import Foundation

public struct UnifiedNetworkEvent {
    public let identifier: String?
    public let timestamp: Date
    public let app: AppName
    public let host: String?
    
    // Network Event Data
    public let ipAddress: String?
    public let port: Int32?
    public let localIP: String?
    public let localPort: Int32?
    public let bytesInbound: Int64
    public let bytesOutbound: Int64
    public let transportProtocol: String?
    public let direction: String?
    
    // Browser Event Data
    public let url: String?
    public let httpMethod: String?
    public let requestHeaders: String?
    public let requestBody: String?
    public let statusCode: Int32?
    public let responseHeaders: String?
    public let parentURL: String?
    public let contentType: String?

    public init(identifier: String?, timestamp: Date, app: AppName, host: String?, ipAddress: String?, port: Int32?, localIP: String?, localPort: Int32?, bytesInbound: Int64, bytesOutbound: Int64, transportProtocol: String?, direction: String?, url: String?, httpMethod: String?, requestHeaders: String?, requestBody: String?, statusCode: Int32?, responseHeaders: String?, parentURL: String?, contentType: String?) {
        self.identifier = identifier
        self.timestamp = timestamp
        self.app = app
        self.host = host
        self.ipAddress = ipAddress
        self.port = port
        self.localIP = localIP
        self.localPort = localPort
        self.bytesInbound = bytesInbound
        self.bytesOutbound = bytesOutbound
        self.transportProtocol = transportProtocol
        self.direction = direction
        self.url = url
        self.httpMethod = httpMethod
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.parentURL = parentURL
        self.contentType = contentType
    }
    
    // Convenience
    public var methodText: String {
        return httpMethod ?? "FLOW"
    }
    
    public var urlText: String {
        guard let urlStr = url, let parsed = URL(string: urlStr) else {
            return host ?? ipAddress ?? "Unknown Host"
        }
        let path = parsed.path.isEmpty ? "/" : parsed.path
        if let query = parsed.query, !query.isEmpty {
            return "\(path)?\(query)"
        }
        return path
    }
    
    public var isBrowserFlow: Bool {
        return url != nil || httpMethod != nil || parentURL != nil
    }
}
