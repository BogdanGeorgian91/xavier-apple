import Foundation

public struct BrowserFlowPayload {
    public let identifier: String?
    public let app: AppName
    public let host: String?
    public let url: String?
    public let httpMethod: String?
    public let requestHeaders: [String: String]?
    public let requestBody: Data?
    public let statusCode: Int32
    public let responseHeaders: [String: String]?
    public let parentURL: String?
    public let contentType: String?

    public init(identifier: String?, app: AppName, host: String?, url: String?, httpMethod: String?, requestHeaders: [String: String]?, requestBody: Data?, statusCode: Int32, responseHeaders: [String: String]?, parentURL: String?, contentType: String?) {
        self.identifier = identifier
        self.app = app
        self.host = host
        self.url = url
        self.httpMethod = httpMethod
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.parentURL = parentURL
        self.contentType = contentType
    }
}

public struct BrowserEventSnapshot {
    public let identifier: String?
    public let timestamp: Date
    public let app: AppName
    public let host: String?
    public let url: String?
    public let httpMethod: String?
    public let requestHeaders: String?
    public let requestBody: String?
    public let statusCode: Int32
    public let responseHeaders: String?
    public let parentURL: String?
    public let contentType: String?

    public init(identifier: String?, timestamp: Date, app: AppName, host: String?, url: String?, httpMethod: String?, requestHeaders: String?, requestBody: String?, statusCode: Int32, responseHeaders: String?, parentURL: String?, contentType: String?) {
        self.identifier = identifier
        self.timestamp = timestamp
        self.app = app
        self.host = host
        self.url = url
        self.httpMethod = httpMethod
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.parentURL = parentURL
        self.contentType = contentType
    }
}

public struct BrowserHostSummary {
    public let host: String
    public let lastTimestamp: Date
    public let requestCount: Int
    public let methods: Set<String>
    public let apps: Set<String>

    public init(host: String, lastTimestamp: Date, requestCount: Int, methods: Set<String>, apps: Set<String>) {
        self.host = host
        self.lastTimestamp = lastTimestamp
        self.requestCount = requestCount
        self.methods = methods
        self.apps = apps
    }
}
