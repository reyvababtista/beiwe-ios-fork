import Foundation
import ObjectMapper
import PromiseKit


let kReclineMetadataKey = "reclineMetadata"  // its a key used in some stuff

enum ReclineErrors: Error {
    case databaseNotOpen
}

// Any call into json.map can error with an invalid collection count, which can't be caught.
// The entire codebase would have to be examined to determine where any thread-unsafe database calls
// are made - you can guarantee one by doing _any access on a Mapper object_, because those call the database? what?,
// before AppDelegate.setupThatDependsOnDatabase is called - to determine if it was safe to stick any
// individual call on a given dispatch queue for EVERY SINGLE USE OF A PROMISE.
// GEE ITS ALMOST LIKE THE PERSON WHO DESIGNED THIS DIDN'T KNOW WHAT THEY WERE DOING.

// This class name is utter, absolute, complete, and total garbage.
class Recline {
    static let shared = Recline()  // singleton instance
    
    var manager: CBLManager!  // Top-level CouchbaseLite object
    var db: CBLDatabase?      // CouchbaseLite database
    var typesView: CBLView?   // persistent index, view can be queried using a CBLQuery.

    /// trivial init - possibly to keep db access as a singleton via open maybe?
    init() {}

    /// database open function - called exactly once in AppDelegate
    func open(_ dbName: String = "default") -> Promise<Bool> {
        return Promise().then(on: RECLINE_QUEUE) { _ -> Promise<Bool> in
            // safety in case its called twice? sure.
            if self.manager == nil {
                // it sets the database up as a file, we don't care about the UnsafeMutablePointer its objc junk
                let cbloptions = CBLManagerOptions(readOnly: false, fileProtection: NSData.WritingOptions.noFileProtection)
                let poptions = UnsafeMutablePointer<CBLManagerOptions>.allocate(capacity: 1)
                poptions.initialize(to: cbloptions)
                try self.manager = CBLManager(directory: CBLManager.defaultDirectory(), options: poptions)
                self.manager.dispatchQueue = RECLINE_QUEUE
            }
            return self._open(dbName)  // defines database views... in a promise... 🙄
        }
    }
    
    /// The actual open function maybe - or at least its called at the end of open. and nowhere else.
    /// Sets self.db, self.typesView; defines view functions - whatever that means.
    func _open(_ dbName: String = "default") -> Promise<Bool> {
        return Promise { (resolver: Resolver<Bool>) in
            // get our critical objects
            self.db = try manager.databaseNamed(dbName)
            self.typesView = self.db!.viewNamed("reclineType")
            
            // Defines the view, sets its functions.
            typesView!.setMapBlock({ (doc: [String : Any], emit) in  // let emit: <<error type>>  (probably ReclineErrors?)
                // I think this sets the return type to be a dict of string to any, because it is json.
                // I don't know what function this actually sets. (... map? mapblock?)
                if let reclineMeta: ReclineMetadata = Mapper<ReclineMetadata>().map(JSONObject: doc[kReclineMetadataKey]) {
                    if let type = reclineMeta.type {
                        emit(type, Mapper<ReclineMetadata>().toJSON(reclineMeta))
                    }
                }
            }, version: "5")  // version arguument of setMapBlock
            return resolver.fulfill(true)  // hot garbo
        }
    }

    /// wraps the actual save function in a promise, but its a template type so it might be necessary
    /// - ah, the templated type is required because this is called from a templated function inside RegisterViewController/ApiManager
    /// - (This still does not explain or justify why the ONLY CONTENT is factored out into another function with IDENTICAL TEMPLATED TYPING 🙄.)
    func save<T: ReclineObject>(_ obj: T) -> Promise<T> {
        return Promise().then(on: RECLINE_QUEUE) {
            return self._save(obj)
        }
    }
    
    /// actual save [template] function
    func _save<T: ReclineObject>(_ obj: T) -> Promise<T> {
        return Promise { (resolver: Resolver<T>) in
            // give up early if db is not instantiated
            guard let db = db else {
                return resolver.reject(ReclineErrors.databaseNotOpen)  // TODO: fatal error?
            }
            // get or create the document.  I can't tell if this could be made non-optional,
            var doc: CBLDocument?
            if let _id = obj._id {
                doc = db.document(withID: _id)
            } else {
                doc = db.createDocument()
            }
            // take the object, make a json version of it, and .... then we do something involving ReclineMetadata?
            var newProps: [String: Any] = Mapper<T>().toJSON(obj)
            let reclineMeta = ReclineMetadata(type: String(describing: type(of: obj)))
            newProps[kReclineMetadataKey] = Mapper<ReclineMetadata>().toJSON(reclineMeta)
            // couchbase uses a revisioning system for concurrency, so this is probably assigning an id and a a revision
            newProps["_id"] = doc?.properties?["_id"]
            newProps["_rev"] = doc?.properties?["_rev"]
            // I think we are swallowing any errors
            try doc?.putProperties(newProps)  // commit to database
            return resolver.fulfill(obj)
        }
    }

    /// wraps load in a promise, but its a template function so maybe its okay 🙄.
    func load<T: ReclineObject>(_ docId: String) -> Promise<T?> {
        return Promise().then(on: RECLINE_QUEUE) {
            self._load(docId)
        }
    }
    
    /// template function to get a single object (a whole document?) from couchbase, inn a promise
    func _load<T: ReclineObject>(_ docId: String) -> Promise<T?> {
        return Promise { (resolver: Resolver<T?>) in
            // give up early if db is not instantiated
            guard let db = db else {
                return resolver.reject(ReclineErrors.databaseNotOpen)
            }
            // get the _underlying_ document? it is apparently json, at least in our usage.
            let doc: CBLDocument? = db.document(withID: docId)
            if let doc = doc {
                if let newObj = Mapper<T>().map(JSONObject: doc.properties) {
                    newObj._id = doc.properties?["_id"] as? String
                    return resolver.fulfill(newObj)
                }
            }
            // this is the failure case?
            return resolver.fulfill(nil)
        }
    }

    /// wraps _queryAll....
    func queryAll<T: ReclineObject>() -> Promise<[T]> {
        return Promise().then(on: RECLINE_QUEUE) {
            return self._queryAll()
        }
    }
    
    /// gets all rows in the typesView database view - this returns a list of all studies as a parameter to the next promise.
    func _queryAll<T: ReclineObject>() -> Promise<[T]> {
        return Promise { (resolver: Resolver<[T]>) in
            guard let typesView = typesView else {  // exit early
                return resolver.reject(ReclineErrors.databaseNotOpen)
            }
            // create an unfiltered query, run it, iterate on rows, each row is a study
            let query = typesView.createQuery()
            let result = try query.run()
            var promises: [Promise<T?>] = []
            while let row = result.nextRow() {
                // assemble a bunch of studies inside promises?
                if let docId = row.documentID {
                    promises.append(load(docId))
                }
            }
            when(fulfilled: promises).done(on: RECLINE_QUEUE) { results in
                // resolve([])
                resolver.fulfill(results.filter { $0 != nil }.map { $0! })  // I think this where it has found all the documents and is... making them findable
            }.catch { err in
                resolver.reject(err)
            }
        }
    }

    /// wrapper for _purge...
    func purge<T: ReclineObject>(_ obj: T) -> Promise<Bool> {
        return Promise().then(on: RECLINE_QUEUE) {
            return self._purge(obj)
        }
    }
    
    /// deletes the item, returns true (always)
    func _purge<T: ReclineObject>(_ obj: T) -> Promise<Bool> {
        return Promise { (resolver: Resolver<Bool>) in
            //deletes the document and always returns true even on failure wut.
            if let _id = obj._id {
                try db?.document(withID: _id)?.purgeDocument()
            }
            return resolver.fulfill(true)
        }
    }

    /// runs the database compact operation
    func compact() -> Promise<Void> {
        return Promise<Void>().done(on: RECLINE_QUEUE) { _ in
            try self.db?.compact()
        }
    }
}

/// class for objects returned from a database query
class ReclineObject: Mappable {
    fileprivate var _id: String?
    init() {}
    required init?(map: Map) {}
    func mapping(map: Map) {}  // Mappable
}

/// I don't know. Usage doesn't obviously mean anything to me other than it has a type value that is set.
struct ReclineMetadata: Mappable {
    var type: String?
    init?(map: Map) {}
    init(type: String) {
        self.type = type
    }
    mutating func mapping(map: Map) {
        self.type <- map["type"]
    }
}
