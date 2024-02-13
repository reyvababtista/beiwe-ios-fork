import Foundation
import ObjectMapper

// its a key that we need to use to access something about the database metadata
let kReclineMetadataKey = "reclineMetadata"

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

/// A database ~manager class for CouchbaseLite
class Recline {
    static let shared = Recline()  // singleton instance
    
    var manager: CBLManager!  // Top-level CouchbaseLite object
    var db: CBLDatabase?      // CouchbaseLite database
    var typesView: CBLView?   // persistent index, view can be queried using a CBLQuery.

    /// trivial init - possibly to keep db access as a singleton via open maybe?
    init() {}

    /// database open function - called exactly once in AppDelegate
    /// this function only be called once at app instantiation. If this fails, the app fails.
    /// Sets self.db, self.typesView; defines view functions - whatever that means.
    func open(_ dbName: String = "default") {
        // it sets the database up as a file, we don't care about the UnsafeMutablePointer its objc junk
        let cbloptions = CBLManagerOptions(readOnly: false, fileProtection: NSData.WritingOptions.noFileProtection)
        let poptions = UnsafeMutablePointer<CBLManagerOptions>.allocate(capacity: 1)
        poptions.initialize(to: cbloptions)
        do {
            try self.manager = CBLManager(directory: CBLManager.defaultDirectory(), options: poptions)
        } catch {
            fatalError("Database manager no worky: \(error)")
        }
        
        // now we've set the queue
        self.manager.dispatchQueue = RECLINE_QUEUE
        
        // now ~open it
        do {
            self.db = try self.manager.databaseNamed(dbName)
        } catch {
            fatalError("Database '" + dbName + "' no worky: \(error)")
        }
        
        // set the typing metadata? don't know.
        self.typesView = self.db!.viewNamed("reclineType")
        self.typesView!.setMapBlock({ (doc: [String: Any], emit: CBLMapEmitBlock) in
            // I think this sets the return type to be a dict of string to any, because it is json.
            // I don't know what function this actually sets. (... map? mapblock?)
            if let reclineMeta: ReclineMetadata = Mapper<ReclineMetadata>().map(JSONObject: doc[kReclineMetadataKey]) {
                if let type = reclineMeta.type {
                    emit(type, Mapper<ReclineMetadata>().toJSON(reclineMeta))
                }
            }
        }, version: "5") // version arguument of setMapBlock
    }
    
    /// Save database changes. Template type is ObjectMapper types, mostly surevy and study, studysettings
    // todo: let's get a comprehensive list of types passed in here
    func save<T: ReclineObject>(_ obj: T) {
        guard let db = db else {
            fatalError("again the database is not instantiated - what do you think you are doing?")
        }
        // get or create the document.
        let doc: CBLDocument = if let _id = obj._id { db.document(withID: _id)! } else { db.createDocument() }
        
        // take the object, make a json version of it, and .... then we do something involving ReclineMetadata?
        var newProps: [String: Any] = Mapper<T>().toJSON(obj)
        let reclineMeta = ReclineMetadata(type: String(describing: type(of: obj)))
        newProps[kReclineMetadataKey] = Mapper<ReclineMetadata>().toJSON(reclineMeta)
        
        // couchbase uses a revisioning system for concurrency(?), so this is probably assigning an id and a revision
        newProps["_id"] = doc.properties!["_id"]
        newProps["_rev"] = doc.properties!["_rev"]
        
        // I think we are swallowing any errors
        do {
            try doc.putProperties(newProps) // commit to database
        } catch {
            fatalError("error saving to couchbase? \(error)")
        }
    }
    
    /// gets all rows in the typesView database view?
    // runs the query across everything and returns the contents.
    func queryAll<T: ReclineObject>() -> [T] {
        guard let typesView: CBLView = self.typesView else { // exit early
            fatalError("uh, you didn't open the database?")
            // throw ReclineErrors.databaseNotOpen
        }
        let results: CBLQueryEnumerator = queryOrExplode(typesView)
        
        var loadedObjects: [T] = []
        while let row = results.nextRow() {
            if let docId = row.documentID {
                loadedObjects.append(self.load(docId))
            }
        }
        return loadedObjects
    }

    // called from queryall
    func load<T: ReclineObject>(_ docId: String) -> T {
        // give up early if db is not instantiated
        guard let db = self.db else {
            fatalError("what are you doing the database isn't instantiated")
            // throw ReclineErrors.databaseNotOpen)
        }
        
        // get the _underlying_ document? it is apparently json, at least in our usage.
        let doc: CBLDocument? = db.document(withID: docId)
        if let doc = doc, let newMapperObj = Mapper<T>().map(JSONObject: doc.properties) {
            // yikes wtf is this
            newMapperObj._id = doc.properties?["_id"] as? String
            return newMapperObj
        } else {
            fatalError("ok it errored. don't know what this error is though.")
        }
    }
    
    // it is annoying to get the result of a query without it all this boiler plate, and all database operations
    // are supposed to succeed, so we wrap it and crash everything for convenience.
    func queryOrExplode(_ view: CBLView) -> CBLQueryEnumerator {
        let query: CBLQuery = view.createQuery()
        var result: CBLQueryEnumerator? = nil
        do {
            result = try query.run()
        } catch {
            fatalError("your query failed? \(error)")
        }
        if let result = result {
            return result
        } else {
            fatalError("your query completely failed? view: \(view.description), query: \(query.description)")}
    }
    
    // purges document from database...?
    func purge<T: ReclineObject>(_ obj: T) {
        if let object_id = obj._id {
            do {
                try db?.document(withID: object_id)?.purgeDocument()
            } catch {
                fatalError("error purging document: \(error)")
           }
        }
    }

    /// runs the database compact operation (why? we have a TINY database.
    func compact() {
        do {
            try self.db?.compact()
        } catch {
            fatalError("error compacting database: \(error)")
        }
    }
}


/// class for objects returned from a database query
class ReclineObject: Mappable {
    fileprivate var _id: String?
    init() {}
    required init?(map: Map) {}
    func mapping(map: Map) {} // Mappable
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
