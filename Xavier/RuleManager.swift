//
//  RuleManager.swift
//  Xavier
//
//

import Foundation
import CoreData


extension RuleType {
    var typeAndValue:(String,String) {
        switch self {
        case .app(let app):
            return ("app", app)
        case .host(let host):
            return ("host", host)
        case .hostFromApp(let host, let app):
            return (app, host)
        }
    }
    
    init(type:String, value:String) {
        switch type {
        case "app":
            self = .app(value)
        case "host":
            self = .host(value)
        default:
            self = .hostFromApp(host: value, app: type)
        }
    }
}
extension DataRule {
    func toRule() throws -> Rule {
        guard
            let type = type,
            let value = value
        else {
            throw RuleManager.Errors.missingObjectField
        }
        
        return Rule(ruleType: RuleType(type: type, value: value), isAllowed: isAllowed, date: Date())
    }
    
    convenience init(rule:Rule, helper context:NSManagedObjectContext) {
        self.init(helper: context)
        
        self.isAllowed = rule.isAllowed
        let (type, value) = rule.ruleType.typeAndValue
        
        self.type = type
        self.value = value
    }
    
    convenience init(helper context: NSManagedObjectContext) {
        //workaround: https://stackoverflow.com/questions/6946798/core-data-store-cannot-hold-instances-of-entity-cocoa-error-134020
        self.init(entity: NSEntityDescription.entity(forEntityName: "DataRule", in: context)!, insertInto: context)
    }
    
}

extension DataWildCard {
    func toWildcard() throws -> Wildcard {
        guard let app = app
        else {
            throw RuleManager.Errors.missingObjectField
        }
        
        return Wildcard(app: app, isAllowed: isAllowed)
    }
    
    convenience init(wildcard:Wildcard, helper context:NSManagedObjectContext) {
        self.init(helper: context)
        
        self.isAllowed = wildcard.isAllowed
        self.app = wildcard.app
    }
    
    convenience init(helper context: NSManagedObjectContext) {
        //workaround: https://stackoverflow.com/questions/6946798/core-data-store-cannot-hold-instances-of-entity-cocoa-error-134020
        self.init(entity: NSEntityDescription.entity(forEntityName: "DataWildCard", in: context)!, insertInto: context)
    }
    
}



class RuleManager {
    
    private var managedObjectModel:NSManagedObjectModel?
    private var persistentStoreCoordinator:NSPersistentStoreCoordinator?
    private var managedObjectContext:NSManagedObjectContext
    
    init() throws {
        // persistent store coordinator
        guard let directoryURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupIdentifier)?.appendingPathComponent("data"),
            let modelURL = Bundle.main.url(forResource:"XavierDataModel", withExtension: "momd"),
            let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL)
            else {
                throw Errors.createDatabase
        }
        
        // create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        let options = [NSMigratePersistentStoresAutomaticallyOption: true,
                       NSInferMappingModelAutomaticallyOption: true]
        
        // db file
        let dbURL = directoryURL.appendingPathComponent("db.sqlite")
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
        
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: dbURL, options: options)
        store.didAdd(to: coordinator)
        
        persistentStoreCoordinator = coordinator
        
        // managed object context
        managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = coordinator
    }
    
    enum Errors:Error {
        case createDatabase
        case missingObjectField
        case noSuchRule
        case ruleAlreadyExists
    }
    
    
    ///MARK: Blocks
    
    func fetchAll() throws -> [Rule] {
        var rules:[Rule] = []
        
        let request:NSFetchRequest<DataRule> = DataRule.fetchRequest()

        try performAndWait {
            let dataRules = try self.managedObjectContext.fetch(request)

            try dataRules.forEach {
                try rules.append($0.toRule())
            }
        }
        
        return rules
    }
    
    func create(rule:Rule) throws  {
        let (type, value) = rule.ruleType.typeAndValue
        
        guard try findDataRule(type: type, value: value) == nil else {
            throw Errors.ruleAlreadyExists
        }
    
        try performAndWait {
            let _ = DataRule(rule: rule, helper: self.managedObjectContext)
        }
        
        try saveContext()
    }
    
    func delete(rule:Rule) throws  {
        let (type, value) = rule.ruleType.typeAndValue
        
        guard let dataRule = try findDataRule(type: type, value: value) else {
            throw Errors.noSuchRule
        }
        
        try performAndWait {
            self.managedObjectContext.delete(dataRule)
        }
        
        try saveContext()
    }

    
    func deleteAll() throws {
        guard let directoryURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupIdentifier)?.appendingPathComponent("data") else {
            return
        }
        
        let dbURL = directoryURL.appendingPathComponent("db.sqlite")
        let shmURL = directoryURL.appendingPathComponent("db.sqlite-shm")
        let walURL = directoryURL.appendingPathComponent("db.sqlite-wal")
        
        for url in [dbURL, shmURL, walURL] {
            try? FileManager.default.removeItem(at: url)
        }

        RuleManager.recreateShared()
    }
    
    func toggle(rule:Rule) throws  {
        let (type, value) = rule.ruleType.typeAndValue
        
        guard let dataRule = try findDataRule(type: type, value: value) else {
            throw Errors.noSuchRule
        }
        
        try performAndWait {
            dataRule.isAllowed = !rule.isAllowed
        }
        
        try saveContext()
    }

    private func findDataRule(type:String, value:String) throws -> DataRule? {
        let request:NSFetchRequest<DataRule> = DataRule.fetchRequest()
        
        // app
        let typePred = NSComparisonPredicate(
            leftExpression: NSExpression(forKeyPath: #keyPath(DataRule.type)),
            rightExpression: NSExpression(forConstantValue: type),
            modifier: .direct,
            type: .equalTo,
            options: NSComparisonPredicate.Options(rawValue: 0)
        )
        
        let valuePred = NSComparisonPredicate(
            leftExpression: NSExpression(forKeyPath: #keyPath(DataRule.value)),
            rightExpression: NSExpression(forConstantValue: value),
            modifier: .direct,
            type: .equalTo,
            options: NSComparisonPredicate.Options(rawValue: 0)
        )
        
        
        // pred
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [typePred, valuePred])
        
        var rule:DataRule?
        
        try performAndWait {
            let dataRules = try self.managedObjectContext.fetch(request)
            rule = dataRules.first
        }
        
        return rule

    }

    private func getDataRule(for app:String, hostname:String?) throws -> DataRule? {
        if let appRule = try findDataRule(type: "app", value: app) {
            return appRule
        }

        guard let host = hostname else {
            return nil
        }

        if let appHostRule = try findDataRule(type: app, value: host) {
            return appHostRule
        }

        return try findDataRule(type: "host", value: host)
    }
    
    func getRule(for app:String, hostname:String?) throws -> Rule? {
        return try self.getDataRule(for: app, hostname: hostname)?.toRule()
    }
    
    
    //MARK: Internals
    private func performAndWait(fn:@escaping (() throws -> Void)) throws {
        
        var caughtError:Error?
        self.managedObjectContext.performAndWait {
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
    
    //MARK: - Core Data Saving/Roll back support
    func saveContext() throws {
        var caughtError:Error?
        self.managedObjectContext.performAndWait {
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
    
    func rollbackContext () {        
        self.managedObjectContext.performAndWait {
            if self.managedObjectContext.hasChanges {
                self.managedObjectContext.rollback()
            }
        }
    }
}

extension RuleManager {
    private static var _shared: RuleManager?

    static var shared: RuleManager {
        if let existing = _shared {
            return existing
        }
        let instance = (try? RuleManager()) ?? (try! RuleManager())
        _shared = instance
        return instance
    }

    static func recreateShared() {
        _shared = try? RuleManager()
    }
}
