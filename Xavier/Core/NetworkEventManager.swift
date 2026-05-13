//
//  NetworkEventManager.swift
//  Xavier
//
//  Created by OpenCode on 4/5/26.
//

import CoreData
import Foundation
import NetworkExtension

struct NetworkEventPayload {
    let identifier: String?
    let timestamp: Date
    let app: AppName
    let host: String?
    let ipAddress: String?
    let port: Int32?
    let localIP: String?
    let localPort: Int32?
    let bytesInbound: Int64
    let bytesOutbound: Int64
    let transportProtocol: String?
    let direction: String?

    init(identifier: String? = nil,
         timestamp: Date = Date(),
         app: AppName,
         host: String?,
         ipAddress: String?,
         port: Int32?,
         localIP: String? = nil,
         localPort: Int32? = nil,
         bytesInbound: Int64 = 0,
         bytesOutbound: Int64 = 0,
         transportProtocol: String?,
         direction: String?) {
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
    }
}

struct NetworkEventSnapshot {
    let identifier: String?
    let timestamp: Date
    let app: AppName
    let host: String?
    let ipAddress: String?
    let port: Int32?
    let localIP: String?
    let localPort: Int32?
    let bytesInbound: Int64
    let bytesOutbound: Int64
    let transportProtocol: String?
    let direction: String?
}

struct NetworkEventAppSummary {
    let app: AppName
    let lastTimestamp: Date
    let lastHost: String?
    let totalBytesInbound: Int64
    let totalBytesOutbound: Int64
    let eventCount: Int
}

struct NetworkActivityOverview {
    let recentBytesInbound: Int64
    let recentBytesOutbound: Int64
    let activeAppCount: Int
    let recentEventCount: Int
    let newHostCountToday: Int
    let lastActivityTimestamp: Date?
}

struct NetworkEventDashboardData {
    let appSummaries: [NetworkEventAppSummary]
    let activityOverview: NetworkActivityOverview
}

extension NetworkEvent {
    convenience init(payload: NetworkEventPayload, helper context: NSManagedObjectContext) {
        self.init(entity: NSEntityDescription.entity(forEntityName: "NetworkEvent", in: context)!, insertInto: context)

        self.timestamp = payload.timestamp
        self.identifier = payload.identifier
        self.app = payload.app
        self.host = payload.host
        self.ipAddress = payload.ipAddress
        self.port = payload.port ?? 0
        self.localIP = payload.localIP
        self.localPort = payload.localPort ?? 0
        self.bytesInbound = payload.bytesInbound
        self.bytesOutbound = payload.bytesOutbound
        self.direction = payload.direction
        self.`protocol` = payload.transportProtocol
    }

    func toSnapshot() throws -> NetworkEventSnapshot {
        guard let timestamp = timestamp, let app = app else {
            throw NetworkEventManager.Errors.missingObjectField
        }

        return NetworkEventSnapshot(identifier: identifier,
                                    timestamp: timestamp,
                                    app: app,
                                    host: host,
                                    ipAddress: ipAddress,
                                    port: port == 0 ? nil : port,
                                    localIP: localIP,
                                    localPort: localPort == 0 ? nil : localPort,
                                    bytesInbound: bytesInbound,
                                    bytesOutbound: bytesOutbound,
                                    transportProtocol: `protocol`,
                                    direction: direction)
    }
}

final class NetworkEventManager {
    static let shared: NetworkEventManager = {
        do {
            return try NetworkEventManager()
        } catch {
            fatalError("Unable to create NetworkEventManager: \(error)")
        }
    }()

    enum Errors: Error {
        case createDatabase
        case missingObjectField
    }

    private let managedObjectContext: NSManagedObjectContext

    init() throws {
        guard let directoryURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupIdentifier)?
            .appendingPathComponent("data"),
            let modelURL = Bundle.main.url(forResource: "XavierDataModel", withExtension: "momd"),
            let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL) else {
            throw Errors.createDatabase
        }

        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }

        let options = [NSMigratePersistentStoresAutomaticallyOption: true,
                       NSInferMappingModelAutomaticallyOption: true]

        let dbURL = directoryURL.appendingPathComponent("db.sqlite")
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: dbURL, options: options)
        store.didAdd(to: coordinator)

        managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = coordinator
    }

    @discardableResult
    func logEvent(_ payload: NetworkEventPayload) throws -> NetworkEventSnapshot {
        var snapshot: NetworkEventSnapshot?

        try performAndWait {
            let event = NetworkEvent(payload: payload, helper: self.managedObjectContext)
            snapshot = try event.toSnapshot()
        }

        try saveContext()
        return snapshot!
    }

    @discardableResult
    func logFlowMetadata(from flow: NEFilterFlow) throws -> NetworkEventSnapshot? {
        guard let payload = flow.networkEventPayload() else {
            return nil
        }

        return try logEvent(payload)
    }

    func updateLatestMatchingEvent(with payload: NetworkEventPayload) throws {
        var shouldInsert = false

        try performAndWait {
            if let event = try self.latestEvent(matching: payload) {
                event.bytesInbound = payload.bytesInbound
                event.bytesOutbound = payload.bytesOutbound
                if let timestamp = event.timestamp, timestamp < payload.timestamp {
                    event.timestamp = payload.timestamp
                }
            } else {
                shouldInsert = true
            }
        }

        if shouldInsert {
            _ = try logEvent(payload)
            return
        }

        try saveContext()
    }

    func updateBytes(from report: NEFilterReport) throws {
        let bytesInbound: Int64
        let bytesOutbound: Int64

        if #available(iOS 13.0, *) {
            bytesInbound = Int64(report.bytesInboundCount)
            bytesOutbound = Int64(report.bytesOutboundCount)
        } else {
            bytesInbound = 0
            bytesOutbound = 0
        }

        guard let flow = report.flow,
              let payload = flow.networkEventPayload(timestamp: Date(),
                                                     bytesInbound: bytesInbound,
                                                     bytesOutbound: bytesOutbound) else {
            return
        }

        try updateLatestMatchingEvent(with: payload)
    }

    func fetchEvents(for app: AppName? = nil, limit: Int? = nil) throws -> [NetworkEventSnapshot] {
        let request: NSFetchRequest<NetworkEvent> = NetworkEvent.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(NetworkEvent.timestamp), ascending: false)]
        if let app = app {
            request.predicate = NSPredicate(format: "%K == %@", #keyPath(NetworkEvent.app), app)
        }
        if let limit = limit {
            request.fetchLimit = limit
        }

        var snapshots: [NetworkEventSnapshot] = []

        try performAndWait {
            let events = try self.managedObjectContext.fetch(request)
            try events.forEach {
                try snapshots.append($0.toSnapshot())
            }
        }

        return snapshots
    }

    func fetchUnifiedEvents(for app: AppName, host: String, limit: Int = 100) throws -> [UnifiedNetworkEvent] {
        let networkEvents = try fetchEvents(for: app, limit: limit).filter { $0.host == host || $0.ipAddress == host }
        let browserEvents = try BrowserEventManager.shared.fetchEvents(for: host, app: app, limit: limit)
        
        var browserEventDict: [String: BrowserEventSnapshot] = [:]
        for bEvent in browserEvents {
            if let id = bEvent.identifier {
                browserEventDict[id] = bEvent
            }
        }
        
        var unifiedEvents: [UnifiedNetworkEvent] = []
        for nEvent in networkEvents {
            let bEvent = nEvent.identifier.flatMap { browserEventDict[$0] }
            
            let unified = UnifiedNetworkEvent(
                identifier: nEvent.identifier,
                timestamp: nEvent.timestamp,
                app: nEvent.app,
                host: nEvent.host,
                ipAddress: nEvent.ipAddress,
                port: nEvent.port,
                localIP: nEvent.localIP,
                localPort: nEvent.localPort,
                bytesInbound: nEvent.bytesInbound,
                bytesOutbound: nEvent.bytesOutbound,
                transportProtocol: nEvent.transportProtocol,
                direction: nEvent.direction,
                url: bEvent?.url,
                httpMethod: bEvent?.httpMethod,
                requestHeaders: bEvent?.requestHeaders,
                requestBody: bEvent?.requestBody,
                statusCode: bEvent?.statusCode,
                responseHeaders: bEvent?.responseHeaders,
                parentURL: bEvent?.parentURL,
                contentType: bEvent?.contentType
            )
            unifiedEvents.append(unified)
        }
        return unifiedEvents
    }

    func fetchAppSummaries(filter: ((AppName) -> Bool)? = nil) throws -> [NetworkEventAppSummary] {
        let events = try fetchEvents()
        var summaries: [AppName: NetworkEventAppSummary] = [:]

        for event in events {
            if let filter = filter, !filter(event.app) {
                continue
            }

            if let summary = summaries[event.app] {
                summaries[event.app] = NetworkEventAppSummary(app: summary.app,
                                                              lastTimestamp: summary.lastTimestamp,
                                                              lastHost: summary.lastHost,
                                                              totalBytesInbound: summary.totalBytesInbound + event.bytesInbound,
                                                              totalBytesOutbound: summary.totalBytesOutbound + event.bytesOutbound,
                                                              eventCount: summary.eventCount + 1)
                continue
            }

            summaries[event.app] = NetworkEventAppSummary(app: event.app,
                                                          lastTimestamp: event.timestamp,
                                                          lastHost: event.host,
                                                          totalBytesInbound: event.bytesInbound,
                                                          totalBytesOutbound: event.bytesOutbound,
                                                          eventCount: 1)
        }

        return summaries.values.sorted {
            if $0.lastTimestamp == $1.lastTimestamp {
                return $0.app < $1.app
            }

            return $0.lastTimestamp > $1.lastTimestamp
        }
    }

    func fetchDashboardData(filter: ((AppName) -> Bool)? = nil,
                            referenceDate: Date = Date(),
                            recentWindow: TimeInterval = 60 * 60) throws -> NetworkEventDashboardData {
        let events = try fetchEvents()
        let recentCutoff = referenceDate.addingTimeInterval(-recentWindow)
        let startOfDay = Calendar.current.startOfDay(for: referenceDate)

        var summaries: [AppName: NetworkEventAppSummary] = [:]
        var recentBytesInbound: Int64 = 0
        var recentBytesOutbound: Int64 = 0
        var recentEventCount = 0
        var activeApps = Set<AppName>()
        var hostsSeenToday = Set<String>()
        var hostsSeenBeforeToday = Set<String>()
        var lastActivityTimestamp: Date?

        for event in events {
            if let filter = filter, !filter(event.app) {
                continue
            }
            
            let normalizedApp = event.app.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if let summary = summaries[normalizedApp] {
                summaries[normalizedApp] = NetworkEventAppSummary(app: summary.app,
                                                              lastTimestamp: summary.lastTimestamp,
                                                              lastHost: summary.lastHost,
                                                              totalBytesInbound: summary.totalBytesInbound + event.bytesInbound,
                                                              totalBytesOutbound: summary.totalBytesOutbound + event.bytesOutbound,
                                                              eventCount: summary.eventCount + 1)
            } else {
                summaries[normalizedApp] = NetworkEventAppSummary(app: event.app.trimmingCharacters(in: .whitespacesAndNewlines),
                                                              lastTimestamp: event.timestamp,
                                                              lastHost: event.host,
                                                              totalBytesInbound: event.bytesInbound,
                                                              totalBytesOutbound: event.bytesOutbound,
                                                              eventCount: 1)
            }

            if lastActivityTimestamp == nil || event.timestamp > lastActivityTimestamp! {
                lastActivityTimestamp = event.timestamp
            }

            if event.timestamp >= recentCutoff {
                recentBytesInbound += event.bytesInbound
                recentBytesOutbound += event.bytesOutbound
                recentEventCount += 1
                activeApps.insert(normalizedApp)
            }

            if let host = (event.host ?? event.ipAddress)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !host.isEmpty {
                if event.timestamp >= startOfDay {
                    hostsSeenToday.insert(host)
                } else {
                    hostsSeenBeforeToday.insert(host)
                }
            }
        }

        let activityOverview = NetworkActivityOverview(recentBytesInbound: recentBytesInbound,
                                                       recentBytesOutbound: recentBytesOutbound,
                                                       activeAppCount: activeApps.count,
                                                       recentEventCount: recentEventCount,
                                                       newHostCountToday: hostsSeenToday.subtracting(hostsSeenBeforeToday).count,
                                                       lastActivityTimestamp: lastActivityTimestamp)

        let appSummaries = summaries.values.sorted {
            if $0.lastTimestamp == $1.lastTimestamp {
                return $0.app < $1.app
            }

            return $0.lastTimestamp > $1.lastTimestamp
        }

        return NetworkEventDashboardData(appSummaries: appSummaries,
                                         activityOverview: activityOverview)
    }

    func fetchActivityOverview(filter: ((AppName) -> Bool)? = nil,
                               referenceDate: Date = Date(),
                               recentWindow: TimeInterval = 60 * 60) throws -> NetworkActivityOverview {
        return try fetchDashboardData(filter: filter,
                                      referenceDate: referenceDate,
                                      recentWindow: recentWindow).activityOverview
    }

    func pruneOldData(days: Int) throws {
        let cutoff = Date().addingTimeInterval(TimeInterval(-days * 24 * 60 * 60))
        let request: NSFetchRequest<NetworkEvent> = NetworkEvent.fetchRequest()
        request.predicate = NSPredicate(format: "%K < %@", #keyPath(NetworkEvent.timestamp), cutoff as NSDate)

        try performAndWait {
            let events = try self.managedObjectContext.fetch(request)
            events.forEach { self.managedObjectContext.delete($0) }
        }

        try saveContext()
    }

    private func latestEvent(matching payload: NetworkEventPayload) throws -> NetworkEvent? {
        let request: NSFetchRequest<NetworkEvent> = NetworkEvent.fetchRequest()
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(NetworkEvent.timestamp), ascending: false)]
        if let identifier = payload.identifier {
            request.predicate = NSPredicate(format: "%K == %@", #keyPath(NetworkEvent.identifier), identifier)
            return try self.managedObjectContext.fetch(request).first
        }

        request.predicate = eventPredicate(for: payload)

        return try self.managedObjectContext.fetch(request).first
    }

    private func eventPredicate(for payload: NetworkEventPayload) -> NSPredicate {
        var predicates = [NSPredicate(format: "%K == %@", #keyPath(NetworkEvent.app), payload.app)]

        predicates.append(stringPredicate(key: #keyPath(NetworkEvent.host), value: payload.host))
        predicates.append(stringPredicate(key: #keyPath(NetworkEvent.ipAddress), value: payload.ipAddress))
        predicates.append(stringPredicate(key: "protocol", value: payload.transportProtocol))
        predicates.append(stringPredicate(key: #keyPath(NetworkEvent.direction), value: payload.direction))

        predicates.append(NSPredicate(format: "%K == %d", #keyPath(NetworkEvent.port), Int(payload.port ?? 0)))

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private func stringPredicate(key: String, value: String?) -> NSPredicate {
        if let value = value {
            return NSPredicate(format: "%K == %@", key, value)
        }

        return NSPredicate(format: "%K == nil", key)
    }

    private func performAndWait(fn: @escaping (() throws -> Void)) throws {
        var caughtError: Error?
        managedObjectContext.performAndWait {
            do {
                try fn()
            } catch {
                caughtError = error
            }
        }

        if let error = caughtError {
            throw error
        }
    }

    private func saveContext() throws {
        var caughtError: Error?

        managedObjectContext.performAndWait {
            if self.managedObjectContext.hasChanges {
                do {
                    try self.managedObjectContext.save()
                } catch {
                    caughtError = error
                }
            }
        }

        if let error = caughtError {
            throw error
        }
    }
}
