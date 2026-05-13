import Foundation

struct InspectedRequestPayload {
    let identifier: String?
    let appName: AppName
    let appBundleID: String?
    let host: String?
    let url: String?
    let httpMethod: String?
    let requestHeaders: [String: String]?
    let requestBody: Data?
    let statusCode: Int32
    let responseHeaders: [String: String]?
    let responseBody: Data?
    let contentType: String?
    let duration: Double
    let tlsVersion: String?
    let port: Int32
    let pinned: Bool
    let blocked: Bool
    let blockedReason: String?
    let responseModified: Bool
    let requestModified: Bool
    let originalRequestHeaders: [String: String]?
    let originalRequestBody: Data?
    let originalResponseHeaders: [String: String]?
    let originalResponseBody: Data?
}

struct InspectedRequestSnapshot {
    let identifier: String?
    let timestamp: Date
    let appName: AppName
    let appBundleID: String?
    let host: String?
    let url: String?
    let httpMethod: String?
    let requestHeaders: String?
    let requestBody: Data?
    let statusCode: Int32
    let responseHeaders: String?
    let responseBody: Data?
    let contentType: String?
    let duration: Double
    let tlsVersion: String?
    let port: Int32
    let pinned: Bool
    let blocked: Bool
    let blockedReason: String?
    let responseModified: Bool
    let requestModified: Bool
    let originalRequestHeaders: String?
    let originalRequestBody: Data?
    let originalResponseHeaders: String?
    let originalResponseBody: Data?
}

struct InspectorHostSummary {
    let host: String
    let lastTimestamp: Date
    let requestCount: Int
    let methods: Set<String>
    let apps: Set<String>
    let blockedCount: Int
}

struct InspectorAppSummary {
    let appBundleID: String
    let lastTimestamp: Date
    let requestCount: Int
    let hostCount: Int
    let methods: Set<String>
    let blockedCount: Int
}

struct InspectorSiteSummary {
    let site: String
    let lastTimestamp: Date
    let requestCount: Int
    let hostCount: Int
    let methods: Set<String>
    let apps: Set<String>
    let blockedCount: Int
}
