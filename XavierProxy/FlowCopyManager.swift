import Foundation
import Network
import NetworkExtension

final class FlowCopyManager {
    private let flowID: UUID
    private let tcpFlow: NEAppProxyTCPFlow?
    private let udpFlow: NEAppProxyUDPFlow?
    private struct UDPEndpoint {
        let host: String
        let port: UInt16
    }
    private var udpRemoteEndpoints: [UDPEndpoint]?
    private let queue = DispatchQueue(label: "\(Constants.appBundleIdentifier).proxy.flowcopy", qos: .utility)

    private var outboundConnection: NWConnection?
    private var cancelled = false
    private var finished = false

    init(flowID: UUID, tcpFlow: NEAppProxyTCPFlow) {
        self.flowID = flowID
        self.tcpFlow = tcpFlow
        self.udpFlow = nil
        self.udpRemoteEndpoints = nil
    }

    init(flowID: UUID, udpFlow: NEAppProxyUDPFlow) {
        self.flowID = flowID
        self.tcpFlow = nil
        self.udpFlow = udpFlow
        self.udpRemoteEndpoints = nil
    }

    func startPassthroughTCP(onComplete: @escaping () -> Void) {
        guard let tcpFlow = tcpFlow else {
            onComplete()
            return
        }

        guard let host = extractHostname(from: tcpFlow),
              let port = Network.NWEndpoint.Port(rawValue: extractPort(from: tcpFlow)) else {
            log("passthrough open skipped missing endpoint")
            tcpFlow.closeReadWithError(nil)
            tcpFlow.closeWriteWithError(nil)
            finish(onComplete: onComplete)
            return
        }

        log("passthrough open start \(host):\(port.rawValue)")

        tcpFlow.open(withLocalEndpoint: nil) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.log("passthrough open failed \(error.localizedDescription) domain=\((error as NSError).domain) code=\((error as NSError).code)")
                tcpFlow.closeReadWithError(error)
                tcpFlow.closeWriteWithError(error)
                self.finish(onComplete: onComplete)
                return
            }

            self.log("passthrough open ok")

            let endpoint = Network.NWEndpoint.hostPort(host: Network.NWEndpoint.Host(host), port: port)
            let connection = NWConnection(to: endpoint, using: .tcp)
            self.outboundConnection = connection

            connection.stateUpdateHandler = { [weak self] (state: NWConnection.State) in
                guard let self = self else { return }

                switch state {
                case .ready:
                    self.log("ready \(host):\(port.rawValue)")
                    self.startFlowToConnection(tcpFlow: tcpFlow, connection: connection, onComplete: onComplete)
                    self.startConnectionToFlow(tcpFlow: tcpFlow, connection: connection, onComplete: onComplete)
                case .failed(let error):
                    self.log("failed \(error.localizedDescription)")
                    tcpFlow.closeReadWithError(error)
                    tcpFlow.closeWriteWithError(error)
                    self.finish(onComplete: onComplete)
                case .cancelled:
                    self.finish(onComplete: onComplete)
                default:
                    break
                }
            }

            connection.start(queue: self.queue)
        }
    }

    func startPassthroughUDP(onComplete: @escaping () -> Void) {
        guard let udpFlow = udpFlow else {
            onComplete()
            return
        }

        let connection = NWConnection(to: Network.NWEndpoint.hostPort(host: "0.0.0.0", port: 0), using: .udp)
        outboundConnection = connection

        udpFlow.open(withLocalEndpoint: nil) { [weak self] error in
            guard let self = self else { return }
            if error != nil {
                self.finish(onComplete: onComplete)
                return
            }

            connection.stateUpdateHandler = { [weak self] (state: NWConnection.State) in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.startUDPFlowToConnection(udpFlow: udpFlow, connection: connection, onComplete: onComplete)
                    self.startUDPConnectionToFlow(udpFlow: udpFlow, connection: connection, onComplete: onComplete)
                case .failed, .cancelled:
                    self.finish(onComplete: onComplete)
                default:
                    break
                }
            }

            connection.start(queue: self.queue)
        }
    }

    func cancel() {
        cancelled = true
        outboundConnection?.cancel()
        tcpFlow?.closeReadWithError(nil)
        tcpFlow?.closeWriteWithError(nil)
        udpFlow?.closeReadWithError(nil)
        udpFlow?.closeWriteWithError(nil)
    }

    private func startFlowToConnection(tcpFlow: NEAppProxyTCPFlow,
                                       connection: NWConnection,
                                       onComplete: @escaping () -> Void) {
        guard !cancelled else {
            finish(onComplete: onComplete)
            return
        }

        tcpFlow.readData { [weak self] data, error in
            guard let self = self else { return }

            if let error = error {
                tcpFlow.closeReadWithError(error)
                connection.cancel()
                self.finish(onComplete: onComplete)
                return
            }

            guard let data = data, !data.isEmpty else {
                connection.send(content: nil, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                self.finish(onComplete: onComplete)
                return
            }

            connection.send(content: data, completion: .contentProcessed { [weak self] sendError in
                guard let self = self else { return }
                if let sendError = sendError {
                    tcpFlow.closeWriteWithError(sendError)
                    connection.cancel()
                    self.finish(onComplete: onComplete)
                    return
                }

                self.startFlowToConnection(tcpFlow: tcpFlow, connection: connection, onComplete: onComplete)
            })
        }
    }

    private func startConnectionToFlow(tcpFlow: NEAppProxyTCPFlow,
                                       connection: NWConnection,
                                       onComplete: @escaping () -> Void) {
        guard !cancelled else {
            finish(onComplete: onComplete)
            return
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                tcpFlow.closeWriteWithError(error)
                connection.cancel()
                self.finish(onComplete: onComplete)
                return
            }

            if let data = data, !data.isEmpty {
                tcpFlow.write(data) { [weak self] writeError in
                    guard let self = self else { return }
                    if let writeError = writeError {
                        tcpFlow.closeWriteWithError(writeError)
                        connection.cancel()
                        self.finish(onComplete: onComplete)
                        return
                    }

                    if isComplete {
                        connection.cancel()
                        self.finish(onComplete: onComplete)
                        return
                    }

                    self.startConnectionToFlow(tcpFlow: tcpFlow, connection: connection, onComplete: onComplete)
                }
                return
            }

            if isComplete {
                connection.cancel()
                self.finish(onComplete: onComplete)
                return
            }

            self.startConnectionToFlow(tcpFlow: tcpFlow, connection: connection, onComplete: onComplete)
        }
    }

    private func startUDPFlowToConnection(udpFlow: NEAppProxyUDPFlow,
                                          connection: NWConnection,
                                          onComplete: @escaping () -> Void) {
        guard !cancelled else {
            finish(onComplete: onComplete)
            return
        }

        udpFlow.readDatagrams { [weak self] datagrams, endpoints, error in
            guard let self = self else { return }

            if error != nil {
                connection.cancel()
                self.finish(onComplete: onComplete)
                return
            }

            if let endpoints = endpoints, let first = endpoints.first {
                let host: String
                let port: UInt16
                if let hostEndpoint = first as? NWHostEndpoint {
                    host = hostEndpoint.hostname
                    port = UInt16(hostEndpoint.port) ?? 0
                } else {
                    host = first.debugDescription
                    port = 0
                }
                self.udpRemoteEndpoints = [UDPEndpoint(host: host, port: port)]
            }

            guard let datagrams = datagrams, !datagrams.isEmpty else {
                self.startUDPFlowToConnection(udpFlow: udpFlow, connection: connection, onComplete: onComplete)
                return
            }

            self.sendUDPPackets(datagrams: datagrams, index: 0, connection: connection) { [weak self] sendError in
                guard let self = self else { return }
                if sendError != nil {
                    connection.cancel()
                    self.finish(onComplete: onComplete)
                    return
                }

                if endpoints == nil || endpoints?.isEmpty == true {
                    self.startUDPFlowToConnection(udpFlow: udpFlow, connection: connection, onComplete: onComplete)
                    return
                }

                self.startUDPFlowToConnection(udpFlow: udpFlow, connection: connection, onComplete: onComplete)
            }
        }
    }

    private func startUDPConnectionToFlow(udpFlow: NEAppProxyUDPFlow,
                                          connection: NWConnection,
                                          onComplete: @escaping () -> Void) {
        guard !cancelled else {
            finish(onComplete: onComplete)
            return
        }

        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self = self else { return }

            if error != nil {
                connection.cancel()
                self.finish(onComplete: onComplete)
                return
            }

            guard let data = data, !data.isEmpty else {
                self.startUDPConnectionToFlow(udpFlow: udpFlow, connection: connection, onComplete: onComplete)
                return
            }

            guard let epInfo = udpRemoteEndpoints?.first, epInfo.port > 0 else {
                connection.cancel()
                self.finish(onComplete: onComplete)
                return
            }
            let targetEndpoint = NWHostEndpoint(hostname: epInfo.host, port: String(epInfo.port))
            udpFlow.writeDatagrams([data], sentBy: [targetEndpoint]) { [weak self] writeError in
                guard let self = self else { return }
                if writeError != nil {
                    connection.cancel()
                    self.finish(onComplete: onComplete)
                    return
                }

                self.startUDPConnectionToFlow(udpFlow: udpFlow, connection: connection, onComplete: onComplete)
            }
        }
    }

    private func sendUDPPackets(datagrams: [Data],
                                index: Int,
                                connection: NWConnection,
                                completion: @escaping (NWError?) -> Void) {
        if index >= datagrams.count {
            completion(nil)
            return
        }

        connection.send(content: datagrams[index], completion: .contentProcessed { [weak self] error in
            guard self != nil else { return }
            if let error = error {
                completion(error)
                return
            }
            self?.sendUDPPackets(datagrams: datagrams, index: index + 1, connection: connection, completion: completion)
        })
    }

    private func extractHostname(from flow: NEAppProxyTCPFlow) -> String? {
        if let hostname = flow.remoteHostname, !hostname.isEmpty {
            return hostname
        }
        if let endpoint = flow.remoteEndpoint as? NWHostEndpoint {
            return endpoint.hostname
        }
        return nil
    }

    private func extractPort(from flow: NEAppProxyTCPFlow) -> UInt16 {
        if let endpoint = flow.remoteEndpoint as? NWHostEndpoint,
           let port = UInt16(endpoint.port) {
            return port
        }
        return 443
    }

    private func finish(onComplete: @escaping () -> Void) {
        guard !finished else { return }
        finished = true
        onComplete()
    }

    private func log(_ message: String) {
        NSLog("[XavierProxy][%@: %@]", flowID.uuidString, message)
    }
}
