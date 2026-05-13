import Foundation
import Network
import NetworkExtension
import Security

final class TLSProxy {
    private let certificateManager = CertificateManager.shared
    private var activeRelay: TLSRelay?
    private var activeHTTPObserver: HTTPObserver?

    enum TLSResult {
        case completed(InspectedRequestPayload)
        case pinningDetected(hostname: String)
        case passthrough(hostname: String, port: UInt16)
        case error(Error)
    }

    func proxyFlow(_ flow: NEAppProxyTCPFlow,
                   hostname: String,
                   port: UInt16,
                   flowID: UUID,
                   appID: String,
                   completion: @escaping (TLSProxy.TLSResult) -> Void) {
        if port == 443 && !hostname.isEmpty {
            if certificateManager.isPinnedDomain(hostname) {
                completion(.passthrough(hostname: hostname, port: port))
                return
            }
            proxyHTTPSFlow(flow, hostname: hostname, flowID: flowID, appID: appID, completion: completion)
        } else if port == 80 {
            proxyHTTPFlow(flow, hostname: hostname, flowID: flowID, appID: appID, completion: completion)
        } else {
            completion(.passthrough(hostname: hostname, port: port))
        }
    }

    private func proxyHTTPSFlow(_ flow: NEAppProxyTCPFlow,
                                hostname: String,
                                flowID: UUID,
                                appID: String,
                                completion: @escaping (TLSProxy.TLSResult) -> Void) {
        do {
            if !certificateManager.isRootCACreated {
                try certificateManager.createRootCA()
            }
            let (identity, _) = try certificateManager.generateLeafCertificate(for: hostname)
            let relay = TLSRelay(flow: flow, hostname: hostname, port: 443, identity: identity, flowID: flowID, appID: appID)
            activeRelay = relay
            relay.start { [weak self] result in
                self?.activeRelay = nil
                switch result {
                case .completed:
                    completion(result)
                case .pinningDetected(let host):
                    self?.certificateManager.markAsPinned(host)
                    completion(result)
                case .passthrough, .error:
                    completion(result)
                }
            }
        } catch {
            NSLog("[XavierProxy][TLS] Cert generation failed for %@: %@", hostname, error.localizedDescription)
            completion(.error(error))
        }
    }

    private func proxyHTTPFlow(_ flow: NEAppProxyTCPFlow,
                               hostname: String,
                               flowID: UUID,
                               appID: String,
                               completion: @escaping (TLSProxy.TLSResult) -> Void) {
        let observer = HTTPObserver(flow: flow, hostname: hostname, port: 80, flowID: flowID, appID: appID)
        activeHTTPObserver = observer
        observer.start { result in
            self.activeHTTPObserver = nil
            switch result {
            case .completed(let payload):
                completion(.completed(payload))
            case .passthrough:
                completion(.passthrough(hostname: hostname, port: 80))
            case .pinningDetected:
                completion(.passthrough(hostname: hostname, port: 80))
            case .error:
                completion(.passthrough(hostname: hostname, port: 80))
            }
        }
    }
}

final class TLSRingBuffer {
    var buffer = Data()
    private let capacity: Int
    private var eof = false
    private let lock = NSLock()
    private let available = DispatchSemaphore(value: 0)

    init(capacity: Int) {
        self.capacity = capacity
    }

    func write(_ data: Data) {
        lock.lock()
        let availableSpace = capacity - buffer.count
        if data.count <= availableSpace {
            buffer.append(data)
        } else if availableSpace > 0 {
            buffer.append(data.prefix(availableSpace))
        }
        lock.unlock()
        available.signal()
    }

    func read(into: UnsafeMutableRawPointer, maxLength: Int) -> Int {
        lock.lock()
        while buffer.isEmpty && !eof {
            lock.unlock()
            available.wait()
            lock.lock()
        }
        if buffer.isEmpty && eof {
            lock.unlock()
            return 0
        }
        let count = min(maxLength, buffer.count)
        buffer.copyBytes(to: into.assumingMemoryBound(to: UInt8.self), count: count)
        buffer = Data(buffer[count...])
        lock.unlock()
        return count
    }

    func readAvailable(into: UnsafeMutableRawPointer, maxLength: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return 0 }
        let count = min(maxLength, buffer.count)
        buffer.copyBytes(to: into.assumingMemoryBound(to: UInt8.self), count: count)
        buffer = Data(buffer[count...])
        return count
    }

    func markEOF() {
        lock.lock()
        eof = true
        lock.unlock()
        available.signal()
    }

    var isEOF: Bool {
        lock.lock()
        defer { lock.unlock() }
        return eof && buffer.isEmpty
    }

    var pendingByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }
}

final class TLSRelay {
    private let flow: NEAppProxyTCPFlow
    private let hostname: String
    private let port: UInt16
    private let identity: SecIdentity
    private let flowID: UUID
    private let appID: String
    private let queue = DispatchQueue(label: "\(Constants.appBundleIdentifier).tlsrelay", qos: .utility)

    var fromAppBuffer = TLSRingBuffer(capacity: 1 << 17)
    var toAppBuffer = TLSRingBuffer(capacity: 1 << 17)
    private var clientConnection: NWConnection?

    private var requestMetadata: HTTPRequestMetadata?
    private var requestCapturedBody: Data?
    private var responseMetadata: HTTPResponseMetadata?
    private var responseCapturedBody: Data?
    private var originalRequestHeaders: [String: String]?
    private var originalRequestBody: Data?
    private var originalResponseHeaders: [String: String]?
    private var originalResponseBody: Data?
    private var requestModified = false
    private var responseModified = false
    private var startTime = Date()
    private var tlsVersion = "TLS"
    private var blockedScriptCount = 0
    private var requestHeaderBuffer = Data()
    private var responseHeaderBuffer = Data()
    private var didLogFirstAppRead = false
    private var didLogFirstServerRead = false
    private var completion: ((TLSProxy.TLSResult) -> Void)?
    private var handshakeCompleted = false
    private var serverReadStarted = false
    private var isAdvancingState = false
    private var needsAnotherAdvance = false
    private var finished = false

    private var sslContext: SSLContext?

    init(flow: NEAppProxyTCPFlow, hostname: String, port: UInt16, identity: SecIdentity, flowID: UUID, appID: String) {
        self.flow = flow
        self.hostname = hostname
        self.port = port
        self.identity = identity
        self.flowID = flowID
        self.appID = appID
    }

    func start(completion: @escaping (TLSProxy.TLSResult) -> Void) {
        startTime = Date()
        self.completion = completion
        log("start host=\(hostname) port=\(port)")

        flow.open(withLocalEndpoint: nil) { [weak self] error in
            guard let self = self else {
                completion(.error(TLSProxyError.connectionFailed))
                return
            }
            if let error = error {
                NSLog("[XavierProxy][TLS][%@] Flow open failed: %@", self.flowID.uuidString, error.localizedDescription)
                completion(.error(error))
                return
            }

            self.log("flow open ok")
            self.createServerContextAndConnect(completion: completion)
        }
    }

    private func createServerContextAndConnect(completion: @escaping (TLSProxy.TLSResult) -> Void) {
        guard let context = SSLCreateContext(nil, .serverSide, .streamType) else {
            completion(.error(TLSProxyError.contextCreationFailed))
            return
        }
        self.sslContext = context

        var status = SSLSetConnection(context, Unmanaged.passUnretained(self).toOpaque())
        guard status == errSecSuccess else {
            completion(.error(TLSProxyError.setupFailed(status)))
            return
        }

        status = SSLSetIOFuncs(context, tlsReadCallback, tlsWriteCallback)
        guard status == errSecSuccess else {
            completion(.error(TLSProxyError.setupFailed(status)))
            return
        }

        var identityArray: [SecIdentity] = [identity]
        status = SSLSetCertificate(context, identityArray as CFArray)
        guard status == errSecSuccess else {
            completion(.error(TLSProxyError.setupFailed(status)))
            return
        }

        let alpnCFArray = ["http/1.1"] as CFArray
        status = SSLSetALPNProtocols(context, alpnCFArray)
        if status != errSecSuccess {
            log("warning: failed to set ALPN protocol to http/1.1 (status=\(status))")
        }

        log("tls server context configured")

        connectToRealServer { [weak self] connection in
            guard let self = self else {
                completion(.error(TLSProxyError.connectionFailed))
                return
            }
            self.clientConnection = connection
            self.log("upstream connection ready")
            self.beginReadingFromFlow()
            self.queue.async { [weak self] in
                self?.advanceTLSState()
            }
        }
    }

    private func connectToRealServer(completion: @escaping (NWConnection) -> Void) {
        guard let nwPort = Network.NWEndpoint.Port(rawValue: port) else {
            NSLog("[XavierProxy][TLS][%@] Invalid port %d", flowID.uuidString, Int(port))
            return
        }

        let tlsOptions = NWProtocolTLS.Options()
        "http/1.1".withCString {
            sec_protocol_options_add_tls_application_protocol(tlsOptions.securityProtocolOptions, $0)
        }

        let parameters = NWParameters(tls: tlsOptions)

        let endpoint = Network.NWEndpoint.hostPort(host: Network.NWEndpoint.Host(hostname), port: nwPort)
        let connection = NWConnection(to: endpoint, using: parameters)

        connection.stateUpdateHandler = { (state: NWConnection.State) in
            switch state {
            case .ready:
                self.log("upstream state ready")
                completion(connection)
            case .failed(let error):
                NSLog("[XavierProxy][TLS][%@] Server connection failed: %@", self.flowID.uuidString, error.localizedDescription)
            case .cancelled:
                self.log("upstream state cancelled")
                break
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func beginReadingFromFlow() {
        flow.readData { [weak self] data, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                if !self.didLogFirstAppRead {
                    self.didLogFirstAppRead = true
                    self.log("first app bytes count=\(data.count)")
                }
                self.fromAppBuffer.write(data)
                self.queue.async { [weak self] in
                    self?.advanceTLSState()
                }
            }
            if let error = error {
                self.log("app read ended error=\(String(describing: error))")
                self.fromAppBuffer.markEOF()
                self.queue.async { [weak self] in
                    self?.advanceTLSState()
                }
                return
            }
            if data == nil {
                self.log("app read ended eof")
                self.fromAppBuffer.markEOF()
                self.queue.async { [weak self] in
                    self?.advanceTLSState()
                }
                return
            }
            self.beginReadingFromFlow()
        }
    }

    private func advanceTLSState() {
        guard !finished else { return }
        guard let context = sslContext else { return }

        if isAdvancingState {
            needsAnotherAdvance = true
            return
        }

        isAdvancingState = true
        defer {
            isAdvancingState = false
            if needsAnotherAdvance {
                needsAnotherAdvance = false
                queue.async { [weak self] in
                    self?.advanceTLSState()
                }
            }
        }

        if !handshakeCompleted {
            advanceHandshake(context: context)
            if !handshakeCompleted || finished {
                return
            }
        }

        processClientTLSData(context: context)
    }

    private func advanceHandshake(context: SSLContext) {
        log("handshake advance")
        while !finished {
            let beforeInput = fromAppBuffer.pendingByteCount
            let status = SSLHandshake(context)
            let flushedBytes = drainToAppBuffer()

            if status == errSecSuccess {
                handshakeCompleted = true
                var protocolVersion: SSLProtocol = SSLProtocol(rawValue: 8)!
                SSLGetNegotiatedProtocolVersion(context, &protocolVersion)
                switch protocolVersion.rawValue {
                case 7: tlsVersion = "TLS 1.1"
                case 8: tlsVersion = "TLS 1.2"
                case 10: tlsVersion = "TLS 1.3"
                case 2: tlsVersion = "SSL 3.0"
                default: tlsVersion = "TLS"
                }
                log("handshake success protocol=\(tlsVersion)")
                startServerReadsIfNeeded(context: context)
                return
            }

            if status == errSSLWouldBlock {
                let afterInput = fromAppBuffer.pendingByteCount
                if beforeInput != afterInput || flushedBytes > 0 {
                    continue
                }
                return
            }

            NSLog("[XavierProxy][TLS][%@] Handshake failed: %d", flowID.uuidString, Int(status))
            finish(.error(TLSProxyError.handshakeFailed(status)))
            return
        }
    }

    private func startServerReadsIfNeeded(context: SSLContext) {
        guard !serverReadStarted else { return }
        serverReadStarted = true

        let blockedPatterns = Set(BlocklistMatcher.loadEnabledPatterns())
        let stripConfiguration = ScriptStrippingManager.shared.hostConfiguration(for: hostname)
        readFromServerAsync(context: context, blockedPatterns: blockedPatterns, stripConfiguration: stripConfiguration)
    }

    private func processClientTLSData(context: SSLContext) {
        let readBufferSize = 32768
        var buffer = [UInt8](repeating: 0, count: readBufferSize)

        while !finished {
            let beforeInput = fromAppBuffer.pendingByteCount
            var bytesRead = 0
            let status = SSLRead(context, &buffer, readBufferSize, &bytesRead)
            let flushedBytes = drainToAppBuffer()

            if bytesRead > 0 {
                let plaintext = Data(buffer[..<bytesRead])
                handleClientPlaintext(plaintext)
            }

            if status == errSecSuccess {
                continue
            }

            if status == errSSLWouldBlock {
                let afterInput = fromAppBuffer.pendingByteCount
                if bytesRead > 0 || beforeInput != afterInput || flushedBytes > 0 {
                    continue
                }
                return
            }

            if status == errSSLClosedGraceful {
                log("client tls closed gracefully")
                return
            }

            NSLog("[XavierProxy][TLS][%@] SSLRead failed: %d", flowID.uuidString, Int(status))
            finish(.error(TLSProxyError.handshakeFailed(status)))
            return
        }
    }

    private func handleClientPlaintext(_ plaintext: Data) {
        if requestMetadata == nil {
            requestHeaderBuffer.append(plaintext)
            if let (meta, headerEnd) = HTTPParser.parseRequestHeaders(from: requestHeaderBuffer) {
                requestMetadata = meta
                originalRequestHeaders = meta.headers
                let bodyData = requestHeaderBuffer[headerEnd...]
                if !bodyData.isEmpty {
                    originalRequestBody = HTTPParser.truncate(Data(bodyData))
                    requestCapturedBody = HTTPParser.truncate(Data(bodyData))
                }

                if HTTPParser.isUpgradeRequest(meta) {
                    finish(.passthrough(hostname: hostname, port: port))
                    return
                }

                requestHeaderBuffer.removeAll(keepingCapacity: true)
            } else if requestHeaderBuffer.count > HTTPParser.maxBodyCaptureSize {
                requestHeaderBuffer = HTTPParser.truncate(requestHeaderBuffer)
            }
        } else {
            appendCapturedBodyChunk(plaintext, to: &requestCapturedBody)
        }

        sendToServer(plaintext)
    }

    @discardableResult
    private func drainToAppBuffer() -> Int {
        var flushedBytes = 0
        while true {
            var writeBuffer = [UInt8](repeating: 0, count: 32768)
            let count = toAppBuffer.readAvailable(into: &writeBuffer, maxLength: 32768)
            if count == 0 { break }
            flushedBytes += count
            let data = Data(writeBuffer[..<count])
            let semaphore = DispatchSemaphore(value: 0)
            flow.write(data) { _ in
                semaphore.signal()
            }
            semaphore.wait()
        }
        if flushedBytes > 0 {
            log("flushed to app bytes=\(flushedBytes)")
        }
        return flushedBytes
    }

    private func sendToServer(_ data: Data) {
        clientConnection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func readFromServerAsync(context: SSLContext, blockedPatterns: Set<String>, stripConfiguration: ScriptStrippingHost?) {
        guard let connection = clientConnection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                if !self.didLogFirstServerRead {
                    self.didLogFirstServerRead = true
                    self.log("first server bytes count=\(data.count)")
                }
                self.processServerData(data, context: context, blockedPatterns: blockedPatterns, stripConfiguration: stripConfiguration)
            }
            if isComplete || error != nil {
                self.log("server read ended isComplete=\(isComplete) error=\(String(describing: error))")
                self.finishCompletedIfPossible()
                return
            }
            self.readFromServerAsync(context: context, blockedPatterns: blockedPatterns, stripConfiguration: stripConfiguration)
        }
    }

    private func processServerData(_ data: Data, context: SSLContext, blockedPatterns: Set<String>, stripConfiguration: ScriptStrippingHost?) {
        if responseMetadata == nil {
            responseHeaderBuffer.append(data)
            if let (meta, headerEnd) = HTTPParser.parseResponseHeaders(from: responseHeaderBuffer) {
                responseMetadata = meta
                originalResponseHeaders = meta.headers
                let bodyData = responseHeaderBuffer[headerEnd...]
                if !bodyData.isEmpty {
                    let capturedBody = Data(bodyData)
                    originalResponseBody = HTTPParser.truncate(capturedBody)
                    responseCapturedBody = HTTPParser.truncate(capturedBody)
                }

                var forwardData = responseHeaderBuffer
                var finalHeaders = meta.headers
                var finalBody: Data? = nil

                if stripConfiguration != nil && HTTPParser.isHTMLResponse(meta) && responseHeaderBuffer.count < ResponseModifier.maxModifiableBodySize {
                    if let result = ResponseModifier.modifyResponse(
                        body: responseHeaderBuffer,
                        headers: meta.headers,
                        host: hostname,
                        blockedDomains: blockedPatterns,
                        stripConfiguration: stripConfiguration
                    ), let modifiedBody = result.modifiedBody {
                        finalHeaders = result.modifiedHeaders ?? finalHeaders
                        finalBody = modifiedBody
                        responseModified = result.wasModified
                        blockedScriptCount = result.strippedScriptCount
                    }
                }

                // Force Connection: close
                let connectionKeys = finalHeaders.keys.filter { $0.lowercased() == "connection" }
                for key in connectionKeys {
                    finalHeaders.removeValue(forKey: key)
                }
                finalHeaders["Connection"] = "close"

                let headerStr = HTTPParser.serializeHeaders(finalHeaders)
                var headerData = "HTTP/\(meta.httpVersion) \(meta.statusCode) \(meta.reasonPhrase)\r\n".data(using: .utf8)!
                headerData.append(headerStr.data(using: .utf8)!)
                headerData.append("\r\n\r\n".data(using: .utf8)!)
                
                if let body = finalBody {
                    headerData.append(body)
                } else if responseHeaderBuffer.count > headerEnd {
                    headerData.append(responseHeaderBuffer[headerEnd...])
                }
                
                forwardData = headerData
                responseHeaderBuffer.removeAll(keepingCapacity: true)

                forwardData.withUnsafeBytes { rawBuffer in
                    var written = 0
                    SSLWrite(context, rawBuffer.baseAddress, forwardData.count, &written)
                }
                drainToAppBuffer()
                return
            } else if responseHeaderBuffer.count > ResponseModifier.maxModifiableBodySize {
                responseHeaderBuffer = HTTPParser.truncate(responseHeaderBuffer, maxLength: ResponseModifier.maxModifiableBodySize)
            }
        } else {
            appendCapturedBodyChunk(data, to: &responseCapturedBody)
        }

        data.withUnsafeBytes { rawBuffer in
            var written = 0
            SSLWrite(context, rawBuffer.baseAddress, data.count, &written)
        }
        drainToAppBuffer()
    }

    private func buildPayload(duration: TimeInterval) -> InspectedRequestPayload {
        return InspectedRequestPayload(
            identifier: flowID.uuidString,
            appName: appID,
            appBundleID: appID,
            host: hostname,
            url: requestMetadata?.url,
            httpMethod: requestMetadata?.method,
            requestHeaders: requestMetadata?.headers,
            requestBody: requestCapturedBody,
            statusCode: Int32(responseMetadata?.statusCode ?? 0),
            responseHeaders: responseMetadata?.headers,
            responseBody: responseCapturedBody,
            contentType: responseMetadata?.contentType,
            duration: duration,
            tlsVersion: tlsVersion,
            port: Int32(port),
            pinned: false,
            blocked: false,
            blockedReason: blockedScriptCount > 0 ? "script_stripped" : nil,
            responseModified: responseModified,
            requestModified: requestModified,
            originalRequestHeaders: originalRequestHeaders,
            originalRequestBody: originalRequestBody,
            originalResponseHeaders: originalResponseHeaders,
            originalResponseBody: originalResponseBody
        )
    }

    private func finishCompletedIfPossible() {
        guard !finished else { return }
        finish(.completed(buildPayload(duration: Date().timeIntervalSince(startTime))))
    }

    private func finish(_ result: TLSProxy.TLSResult) {
        guard !finished else { return }
        finished = true
        clientConnection?.cancel()
        toAppBuffer.markEOF()
        flow.closeReadWithError(nil)
        flow.closeWriteWithError(nil)
        completion?(result)
        completion = nil
    }

    func scheduleAdvanceTLSState() {
        queue.async { [weak self] in
            self?.advanceTLSState()
        }
    }

    private func log(_ message: String) {
        NSLog("[XavierProxy][TLS][%@] %@", flowID.uuidString, message)
    }

    private func appendCapturedBodyChunk(_ chunk: Data, to body: inout Data?) {
        guard !chunk.isEmpty else { return }
        if body == nil {
            body = Data()
        }
        let remainingBytes = max(0, HTTPParser.maxBodyCaptureSize - (body?.count ?? 0))
        guard remainingBytes > 0 else { return }
        body?.append(chunk.prefix(remainingBytes))
    }
}

private func tlsReadCallback(connection: SSLConnectionRef,
                              data: UnsafeMutableRawPointer,
                              dataLength: UnsafeMutablePointer<Int>) -> OSStatus {
    guard let context = Unmanaged<TLSRelay>.fromOpaque(connection).takeUnretainedValue() as TLSRelay? else {
        dataLength.pointee = 0
        return errSSLClosedAbort
    }
    let bytesRead = context.fromAppBuffer.readAvailable(into: data, maxLength: dataLength.pointee)
    dataLength.pointee = bytesRead
    if bytesRead == 0 {
        if context.fromAppBuffer.isEOF {
            return errSSLClosedGraceful
        }
        return errSSLWouldBlock
    }
    return errSecSuccess
}

private func tlsWriteCallback(connection: SSLConnectionRef,
                               data: UnsafeRawPointer,
                               dataLength: UnsafeMutablePointer<Int>) -> OSStatus {
    guard let context = Unmanaged<TLSRelay>.fromOpaque(connection).takeUnretainedValue() as TLSRelay? else {
        dataLength.pointee = 0
        return errSSLClosedAbort
    }
    let bytesToWrite = Data(bytes: data, count: dataLength.pointee)
    context.toAppBuffer.write(bytesToWrite)
    context.scheduleAdvanceTLSState()
    dataLength.pointee = bytesToWrite.count
    return errSecSuccess
}

final class HTTPObserver {
    private let flow: NEAppProxyTCPFlow
    private let hostname: String
    private let port: UInt16
    private let flowID: UUID
    private let appID: String
    private let queue = DispatchQueue(label: "\(Constants.appBundleIdentifier).httpobserver", qos: .utility)

    private var outboundConnection: NWConnection?
    private var requestMetadata: HTTPRequestMetadata?
    private var responseMetadata: HTTPResponseMetadata?
    private var requestCapturedBody: Data?
    private var responseCapturedBody: Data?
    private var originalRequestHeaders: [String: String]?
    private var originalRequestBody: Data?
    private var originalResponseHeaders: [String: String]?
    private var originalResponseBody: Data?
    private var requestModified = false
    private var responseModified = false
    private var startTime = Date()
    private var blockedScriptCount = 0
    private var requestHeaderBuffer = Data()
    private var responseHeaderBuffer = Data()

    init(flow: NEAppProxyTCPFlow, hostname: String, port: UInt16, flowID: UUID, appID: String) {
        self.flow = flow
        self.hostname = hostname
        self.port = port
        self.flowID = flowID
        self.appID = appID
    }

    func start(completion: @escaping (TLSProxy.TLSResult) -> Void) {
        startTime = Date()

        flow.open(withLocalEndpoint: nil) { [weak self] error in
            guard let self = self else {
                completion(.error(TLSProxyError.connectionFailed))
                return
            }
            if let error = error {
                completion(.error(error))
                return
            }

            guard let port = Network.NWEndpoint.Port(rawValue: self.port) else {
                completion(.error(TLSProxyError.connectionFailed))
                return
            }
            let hostname: String
            if let remoteHost = flow.remoteHostname, !remoteHost.isEmpty {
                hostname = remoteHost
            } else if let endpoint = flow.remoteEndpoint as? NWHostEndpoint {
                hostname = endpoint.hostname
            } else {
                completion(.error(TLSProxyError.connectionFailed))
                return
            }
            let endpoint = Network.NWEndpoint.hostPort(host: Network.NWEndpoint.Host(hostname), port: port)
            let connection = NWConnection(to: endpoint, using: .tcp)
            self.outboundConnection = connection

connection.stateUpdateHandler = { (state: NWConnection.State) in
                switch state {
                case .ready:
                    self.relayHTTP(completion: completion)
                case .failed, .cancelled:
                    completion(.passthrough(hostname: self.hostname, port: self.port))
                default:
                    break
                }
            }
            connection.start(queue: self.queue)
        }
    }

    private func relayHTTP(completion: @escaping (TLSProxy.TLSResult) -> Void) {
        readFromAppAndForward(completion: completion)
    }

    private func readFromAppAndForward(completion: @escaping (TLSProxy.TLSResult) -> Void) {
        flow.readData { [weak self] data, error in
            guard let self = self else { return }
            if let error = error {
                self.finishHTTP(completion: completion)
                return
            }
            guard let data = data, !data.isEmpty else {
                self.finishHTTP(completion: completion)
                return
            }

            let rules = ModificationRuleManager.shared.fetchEnabledRules()
            let blockedPatterns = BlocklistMatcher.loadEnabledPatterns()

            if self.requestMetadata == nil {
                self.requestHeaderBuffer.append(data)
                if let (meta, headerEnd) = HTTPParser.parseRequestHeaders(from: self.requestHeaderBuffer) {
                    self.requestMetadata = meta
                    self.originalRequestHeaders = meta.headers
                    let bodyData = self.requestHeaderBuffer[headerEnd...]
                    if !bodyData.isEmpty {
                        let capturedBody = Data(bodyData)
                        self.originalRequestBody = HTTPParser.truncate(capturedBody)
                        self.requestCapturedBody = HTTPParser.truncate(capturedBody)
                    }
                    self.requestHeaderBuffer.removeAll(keepingCapacity: true)

                    if HTTPParser.isUpgradeRequest(meta) {
                        self.sendToServer(data) {
                            let copyManager = FlowCopyManager(flowID: self.flowID, tcpFlow: self.flow)
                            copyManager.startPassthroughTCP(onComplete: {})
                        }
                        completion(.passthrough(hostname: self.hostname, port: self.port))
                        return
                    }

                    let matchingRules = rules.filter { $0.host == self.hostname || $0.host == "*" }
                    var finalHeaders = meta.headers
                    var finalBody = self.originalRequestBody
                    var finalURL = meta.url
                    var wasModified = false
                    
                    if !matchingRules.isEmpty {
                        let mod = RequestModifier.modifyRequest(
                            request: meta,
                            originalBody: self.originalRequestBody,
                            host: self.hostname,
                            rules: matchingRules
                        )
                        if mod.wasModified {
                            self.requestModified = true
                            finalHeaders = mod.modifiedHeaders ?? finalHeaders
                            finalBody = mod.modifiedBody ?? finalBody
                            finalURL = mod.modifiedURL ?? finalURL
                            wasModified = true
                        }
                    }

                    // Force Connection: close to break HTTP keep-alive multiplexing
                    let connectionKeys = finalHeaders.keys.filter { $0.lowercased() == "connection" }
                    for key in connectionKeys {
                        finalHeaders.removeValue(forKey: key)
                    }
                    finalHeaders["Connection"] = "close"
                    
                    let rebuilt = HTTPParser.buildHTTPRequest(
                        method: meta.method,
                        url: finalURL,
                        httpVersion: meta.httpVersion,
                        headers: finalHeaders,
                        body: finalBody
                    )
                    
                    self.sendToServer(rebuilt)
                    return
                } else if self.requestHeaderBuffer.count > HTTPParser.maxBodyCaptureSize {
                    self.requestHeaderBuffer = HTTPParser.truncate(self.requestHeaderBuffer)
                }
            } else {
                self.appendCapturedBodyChunk(data, to: &self.requestCapturedBody)
            }

            self.sendToServer(data) {
                self.readFromAppAndForward(completion: completion)
            }
        }
    }

    private func readResponseFromServer(completion: @escaping (TLSProxy.TLSResult) -> Void) {
        guard let connection = outboundConnection else {
            completion(.passthrough(hostname: hostname, port: port))
            return
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            let responseComplete = isComplete || error != nil
            if let data = data, !data.isEmpty {
                self.processHTTPResponse(data, responseComplete: responseComplete, completion: completion)
            } else {
                self.finishHTTP(completion: completion)
            }
        }
    }

    private func processHTTPResponse(_ data: Data, responseComplete: Bool, completion: @escaping (TLSProxy.TLSResult) -> Void) {
        let stripConfiguration = ScriptStrippingManager.shared.hostConfiguration(for: hostname)
        let blockedPatterns = BlocklistMatcher.loadEnabledPatterns()

        if responseMetadata == nil {
            responseHeaderBuffer.append(data)
            if let (meta, headerEnd) = HTTPParser.parseResponseHeaders(from: responseHeaderBuffer) {
                responseMetadata = meta
                originalResponseHeaders = meta.headers
                let bodyData = responseHeaderBuffer[headerEnd...]
                if !bodyData.isEmpty {
                    let capturedBody = Data(bodyData)
                    originalResponseBody = HTTPParser.truncate(capturedBody)
                    responseCapturedBody = HTTPParser.truncate(capturedBody)
                }

                var forwardData = responseHeaderBuffer
                var finalHeaders = meta.headers
                var finalBody: Data? = nil

                if stripConfiguration != nil && HTTPParser.isHTMLResponse(meta) {
                    if let result = ResponseModifier.modifyResponse(
                        body: responseHeaderBuffer,
                        headers: meta.headers,
                        host: hostname,
                        blockedDomains: Set(blockedPatterns),
                        stripConfiguration: stripConfiguration
                    ), let modifiedBody = result.modifiedBody {
                        finalHeaders = result.modifiedHeaders ?? finalHeaders
                        finalBody = modifiedBody
                        responseModified = result.wasModified
                        blockedScriptCount = result.strippedScriptCount
                    }
                }
                
                // Force Connection: close
                let connectionKeys = finalHeaders.keys.filter { $0.lowercased() == "connection" }
                for key in connectionKeys {
                    finalHeaders.removeValue(forKey: key)
                }
                finalHeaders["Connection"] = "close"

                let headerStr = HTTPParser.serializeHeaders(finalHeaders)
                var headerData = "HTTP/\(meta.httpVersion) \(meta.statusCode) \(meta.reasonPhrase)\r\n".data(using: .utf8)!
                headerData.append(headerStr.data(using: .utf8)!)
                headerData.append("\r\n\r\n".data(using: .utf8)!)
                
                if let body = finalBody {
                    headerData.append(body)
                } else if responseHeaderBuffer.count > headerEnd {
                    headerData.append(responseHeaderBuffer[headerEnd...])
                }
                
                forwardData = headerData
                responseHeaderBuffer.removeAll(keepingCapacity: true)

                flow.write(forwardData) { [weak self] _ in
                    guard let self = self else { return }
                    if responseComplete {
                        self.finishHTTP(completion: completion)
                    } else {
                        self.continueReadingResponse(completion: completion)
                    }
                }
                return
            } else if responseHeaderBuffer.count > ResponseModifier.maxModifiableBodySize {
                responseHeaderBuffer = HTTPParser.truncate(responseHeaderBuffer, maxLength: ResponseModifier.maxModifiableBodySize)
            }
        } else {
            appendCapturedBodyChunk(data, to: &responseCapturedBody)
        }

        flow.write(data) { [weak self] _ in
            guard let self = self else { return }
            self.continueReadingResponse(completion: completion)
        }
    }

    private func continueReadingResponse(completion: @escaping (TLSProxy.TLSResult) -> Void) {
        guard let connection = outboundConnection else {
            finishHTTP(completion: completion)
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            let responseComplete = isComplete || error != nil
            if let data = data, !data.isEmpty {
                self.flow.write(data) { [weak self] _ in
                    guard let self = self else { return }
                    if responseComplete {
                        self.finishHTTP(completion: completion)
                    } else {
                        self.continueReadingResponse(completion: completion)
                    }
                }
            } else {
                self.finishHTTP(completion: completion)
            }
        }
    }

    private func sendToServer(_ data: Data, completion: @escaping () -> Void = {}) {
        outboundConnection?.send(content: data, completion: .contentProcessed { _ in completion() })
    }

    private func finishHTTP(completion: @escaping (TLSProxy.TLSResult) -> Void) {
        let duration = Date().timeIntervalSince(startTime)
        let payload = InspectedRequestPayload(
            identifier: flowID.uuidString,
            appName: appID,
            appBundleID: appID,
            host: hostname,
            url: requestMetadata?.url,
            httpMethod: requestMetadata?.method,
            requestHeaders: requestMetadata?.headers,
            requestBody: requestCapturedBody,
            statusCode: Int32(responseMetadata?.statusCode ?? 0),
            responseHeaders: responseMetadata?.headers,
            responseBody: responseCapturedBody,
            contentType: responseMetadata?.contentType,
            duration: duration,
            tlsVersion: nil,
            port: Int32(port),
            pinned: false,
            blocked: false,
            blockedReason: blockedScriptCount > 0 ? "script_stripped" : nil,
            responseModified: responseModified,
            requestModified: requestModified,
            originalRequestHeaders: originalRequestHeaders,
            originalRequestBody: originalRequestBody,
            originalResponseHeaders: originalResponseHeaders,
            originalResponseBody: originalResponseBody
        )
        flow.closeReadWithError(nil)
        flow.closeWriteWithError(nil)
        completion(.completed(payload))
    }

    private func appendCapturedBodyChunk(_ chunk: Data, to body: inout Data?) {
        guard !chunk.isEmpty else { return }
        if body == nil {
            body = Data()
        }
        let remainingBytes = max(0, HTTPParser.maxBodyCaptureSize - (body?.count ?? 0))
        guard remainingBytes > 0 else { return }
        body?.append(chunk.prefix(remainingBytes))
    }
}

enum TLSProxyError: Error {
    case contextCreationFailed
    case setupFailed(OSStatus)
    case handshakeFailed(OSStatus)
    case connectionFailed
    case pinningDetected
}
