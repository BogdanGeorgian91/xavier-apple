//
//  NetworkEvent+CoreDataProperties.swift
//  Xavier
//
//  Created by OpenCode on 4/5/26.
//

import CoreData
import Foundation

extension NetworkEvent {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<NetworkEvent> {
        return NSFetchRequest<NetworkEvent>(entityName: "NetworkEvent")
    }

    @NSManaged public var app: String?
    @NSManaged public var bytesInbound: Int64
    @NSManaged public var bytesOutbound: Int64
    @NSManaged public var direction: String?
    @NSManaged public var host: String?
    @NSManaged public var identifier: String?
    @NSManaged public var ipAddress: String?
    @NSManaged public var localIP: String?
    @NSManaged public var localPort: Int32
    @NSManaged public var port: Int32
    @NSManaged public var `protocol`: String?
    @NSManaged public var timestamp: Date?
}
