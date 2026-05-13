import CoreData
import Foundation

extension BrowserEvent {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<BrowserEvent> {
        return NSFetchRequest<BrowserEvent>(entityName: "BrowserEvent")
    }

    @NSManaged public var app: String?
    @NSManaged public var host: String?
    @NSManaged public var urlString: String?
    @NSManaged public var httpMethod: String?
    @NSManaged public var requestHeaders: String?
    @NSManaged public var requestBody: String?
    @NSManaged public var statusCode: Int32
    @NSManaged public var responseHeaders: String?
    @NSManaged public var responseBody: String?
    @NSManaged public var parentURL: String?
    @NSManaged public var contentType: String?
    @NSManaged public var timestamp: Date?
    @NSManaged public var identifier: String?
}