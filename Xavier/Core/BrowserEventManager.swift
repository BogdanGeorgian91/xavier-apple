import CoreData
import Foundation
import NetworkExtension

final class BrowserEventManager {
    static let shared: BrowserEventManager = {
        do {
            return try BrowserEventManager()
        } catch {
            fatalError("Unable to create BrowserEventManager: \(error)")
        }
    }()

    private let managedObjectContext: NSManagedObjectContext

    init() throws {
        guard let directoryURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupIdentifier)?
            .appendingPathComponent("data"),
              let modelURL = Bundle.main.url(forResource: "XavierDataModel", withExtension: "momd"),
              let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL) else {
            throw NSError(domain: "BrowserEventManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Core Data stack"])
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
    func logEvent(_ payload: BrowserFlowPayload) throws -> BrowserEventSnapshot? {
        var snapshot: BrowserEventSnapshot?

        try performAndWait {
            let event: BrowserEvent
            if let identifier = payload.identifier,
               let existingEvent = try self.existingEvent(identifier: identifier) {
                event = existingEvent
            } else {
                event = BrowserEvent(entity: NSEntityDescription.entity(forEntityName: "BrowserEvent", in: self.managedObjectContext)!, insertInto: self.managedObjectContext)
            }

            event.identifier = payload.identifier ?? UUID().uuidString
            event.app = payload.app
            event.host = payload.host ?? event.host
            event.urlString = payload.url ?? event.urlString
            event.httpMethod = payload.httpMethod ?? event.httpMethod
            if payload.statusCode > 0 {
                event.statusCode = payload.statusCode
            }
            event.parentURL = payload.parentURL ?? event.parentURL
            event.contentType = payload.contentType ?? event.contentType
            event.timestamp = Date()

            if let headers = payload.requestHeaders {
                let sorted = headers.sorted { $0.key < $1.key }
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: "\n")
                event.requestHeaders = sorted
            }

            if let body = payload.requestBody {
                if let bodyString = String(data: body, encoding: .utf8) {
                    event.requestBody = String(bodyString.prefix(65536))
                } else {
                    event.requestBody = "\(body.count) bytes (binary data)"
                }
            }

            if let headers = payload.responseHeaders {
                let sorted = headers.sorted { $0.key < $1.key }
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: "\n")
                event.responseHeaders = sorted
            }

            snapshot = BrowserEventSnapshot(
                identifier: event.identifier,
                timestamp: event.timestamp!,
                app: event.app!,
                host: event.host,
                url: event.urlString,
                httpMethod: event.httpMethod,
                requestHeaders: event.requestHeaders,
                requestBody: event.requestBody,
                statusCode: event.statusCode,
                responseHeaders: event.responseHeaders,
                parentURL: event.parentURL,
                contentType: event.contentType
            )
        }

        try saveContext()
        return snapshot
    }

    private func existingEvent(identifier: String) throws -> BrowserEvent? {
        let request: NSFetchRequest<BrowserEvent> = BrowserEvent.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(BrowserEvent.identifier), identifier)
        return try managedObjectContext.fetch(request).first
    }

    @discardableResult
    func logFlowMetadata(from flow: NEFilterFlow) throws -> BrowserEventSnapshot? {
        guard let payload = flow.browserFlowPayload() else {
            return nil
        }

        return try logEvent(payload)
    }

    func fetchEvents(for host: String? = nil, app: String? = nil, limit: Int? = nil) throws -> [BrowserEventSnapshot] {
        let request: NSFetchRequest<BrowserEvent> = BrowserEvent.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(BrowserEvent.timestamp), ascending: false)]

        var predicates = [NSPredicate]()
        if let host = host {
            predicates.append(NSPredicate(format: "%K == %@", #keyPath(BrowserEvent.host), host))
        }
        if let app = app {
            predicates.append(NSPredicate(format: "%K == %@", #keyPath(BrowserEvent.app), app))
        }
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        if let limit = limit {
            request.fetchLimit = limit
        }

        var snapshots: [BrowserEventSnapshot] = []

        try performAndWait {
            let events = try self.managedObjectContext.fetch(request)
            for event in events {
                guard let timestamp = event.timestamp, let app = event.app else { continue }
                snapshots.append(BrowserEventSnapshot(
                    identifier: event.identifier,
                    timestamp: timestamp,
                    app: app,
                    host: event.host,
                    url: event.urlString,
                    httpMethod: event.httpMethod,
                    requestHeaders: event.requestHeaders,
                    requestBody: event.requestBody,
                    statusCode: event.statusCode,
                    responseHeaders: event.responseHeaders,
                    parentURL: event.parentURL,
                    contentType: event.contentType
                ))
            }
        }

        return snapshots
    }

    func fetchEvents(forPage page: String) throws -> [BrowserEventSnapshot] {
        return try fetchEvents().filter { pageKey(for: $0) == page }
    }

    func fetchHostSummaries(limit: Int = 100) throws -> [BrowserHostSummary] {
        let events = try fetchEvents()

        var hostMap: [String: BrowserHostSummary] = [:]
        for event in events {
            let host = pageKey(for: event)
            guard !host.isEmpty else { continue }
            if let existing = hostMap[host] {
                if let method = event.httpMethod {
                    var methods = existing.methods
                    methods.insert(method)
                    var apps = existing.apps
                    apps.insert(event.app)
                    hostMap[host] = BrowserHostSummary(
                        host: existing.host,
                        lastTimestamp: max(existing.lastTimestamp, event.timestamp),
                        requestCount: existing.requestCount + 1,
                        methods: methods,
                        apps: apps
                    )
                } else {
                    var apps = existing.apps
                    apps.insert(event.app)
                    hostMap[host] = BrowserHostSummary(
                        host: existing.host,
                        lastTimestamp: max(existing.lastTimestamp, event.timestamp),
                        requestCount: existing.requestCount + 1,
                        methods: existing.methods,
                        apps: apps
                    )
                }
            } else {
                var methods = Set<String>()
                if let method = event.httpMethod {
                    methods.insert(method)
                }
                hostMap[host] = BrowserHostSummary(
                    host: host,
                    lastTimestamp: event.timestamp,
                    requestCount: 1,
                    methods: methods,
                    apps: [event.app]
                )
            }
        }

        return hostMap.values.sorted { $0.lastTimestamp > $1.lastTimestamp }
    }

    private func pageKey(for event: BrowserEventSnapshot) -> String {
        if let parentURL = event.parentURL,
           let host = URL(string: parentURL)?.host,
           !host.isEmpty {
            return host
        }

        if let url = event.url,
           let host = URL(string: url)?.host,
           !host.isEmpty {
            return host
        }

        return event.host ?? ""
    }

    func pruneOldData(days: Int) throws {
        let cutoff = Date().addingTimeInterval(TimeInterval(-days * 24 * 60 * 60))
        let request: NSFetchRequest<BrowserEvent> = BrowserEvent.fetchRequest()
        request.predicate = NSPredicate(format: "%K < %@", #keyPath(BrowserEvent.timestamp), cutoff as NSDate)

        try performAndWait {
            let events = try self.managedObjectContext.fetch(request)
            events.forEach { self.managedObjectContext.delete($0) }
        }

        try saveContext()
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
