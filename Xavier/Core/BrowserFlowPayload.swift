import Foundation

struct BrowserFlowPayload {
    let identifier: String?
    let app: AppName
    let host: String?
    let url: String?
    let httpMethod: String?
    let requestHeaders: [String: String]?
    let requestBody: Data?
    let statusCode: Int32
    let responseHeaders: [String: String]?
    let parentURL: String?
    let contentType: String?
}

struct BrowserEventSnapshot {
    let identifier: String?
    let timestamp: Date
    let app: AppName
    let host: String?
    let url: String?
    let httpMethod: String?
    let requestHeaders: String?
    let requestBody: String?
    let statusCode: Int32
    let responseHeaders: String?
    let parentURL: String?
    let contentType: String?
}

struct BrowserHostSummary {
    let host: String
    let lastTimestamp: Date
    let requestCount: Int
    let methods: Set<String>
    let apps: Set<String>
}