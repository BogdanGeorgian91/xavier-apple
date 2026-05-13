import CoreData
import Foundation

final class InspectionManager {
    static let shared: InspectionManager = {
        do {
            return try InspectionManager()
        } catch {
            fatalError("Unable to create InspectionManager: \(error)")
        }
    }()

    private let managedObjectContext: NSManagedObjectContext
    private static let maxBodyBytes = 65536

    init() throws {
        guard let directoryURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupIdentifier)?
            .appendingPathComponent("data"),
            let modelURL = Bundle.main.url(forResource: "InspectionModel", withExtension: "momd"),
            let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL) else {
            throw NSError(domain: "InspectionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Core Data stack"])
        }

        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }

        let options = [NSMigratePersistentStoresAutomaticallyOption: true,
                       NSInferMappingModelAutomaticallyOption: true]
        let dbURL = directoryURL.appendingPathComponent("inspection_db.sqlite")
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: dbURL, options: options)
        store.didAdd(to: coordinator)

        managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = coordinator
    }

    @discardableResult
    func logRequest(_ payload: InspectedRequestPayload) throws -> InspectedRequestSnapshot {
        var snapshot: InspectedRequestSnapshot?

        try performAndWait {
            let request = InspectedRequest(entity: NSEntityDescription.entity(forEntityName: "InspectedRequest", in: self.managedObjectContext)!, insertInto: self.managedObjectContext)
            request.identifier = payload.identifier ?? UUID().uuidString
            request.timestamp = Date()
            request.appName = payload.appName
            request.appBundleID = payload.appBundleID
            request.host = payload.host
            request.url = payload.url
            request.httpMethod = payload.httpMethod
            request.requestHeaders = self.serializeHeaders(payload.requestHeaders)
            request.requestBody = self.truncate(payload.requestBody)
            request.statusCode = payload.statusCode
            request.responseHeaders = self.serializeHeaders(payload.responseHeaders)
            request.responseBody = self.truncate(payload.responseBody)
            request.contentType = payload.contentType
            request.duration = payload.duration
            request.tlsVersion = payload.tlsVersion
            request.port = payload.port
            request.pinned = payload.pinned
            request.blocked = payload.blocked
            request.blockedReason = payload.blockedReason
            request.responseModified = payload.responseModified
            request.requestModified = payload.requestModified
            request.originalRequestHeaders = self.serializeHeaders(payload.originalRequestHeaders)
            request.originalRequestBody = self.truncate(payload.originalRequestBody)
            request.originalResponseHeaders = self.serializeHeaders(payload.originalResponseHeaders)
            request.originalResponseBody = self.truncate(payload.originalResponseBody)

            snapshot = try self.snapshot(for: request)
        }

        try saveContext()
        return snapshot!
    }

    private func isParsedRequest(_ snapshot: InspectedRequestSnapshot) -> Bool {
        guard let method = snapshot.httpMethod?.trimmingCharacters(in: .whitespacesAndNewlines), !method.isEmpty else {
            return false
        }
        return method != "FLOW"
    }

    func fetchRequests(site: String? = nil, host: String? = nil, appBundleID: String? = nil, limit: Int? = nil) throws -> [InspectedRequestSnapshot] {
        let request: NSFetchRequest<InspectedRequest> = InspectedRequest.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(InspectedRequest.timestamp), ascending: false)]

        let requiresInMemoryFiltering = site != nil || host != nil || appBundleID != nil || !Constants.isShowFallbackFlowsEnabled
        if let limit = limit, !requiresInMemoryFiltering {
            request.fetchLimit = limit
        }

        var snapshots = [InspectedRequestSnapshot]()
        try performAndWait {
            let items = try self.managedObjectContext.fetch(request)
            try items.forEach { item in
                try snapshots.append(self.snapshot(for: item))
            }
        }
        var filtered = snapshots.filter { snapshot in
            let siteMatches = site.map { self.siteContext(for: snapshot) == $0 } ?? true
            let hostMatches = host.map { snapshot.host == $0 } ?? true
            let appMatches = appBundleID.map { self.appIdentifier(for: snapshot) == $0 } ?? true
            return siteMatches && hostMatches && appMatches
        }

        if !Constants.isShowFallbackFlowsEnabled {
            filtered = filtered.filter(isParsedRequest)
        }

        if let limit = limit {
            return Array(filtered.prefix(limit))
        }

        return filtered
    }

    func fetchHostSummaries(limit: Int = 100) throws -> [InspectorHostSummary] {
        let requests = try fetchRequests(limit: limit * 20)
        return summarizeHosts(from: requests, limit: limit)
    }

    func fetchSiteSummaries(limit: Int = 100) throws -> [InspectorSiteSummary] {
        let requests = try fetchRequests(limit: limit * 40)
        return Dictionary(grouping: requests, by: { siteContext(for: $0) })
            .map { site, siteRequests in
                InspectorSiteSummary(
                    site: site,
                    lastTimestamp: siteRequests.map(\.timestamp).max() ?? Date.distantPast,
                    requestCount: siteRequests.count,
                    hostCount: Set(siteRequests.map { $0.host ?? "Unknown Host" }).count,
                    methods: Set(siteRequests.compactMap(\.httpMethod)),
                    apps: Set(siteRequests.map { self.appIdentifier(for: $0) }),
                    blockedCount: siteRequests.reduce(0) { $0 + ($1.blocked ? 1 : 0) }
                )
            }
            .sorted { $0.lastTimestamp > $1.lastTimestamp }
            .prefix(limit)
            .map { $0 }
    }

    func fetchHostSummaries(site: String, limit: Int = 100) throws -> [InspectorHostSummary] {
        let requests = try fetchRequests(site: site, limit: limit * 20)
        return summarizeHosts(from: requests, limit: limit)
    }

    func fetchAppSummaries(site: String, limit: Int = 100) throws -> [InspectorAppSummary] {
        let requests = try fetchRequests(site: site, limit: limit * 40)
        return Dictionary(grouping: requests, by: { self.appIdentifier(for: $0) })
            .map { appBundleID, appRequests in
                InspectorAppSummary(
                    appBundleID: appBundleID,
                    lastTimestamp: appRequests.map(\.timestamp).max() ?? Date.distantPast,
                    requestCount: appRequests.count,
                    hostCount: Set(appRequests.map { $0.host ?? "Unknown Host" }).count,
                    methods: Set(appRequests.compactMap(\.httpMethod)),
                    blockedCount: appRequests.reduce(0) { $0 + ($1.blocked ? 1 : 0) }
                )
            }
            .sorted { $0.lastTimestamp > $1.lastTimestamp }
            .prefix(limit)
            .map { $0 }
    }

    private func summarizeHosts(from requests: [InspectedRequestSnapshot], limit: Int) -> [InspectorHostSummary] {
        var summaries = [String: InspectorHostSummary]()

        for request in requests {
            let host = request.host ?? "Unknown Host"
            if let existing = summaries[host] {
                var methods = existing.methods
                if let method = request.httpMethod, !method.isEmpty {
                    methods.insert(method)
                }
                var apps = existing.apps
                apps.insert(appIdentifier(for: request))
                summaries[host] = InspectorHostSummary(
                    host: existing.host,
                    lastTimestamp: max(existing.lastTimestamp, request.timestamp),
                    requestCount: existing.requestCount + 1,
                    methods: methods,
                    apps: apps,
                    blockedCount: existing.blockedCount + (request.blocked ? 1 : 0)
                )
            } else {
                summaries[host] = InspectorHostSummary(
                    host: host,
                    lastTimestamp: request.timestamp,
                    requestCount: 1,
                    methods: request.httpMethod.map { [$0] } ?? [],
                    apps: [appIdentifier(for: request)],
                    blockedCount: request.blocked ? 1 : 0
                )
            }
        }

        return summaries.values.sorted { $0.lastTimestamp > $1.lastTimestamp }.prefix(limit).map { $0 }
    }

    func pruneOldData(days: Int) throws {
        let cutoff = Date().addingTimeInterval(TimeInterval(-days * 24 * 60 * 60))
        let request: NSFetchRequest<InspectedRequest> = InspectedRequest.fetchRequest()
        request.predicate = NSPredicate(format: "%K < %@", #keyPath(InspectedRequest.timestamp), cutoff as NSDate)

        try performAndWait {
            let items = try self.managedObjectContext.fetch(request)
            items.forEach { self.managedObjectContext.delete($0) }
        }

        try saveContext()
    }

    private func snapshot(for request: InspectedRequest) throws -> InspectedRequestSnapshot {
        guard let timestamp = request.timestamp, let appName = request.appName else {
            throw NSError(domain: "InspectionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing object field"])
        }

        return InspectedRequestSnapshot(
            identifier: request.identifier,
            timestamp: timestamp,
            appName: appName,
            appBundleID: request.appBundleID,
            host: request.host,
            url: request.url,
            httpMethod: request.httpMethod,
            requestHeaders: request.requestHeaders,
            requestBody: request.requestBody,
            statusCode: request.statusCode,
            responseHeaders: request.responseHeaders,
            responseBody: request.responseBody,
            contentType: request.contentType,
            duration: request.duration,
            tlsVersion: request.tlsVersion,
            port: request.port,
            pinned: request.pinned,
            blocked: request.blocked,
            blockedReason: request.blockedReason,
            responseModified: request.responseModified,
            requestModified: request.requestModified,
            originalRequestHeaders: request.originalRequestHeaders,
            originalRequestBody: request.originalRequestBody,
            originalResponseHeaders: request.originalResponseHeaders,
            originalResponseBody: request.originalResponseBody
        )
    }

    private func siteContext(for snapshot: InspectedRequestSnapshot) -> String {
        if let host = snapshot.host, !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return normalizedHost(host)
        }

        let headers = deserializeHeaders(snapshot.requestHeaders)
        let candidates = [headers["Referer"], headers["Origin"], snapshot.url]
        for candidate in candidates {
            guard let candidate = candidate,
                  let url = URL(string: candidate),
                  let host = url.host else { continue }
            return normalizedHost(host)
        }
        return "Unknown Site"
    }

    private func normalizedHost(_ host: String) -> String {
        return host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func appIdentifier(for snapshot: InspectedRequestSnapshot) -> String {
        guard let bundleID = snapshot.appBundleID, !bundleID.isEmpty else {
            return snapshot.appName.contains(".") ? snapshot.appName : "Unknown Bundle ID"
        }
        return bundleID
    }

    private func deserializeHeaders(_ serialized: String?) -> [String: String] {
        guard let serialized = serialized, !serialized.isEmpty else { return [:] }
        var headers = [String: String]()
        for line in serialized.components(separatedBy: "\n") {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        return headers
    }

    private func serializeHeaders(_ headers: [String: String]?) -> String? {
        guard let headers = headers, !headers.isEmpty else { return nil }
        return headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }

    private func truncate(_ data: Data?) -> Data? {
        guard let data = data else { return nil }
        if data.count <= InspectionManager.maxBodyBytes {
            return data
        }
        return data.subdata(in: 0..<InspectionManager.maxBodyBytes)
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
