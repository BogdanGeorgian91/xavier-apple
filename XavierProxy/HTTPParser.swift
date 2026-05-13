import Foundation

struct HTTPRequestMetadata {
    let method: String
    let url: String
    let httpVersion: String
    let headers: [String: String]
    let capturedBody: Data?
}

struct HTTPResponseMetadata {
    let statusCode: Int
    let reasonPhrase: String
    let httpVersion: String
    let headers: [String: String]
    let capturedBody: Data?
    let contentType: String?
    let contentLength: Int64?
    let isChunked: Bool
}

final class HTTPParser {
    static let maxBodyCaptureSize = 65536

    static func parseRequestHeaders(from data: Data) -> (metadata: HTTPRequestMetadata, headerEndIndex: Int)? {
        guard let headerEnd = findHeaderEnd(in: data) else { return nil }

        let headerData = data[..<headerEnd]
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
        guard let requestLine = lines.first, !requestLine.isEmpty else { return nil }

        let requestParts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard requestParts.count >= 2 else { return nil }

        let method = String(requestParts[0])
        let url = String(requestParts[1])
        let httpVersion = requestParts.count >= 3 ? String(requestParts[2]) : "HTTP/1.1"

        var headers = [String: String]()
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        let bodyStart = headerEnd
        let remainingData = data[bodyStart...]
        let capturedBody: Data? = remainingData.isEmpty ? nil : Data(remainingData.prefix(maxBodyCaptureSize))

        return (metadata: HTTPRequestMetadata(
            method: method,
            url: url,
            httpVersion: httpVersion,
            headers: headers,
            capturedBody: capturedBody
        ), headerEndIndex: headerEnd)
    }

    static func parseResponseHeaders(from data: Data) -> (metadata: HTTPResponseMetadata, headerEndIndex: Int)? {
        guard let headerEnd = findHeaderEnd(in: data) else { return nil }

        let headerData = data[..<headerEnd]
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
        guard let statusLine = lines.first, !statusLine.isEmpty else { return nil }

        let statusParts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else { return nil }

        let httpVersion = String(statusParts[0])
        let reasonPhrase = statusParts.count >= 3 ? String(statusParts[2]) : ""

        var headers = [String: String]()
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        let contentType = headers["Content-Type"]
        let contentLength = headers["Content-Length"].flatMap { Int64($0) }
        let isChunked = headers["Transfer-Encoding"]?.lowercased().contains("chunked") ?? false

        let bodyStart = headerEnd
        let remainingData = data[bodyStart...]
        let capturedBody: Data? = remainingData.isEmpty ? nil : Data(remainingData.prefix(maxBodyCaptureSize))

        return (metadata: HTTPResponseMetadata(
            statusCode: statusCode,
            reasonPhrase: reasonPhrase,
            httpVersion: httpVersion,
            headers: headers,
            capturedBody: capturedBody,
            contentType: contentType,
            contentLength: contentLength,
            isChunked: isChunked
        ), headerEndIndex: headerEnd)
    }

    static func isScriptRequest(_ request: HTTPRequestMetadata) -> Bool {
        if let dest = request.headers["Sec-Fetch-Dest"]?.lowercased(), dest == "script" {
            return true
        }
        if let accept = request.headers["Accept"]?.lowercased(), accept.contains("javascript") || accept.contains("ecmascript") {
            return true
        }
        let path = request.url.lowercased()
        return path.hasSuffix(".js") || path.hasSuffix(".mjs")
    }

    static func isHTMLResponse(_ response: HTTPResponseMetadata) -> Bool {
        guard let contentType = response.contentType?.lowercased() else { return false }
        return contentType.contains("text/html")
    }

    static func isUpgradeRequest(_ request: HTTPRequestMetadata) -> Bool {
        return request.headers["Upgrade"] != nil || request.headers["upgrade"] != nil
    }

    static func truncate(_ data: Data, maxLength: Int = maxBodyCaptureSize) -> Data {
        if data.count <= maxLength { return data }
        return data.prefix(maxLength)
    }

    static func serializeHeaders(_ headers: [String: String]) -> String {
        return headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }

    static func hasExpect100Continue(_ request: HTTPRequestMetadata) -> Bool {
        return request.headers["Expect"]?.lowercased() == "100-continue"
    }

    static func buildHTTPRequest(method: String, url: String, httpVersion: String, headers: [String: String], body: Data?) -> Data {
        var request = "\(method) \(url) \(httpVersion)\r\n"
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            request += "\(key): \(value)\r\n"
        }
        request += "\r\n"
        var result = request.data(using: .utf8)!
        if let body = body {
            result.append(body)
        }
        return result
    }

    static func httpResponse100Continue() -> Data {
        return "HTTP/1.1 100 Continue\r\n\r\n".data(using: .utf8)!
    }

    private static func findHeaderEnd(in data: Data) -> Int? {
        let patternRN = Data([0x0D, 0x0A, 0x0D, 0x0A])
        let patternNN = Data([0x0A, 0x0A])
        
        if let range = data.range(of: patternRN) {
            return range.upperBound
        }
        if let range = data.range(of: patternNN) {
            return range.upperBound
        }
        return nil
    }
}