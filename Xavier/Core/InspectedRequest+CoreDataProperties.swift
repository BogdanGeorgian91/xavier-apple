import CoreData
import Foundation

extension InspectedRequest {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<InspectedRequest> {
        return NSFetchRequest<InspectedRequest>(entityName: "InspectedRequest")
    }

    @NSManaged public var identifier: String?
    @NSManaged public var timestamp: Date?
    @NSManaged public var appName: String?
    @NSManaged public var appBundleID: String?
    @NSManaged public var host: String?
    @NSManaged public var url: String?
    @NSManaged public var httpMethod: String?
    @NSManaged public var requestHeaders: String?
    @NSManaged public var requestBody: Data?
    @NSManaged public var statusCode: Int32
    @NSManaged public var responseHeaders: String?
    @NSManaged public var responseBody: Data?
    @NSManaged public var contentType: String?
    @NSManaged public var duration: Double
    @NSManaged public var tlsVersion: String?
    @NSManaged public var port: Int32
    @NSManaged public var pinned: Bool
    @NSManaged public var blocked: Bool
    @NSManaged public var blockedReason: String?
    @NSManaged public var responseModified: Bool
    @NSManaged public var requestModified: Bool
    @NSManaged public var originalRequestHeaders: String?
    @NSManaged public var originalRequestBody: Data?
    @NSManaged public var originalResponseHeaders: String?
    @NSManaged public var originalResponseBody: Data?
}
