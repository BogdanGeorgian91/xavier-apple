import Foundation

struct UnifiedNetworkEvent {
    let identifier: String?
    let timestamp: Date
    let app: AppName
    let host: String?
    
    // Network Event Data
    let ipAddress: String?
    let port: Int32?
    let localIP: String?
    let localPort: Int32?
    let bytesInbound: Int64
    let bytesOutbound: Int64
    let transportProtocol: String?
    let direction: String?
    
    // Browser Event Data
    let url: String?
    let httpMethod: String?
    let requestHeaders: String?
    let requestBody: String?
    let statusCode: Int32?
    let responseHeaders: String?
    let parentURL: String?
    let contentType: String?
    
    // Convenience
    var methodText: String {
        return httpMethod ?? "FLOW"
    }
    
    var urlText: String {
        guard let urlStr = url, let parsed = URL(string: urlStr) else {
            return host ?? ipAddress ?? "Unknown Host"
        }
        let path = parsed.path.isEmpty ? "/" : parsed.path
        if let query = parsed.query, !query.isEmpty {
            return "\(path)?\(query)"
        }
        return path
    }
    
    var isBrowserFlow: Bool {
        return url != nil || httpMethod != nil || parentURL != nil
    }
}
