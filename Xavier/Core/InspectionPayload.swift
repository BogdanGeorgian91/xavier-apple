import Foundation

public struct InspectedRequestPayload {
    public let identifier: String?
    public let appName: AppName
    public let appBundleID: String?
    public let host: String?
    public let url: String?
    public let httpMethod: String?
    public let requestHeaders: [String: String]?
    public let requestBody: Data?
    public let statusCode: Int32
    public let responseHeaders: [String: String]?
    public let responseBody: Data?
    public let contentType: String?
    public let duration: Double
    public let tlsVersion: String?
    public let port: Int32
    public let pinned: Bool
    public let blocked: Bool
    public let blockedReason: String?
    public let responseModified: Bool
    public let requestModified: Bool
    public let originalRequestHeaders: [String: String]?
    public let originalRequestBody: Data?
    public let originalResponseHeaders: [String: String]?
    public let originalResponseBody: Data?

    public init(identifier: String?, appName: AppName, appBundleID: String?, host: String?, url: String?, httpMethod: String?, requestHeaders: [String: String]?, requestBody: Data?, statusCode: Int32, responseHeaders: [String: String]?, responseBody: Data?, contentType: String?, duration: Double, tlsVersion: String?, port: Int32, pinned: Bool, blocked: Bool, blockedReason: String?, responseModified: Bool, requestModified: Bool, originalRequestHeaders: [String: String]?, originalRequestBody: Data?, originalResponseHeaders: [String: String]?, originalResponseBody: Data?) {
        self.identifier = identifier
        self.appName = appName
        self.appBundleID = appBundleID
        self.host = host
        self.url = url
        self.httpMethod = httpMethod
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.contentType = contentType
        self.duration = duration
        self.tlsVersion = tlsVersion
        self.port = port
        self.pinned = pinned
        self.blocked = blocked
        self.blockedReason = blockedReason
        self.responseModified = responseModified
        self.requestModified = requestModified
        self.originalRequestHeaders = originalRequestHeaders
        self.originalRequestBody = originalRequestBody
        self.originalResponseHeaders = originalResponseHeaders
        self.originalResponseBody = originalResponseBody
    }
}

public struct InspectedRequestSnapshot {
    public let identifier: String?
    public let timestamp: Date
    public let appName: AppName
    public let appBundleID: String?
    public let host: String?
    public let url: String?
    public let httpMethod: String?
    public let requestHeaders: String?
    public let requestBody: Data?
    public let statusCode: Int32
    public let responseHeaders: String?
    public let responseBody: Data?
    public let contentType: String?
    public let duration: Double
    public let tlsVersion: String?
    public let port: Int32
    public let pinned: Bool
    public let blocked: Bool
    public let blockedReason: String?
    public let responseModified: Bool
    public let requestModified: Bool
    public let originalRequestHeaders: String?
    public let originalRequestBody: Data?
    public let originalResponseHeaders: String?
    public let originalResponseBody: Data?
}

public struct InspectorHostSummary {
    public let host: String
    public let lastTimestamp: Date
    public let requestCount: Int
    public let methods: Set<String>
    public let apps: Set<String>
    public let blockedCount: Int

    public init(host: String, lastTimestamp: Date, requestCount: Int, methods: Set<String>, apps: Set<String>, blockedCount: Int) {
        self.host = host
        self.lastTimestamp = lastTimestamp
        self.requestCount = requestCount
        self.methods = methods
        self.apps = apps
        self.blockedCount = blockedCount
    }
}

public struct InspectorAppSummary {
    public let appBundleID: String
    public let lastTimestamp: Date
    public let requestCount: Int
    public let hostCount: Int
    public let methods: Set<String>
    public let blockedCount: Int

    public init(appBundleID: String, lastTimestamp: Date, requestCount: Int, hostCount: Int, methods: Set<String>, blockedCount: Int) {
        self.appBundleID = appBundleID
        self.lastTimestamp = lastTimestamp
        self.requestCount = requestCount
        self.hostCount = hostCount
        self.methods = methods
        self.blockedCount = blockedCount
    }
}

public struct InspectorSiteSummary {
    public let site: String
    public let lastTimestamp: Date
    public let requestCount: Int
    public let hostCount: Int
    public let methods: Set<String>
    public let apps: Set<String>
    public let blockedCount: Int

    public init(site: String, lastTimestamp: Date, requestCount: Int, hostCount: Int, methods: Set<String>, apps: Set<String>, blockedCount: Int) {
        self.site = site
        self.lastTimestamp = lastTimestamp
        self.requestCount = requestCount
        self.hostCount = hostCount
        self.methods = methods
        self.apps = apps
        self.blockedCount = blockedCount
    }
}
