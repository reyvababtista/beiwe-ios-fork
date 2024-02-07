import Foundation
import IDZSwiftCommonCrypto
import Security

enum DataStorageErrors: Error {
    case cantCreateFile
    case notInitialized
}

// TODO: convert All fatalError calls to sentry error reports with real error information.

//////////////////////////////////////////////////////////// DataStorage Manager //////////////////////////////////////////////////////
//////////////////////////////////////////////////////////// DataStorage Manager //////////////////////////////////////////////////////
//////////////////////////////////////////////////////////// DataStorage Manager //////////////////////////////////////////////////////
class DataStorageManager {
    static let sharedInstance = DataStorageManager()
    static let dataFileSuffix = ".csv"

    var storageTypes: [String: DataStorage] = [:]
    var secKeyRef: SecKey?
    var initted = false

    ///////////////////////////////////////////////// Setup //////////////////////////////////////////////////////
    
    /// instantiates your DataStorage object - called in every manager
    func createStore(_ type: String, headers: [String]) -> DataStorage {
        //! in order to avoid a race condition we cannot stash data on this object and then access it later, we need to access
        //! it through the StudyManager
        if !self.initted {
            // we tried accessing the keyRef variable on the study manager but that variable would be null.
            // No real understanding of why this code works, except that we always call the dataStorageManagerInit
            // externally to set it just before this runs in an external scope? that would be an Extremely
            // tight time window for a race condition...
            log.error("createStore called before the DataStorageManager received secKeyRef, app should crash now.")
        }
        
        if self.storageTypes[type] == nil {
            if let study = StudyManager.sharedInstance.currentStudy {
                if let patientId = study.patientId { // FIXME: need to identify if this has a patient id that is null or a public key
                    if let studySettings = study.studySettings {
                        if let publicKey = studySettings.clientPublicKey {
                            self.storageTypes[type] = DataStorage(
                                type: type,
                                headers: headers,
                                patientId: patientId,
                                publicKey: publicKey,
                                keyRef: self.secKeyRef
                            )
                        } else {
                            fatalError("(createStore) No public key found!")
                        }
                    } else {
                        fatalError("(createStore) No study settings found!")
                    }
                } else {
                    fatalError("(createStore) No patient id found!")
                }
            } else {
                fatalError("(createStore) No study found!")
            }
        }
        return self.storageTypes[type]!
    }

    func dataStorageManagerInit(_ study: Study, secKeyRef: SecKey?) {
        self.initted = true
        self.secKeyRef = secKeyRef
        // this function used to be called setCurrentStudy, but there was a looked-like-a-race-condition
        // in stashing these variables early on during app start, and then trying to access them later.
        // Fully removing the stashing of `self.secKeyRef` resulted in
        //   StudyManager().currentStudy?.keyRef
        // causing a null access (wrapped in an if-let statement so we know it was exactly .keyRef, not something else)
        // to occur.
        // Maybe the call to dataStorageManagerInit and passing the non-nullable study forces the compiler to block
        // until keyRef exists on StudyManager.currentStudy. Or somehow its the (optional tho?) secKeyRef that's passed in.
        
        // OLD CODE:
        // self.study = study
        // if let publicKey = study.studySettings?.clientPublicKey {
        //     self.publicKey = publicKey
        // }
    }

    /// see comment about race condition in createStore. We are using the same pattern here because we discovered a race condition
    /// in very similar code over there.
    func createEncryptedFile(type: String, suffix: String) -> EncryptedStorage {
        if !self.initted {
            log.error("createEncryptedFile called before the DataStorageManager received secKeyRef, app should crash now.")
        }
        
        if let study = StudyManager.sharedInstance.currentStudy {
            if let patientId = study.patientId {
                if let studySettings = study.studySettings {
                    if let publicKey = studySettings.clientPublicKey {
                        return EncryptedStorage(
                            data_stream_type: type,
                            suffix: suffix,
                            patientId: patientId,
                            publicKey: PersistentPasswordManager.sharedInstance.publicKeyName(patientId),
                            keyRef: self.secKeyRef
                        )
                    } else {
                        fatalError("(createEncryptedFile) No public key found!")
                    }
                } else {
                    fatalError("(createEncryptedFile) No study settings found!")
                }
            } else {
                fatalError("(createEncryptedFile) No patient id found!")
            }
        } else {
            fatalError("(createEncryptedFile) No study found!")
        }
    }
    
    /// creates the currentData and upload directories. app crashes if this fails because that is a fundamental app failure.
    func createDirectories(recur: Int = Constants.RECUR_DEPTH) {
        do {
            try FileManager.default.createDirectory(
                atPath: DataStorageManager.currentDataDirectory().path,
                withIntermediateDirectories: true,
                attributes: [FileAttributeKey(rawValue: FileAttributeKey.protectionKey.rawValue): FileProtectionType.none]
            )
            try FileManager.default.createDirectory(
                atPath: DataStorageManager.uploadDataDirectory().path,
                withIntermediateDirectories: true,
                attributes: [FileAttributeKey(rawValue: FileAttributeKey.protectionKey.rawValue): FileProtectionType.none]
            )
        } catch {
            print("\(error)")
            if recur > 0 {
                log.error("create_directories recur at \(recur).")
                Thread.sleep(forTimeInterval: Constants.RECUR_SLEEP_DURATION)
                return self.createDirectories(recur: recur - 1)
            }
            log.error("Failed to create directories. \(error)")
            fatalError("Failed to create directories. \(error)")
        }
    }
    
    ///////////////////////////////////////////////// Informational //////////////////////////////////////////////////////
    
    // TODO: we are using the cache directory, we should be using applicationSupportDirectory (Library/Application support/)
    // https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html
    static func currentDataDirectory() -> URL {
        let cacheDir = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        return URL(fileURLWithPath: cacheDir).appendingPathComponent("currentdata")
    }

    static func uploadDataDirectory() -> URL {
        let cacheDir = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        return URL(fileURLWithPath: cacheDir).appendingPathComponent("uploaddata")
    }
    
    func isUploadFile(_ filename: String) -> Bool {
        return filename.hasSuffix(DataStorageManager.dataFileSuffix) || filename.hasSuffix(".mp4") || filename.hasSuffix(".wav")
    }
    
    ///////////////////////////////////////////////// Teardown //////////////////////////////////////////////////////
    
    func closeStore(_ type: String) {
        // deletes a DataStorage object from the list
        // TODO: there is no corresponding close mechasims on datastorage objects themselves so... this is dangerous?
        self.storageTypes.removeValue(forKey: type)
    }

    // calls reset for all files
    private func resetAll() {
        for (_, storage) in self.storageTypes {
            storage.reset()
        }
    }
    
    ///////////////////////////////////////////////// Upload //////////////////////////////////////////////////////
    

    // private func prepareForUpload_actual() {
    func prepareForUpload() {
        // this is the only use of PRE_UPLOAD_QUEUE
        PRE_UPLOAD_QUEUE.sync {
            // TODO: this is a really dangerous general solution to ensuring files are getting uploaded...
            // Reset once to get all of the currently processing file paths.
            self.resetAll()
            var filesToUpload: [String] = []
            if let enumerator = FileManager.default.enumerator(atPath: DataStorageManager.currentDataDirectory().path) {
                // for each file check its file type and add to list
                while let filename = enumerator.nextObject() as? String {
                    if self.isUploadFile(filename) {
                        filesToUpload.append(filename)
                    } else {
                        log.warning("Non upload file sitting in directory: \(filename)")
                    }
                }
            }
            // move all data in the current data directory to the upload file directory.
            // active files are stored in a temp directory, then moved to the currentDataDirectory. this moves them to the upload directory.
            for filename in filesToUpload {
                self.moveFile(DataStorageManager.currentDataDirectory().appendingPathComponent(filename),
                              dst: DataStorageManager.uploadDataDirectory().appendingPathComponent(filename))
            }
        }
    }
    
    // move file function with retry logic, fails silently but that is ok because it is only used prepareForUpload_actual
    private func moveFile(_ src: URL, dst: URL, recur: Int = Constants.RECUR_DEPTH) {
        do {
            try FileManager.default.moveItem(at: src, to: dst)
        } catch {
            if recur > 0 {
                log.error("moveFile recur at \(recur).")
                Thread.sleep(forTimeInterval: Constants.RECUR_SLEEP_DURATION)
                return self.moveFile(src, dst: dst, recur: recur - 1)
            }
            log.error("Error moving \(src) to \(dst)")
            print("\(error)")
        }
    }
    
    // func _printFileInfo(_ file: URL) {
    //     // debugging function - unused
    //     let path = file.path
    //     var seekPos: UInt64 = 0
    //     var firstLine: String = ""
    //
    //     log.info("infoBeginForFile: \(path)")
    //     if let fileHandle = try? FileHandle(forReadingFrom: file) {
    //         defer {
    //             fileHandle.closeFile()
    //         }
    //         let dataString = String(data: fileHandle.readData(ofLength: 2048), encoding: String.Encoding.utf8)
    //         let dataArray = dataString?.split { $0 == "\n" }.map(String.init)
    //         if let dataArray = dataArray, dataArray.count > 0 {
    //             firstLine = dataArray[0]
    //         } else {
    //             log.warning("No first line found!!")
    //         }
    //         seekPos = fileHandle.seekToEndOfFile()
    //         fileHandle.closeFile()
    //     } else {
    //         log.error("Error opening file: \(path) for info")
    //     }
    //     log.info("infoForFile: len: \(seekPos), line: \(firstLine), filename: \(path)")
    // }
}

////////////////////////////////////////////////////// Data Storage ///////////////////////////////////////////////////////
////////////////////////////////////////////////////// Data Storage ///////////////////////////////////////////////////////
////////////////////////////////////////////////////// Data Storage ///////////////////////////////////////////////////////

class DataStorage {
    // participant info (to be factored out)
    var patientId: String // TODO: factor out
    var publicKey: String // string of the public key for local access. TODO: factor out
    var secKeyRef: SecKey? // TODO: make non-optional
    
    // file settings
    var headers: [String] // csv file header line
    var type: String // data stream type
    var name: String // name of this data storage object
    var sanitize: Bool // flag for the store function, replace commas with semicolons. TODO: factor out
    let moveOnClose: Bool // flag for whether to move the file (to the upload folder) when it is reset.
    
    // file state
    var aesKey: Data // the current encryption key
    var filename: URL // the current file name
    var realFilename: URL // the target file name that will be used eventually when the file is moved into the upload folder

    // Locks to deal with critical code. We have at-upload-time threading conflicts, and tighter write conflicts.
    var lock_write = NSLock() // lowest level, locks file seek and file write
    var lock_exists = NSLock() // locks on the exists check
    var lock_file_level_operation = NSLock()
    
    // flag used to implement lazy file creation on at the first write operation.
    var lazy_reset_active = false
    
    init(type: String, headers: [String], patientId: String, publicKey: String, moveOnClose: Bool = false, keyRef: SecKey?) {
        self.type = type
        self.patientId = patientId
        self.publicKey = publicKey
        self.headers = headers
        self.moveOnClose = moveOnClose
        self.secKeyRef = keyRef
        self.sanitize = false

        // these need to be instantiated due to rules about all values getting instantiated in the init function,
        // but they are immediately reset in self.reset()
        self.aesKey = Crypto.sharedInstance.newAesKey(Constants.KEYLENGTH)
        self.name = self.patientId + "_" + self.type + "_" + String(Int64(Date().timeIntervalSince1970 * 1000))
        self.realFilename = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(self.name + DataStorageManager.dataFileSuffix)
        self.filename = self.realFilename

        self.reset() // properly creates new mutables, sets lazy_reset_active to TRUE
    }
    
    ////////////////////////////////////// Locking, public functions ///////////////////////////////////////
    
    /// the write function used for all data streams.
    public func store(_ data: [String]) {
        defer {
            self.lock_file_level_operation.unlock()
        }
        self.lock_file_level_operation.lock()
        self.lazy_new_file_setup() // tests for whether lazy new file operations need to occur.
        self._store(data)
    }
    
    /// The public reset (create new file) function, all calls that are internal to the class should be to _reset() so lock.
    public func reset() {
        defer {
            self.lock_file_level_operation.unlock()
        }
        self._reset()
        self.lock_file_level_operation.lock()
    }
    
    /// To reduce junk file creation we have lazy initial file write.
    /// This function is called only inside store(), which is the only external function that should be called for writes.
    private func lazy_new_file_setup() {
        // do nothing if lazy_reset_active is not true - we could fatalError on that - this works because reset is actually called during init.
        if self.lazy_reset_active {
            // clear the flag
            self.lazy_reset_active = false
            // generate and write encryptiion key
            self.aesKey = Crypto.sharedInstance.newAesKey(Constants.KEYLENGTH)
            self.write_raw_to_end_of_file(self.get_rsa_line())
            self.encrypted_write(self.headers.joined(separator: Constants.DELIMITER))
            // log creating new file.
            self.conditionalApplog(event: "file_init", msg: "Init new data file", d1: self.name)
        }
    }
    
    /// synchronized function to ensure that a file exists
    // Keep _ensure_file_exists function from overlapping with itself, keep lock logic clean.
    // The inner recursive call should be to _ensure_file_exists.
    private func ensure_file_exists(recur: Int = Constants.RECUR_DEPTH) {
        defer {
            self.lock_exists.unlock()
        }
        self.lock_exists.lock()
        self._ensure_file_exists(recur: recur)
    }
    
    ////////////////////////////////////// Informational Functions /////////////////////////////////////////
    
    /// Returns the entire raw string of the first line of a file containing an RSA-encoded decryption key.
    private func get_rsa_line() -> Data {
        // TODO: why are these two functions are not identical, the call to encryptString
        //   have different args, publicKey vs publicKeyId. And self.secKeyRef is sometimes not present?
        if let keyRef = self.secKeyRef {
            return try! Crypto.sharedInstance.base64ToBase64URL(
                (SwiftyRSA.encryptString(
                    Crypto.sharedInstance.base64ToBase64URL(self.aesKey.base64EncodedString()),
                    publicKey: keyRef,
                    padding: []
                )) + "\n").data(using: String.Encoding.utf8)!
        } else {
            return try! Crypto.sharedInstance.base64ToBase64URL(
                (SwiftyRSA.encryptString(
                    Crypto.sharedInstance.base64ToBase64URL(self.aesKey.base64EncodedString()),
                    publicKeyId: PersistentPasswordManager.sharedInstance.publicKeyName(self.patientId),
                    padding: []
                )) + "\n").data(using: String.Encoding.utf8)!
        }
    }
    
    /// returns boolean about whether a file exists on the file system for self.
    private func check_file_exists() -> Bool {
        // operation profiled on an iphone 8 plus to take roughly 400-450us average/rms, standard deviation of 200us
        // print("checking that '\(self.filename.path)' exists...")
        return FileManager.default.fileExists(atPath: self.filename.path)
    }
    
    /// Unless self's "type" (data stream) is the ios log, write a message to the ios log.
    private func conditionalApplog(event: String, msg: String = "", d1: String = "", d2: String = "", d3: String = "", d4: String = "") {
        if self.type != "ios_log" {
            AppEventManager.sharedInstance.logAppEvent(event: event, msg: msg, d1: d1, d2: d2, d3: d3)
        }
    }
    
    /////////////////////////////////// Complex Functions (manages state) ///////////////////////////////////
    
    // generally resets all object assets and creates a new filename.
    // called when max filesize is reached, and inside resetAll.
    private func _reset(recur: Int = Constants.RECUR_DEPTH) {
        // we don't want to lazy reset while pending a new file due to an existing lazy reset.
        // (this is the singular file io condition under which we actually want to not do anything.)
        if self.lazy_reset_active {
            return
        }
            
        // log.info("DataStorage.reset called on \(self.name)...")
        if self.moveOnClose == true {
            do {
                if self.check_file_exists() {
                    try FileManager.default.moveItem(at: self.filename, to: self.realFilename)
                    print("moved temp data file \(self.filename) to \(self.realFilename)")
                }
            } catch {
                print("\(error)")
                log.error("Error moving temp data \(self.filename) to \(self.realFilename)")
                if recur > 0 {
                    log.error("reset recur at \(recur).")
                    Thread.sleep(forTimeInterval: Constants.RECUR_SLEEP_DURATION)
                    return self._reset(recur: recur - 1)
                }
                fatalError("Error moving temp data \(self.filename) to \(self.realFilename) \(error)")
            }
        }
        
        // set new filename and real filename mased on move on close
        self.name = self.patientId + "_" + self.type + "_" + String(Int64(Date().timeIntervalSince1970 * 1000))
        self.realFilename = DataStorageManager.currentDataDirectory().appendingPathComponent(self.name + DataStorageManager.dataFileSuffix)
        if self.moveOnClose {
            self.filename = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(self.name + DataStorageManager.dataFileSuffix)
        } else {
            self.filename = self.realFilename
        }
        
        // In an attempt to reduce file spam, the automatic creation of the next file when reset is called
        // is getting scrapped, we are going to set a flag and only generate and write that next line when
        // store is called.
        self.lazy_reset_active = true
    }
    
    /// all file paths in the scope of the app are of this form:
    /// /var/mobile/Containers/Data/Application/49ECF24B-85A4-40C1-BC57-92B742C6ED64/Library/Caches/currentdat(a/patientid_accel_1698721703289.csv
    /// the uuid is randomized per installation. We could remove it with a splice, but regex would be better. (not implemented)
    func shortenPath(_ path_string: String) -> String {
        return path_string.replacingOccurrences(of: "/var/mobile/Containers/Data/Application/", with: "")
    }

    func shortenPath(_ url: URL) -> String {
        return self.shortenPath(url.path)
    }
    
    /// unlocked function to ensure that a file exists.
    private func _ensure_file_exists(recur: Int) {
        // if there is no file, create it with these permissions and no data
        if !self.check_file_exists() {
            // print("creating file '\(self.shortenPath(self.filename))'...")
            let created = FileManager.default.createFile(
                atPath: self.filename.path,
                contents: "".data(using: String.Encoding.utf8),
                attributes: [FileAttributeKey(rawValue: FileAttributeKey.protectionKey.rawValue): FileProtectionType.none]
            )
            
            var message = if created { "Create new data file" } else { "Could not create new data file" }
            self.conditionalApplog(event: "file_create", msg: message, d1: self.name)
            if !created {
                // TODO; this is a really bad fatal error, need to not actually crash the app in this scenario
                if recur > 0 {
                    log.error("ensure_file_exists recur at \(recur).")
                    print("COULD NOT CREATE FILE '\(self.shortenPath(self.filename))'...")
                    Thread.sleep(forTimeInterval: Constants.RECUR_SLEEP_DURATION)
                    return self._ensure_file_exists(recur: recur - 1) // needs to actually call the _ version of the function (2.3.1 was incorrect, oops)
                }
                fatalError(message)
            }
        }
    }
    
    ///////////////////////////////////////// Actual write logic ///////////////////////////////////////////
    
    /// outer write operation, handles encrypting data and passes it off to the write_raw_to_end_of_file
    private func encrypted_write(_ line: String) {
        self.ensure_file_exists()
        let iv: Data = Crypto.sharedInstance.randomBytes(16)
        let encrypted = Crypto.sharedInstance.aesEncrypt(iv, key: self.aesKey, plainText: line)!
        let base64_data = (
            Crypto.sharedInstance.base64ToBase64URL(iv.base64EncodedString(options: []))
                + ":"
                + Crypto.sharedInstance.base64ToBase64URL(encrypted.base64EncodedString(options: []))
                + "\n"
        ).data(using: String.Encoding.utf8)!
        self.write_raw_to_end_of_file(base64_data)
    }

    /// Writes a line of data to the end of the current file, has locks to handle single-line-level write contention.
    private func write_raw_to_end_of_file(_ data: Data, recur: Int = Constants.RECUR_DEPTH) {
        self.ensure_file_exists()
        // if file handle instantiated (file open) append data (a line) to the end of the file.
        // it appears to be the case that lines are constructed ending with \n, so we don't handle that here.
        if let fileHandle = try? FileHandle(forWritingTo: self.filename) {
            // this lock blocks a write operation and seek opration, it blocks overlapping writes.
            defer {
                fileHandle.closeFile()
                self.lock_write.unlock()
            }
            // (all profiling done on a 5 year old iphone 8 plus)
            // seeks take on the order of 3us-, but writes are highly variant and depend on the size of the write.
            // Initial file writes are much longer, on the order of 10s of milliseconds.
            // The RMS of accelerometer/magnetomiter writes is just under 1ms. We do see writes as low as 10us.
            // lock/unlock almost always takes less than 3us.
            self.lock_write.lock()
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            // this data variable is a string of the full line in base64 including the iv. (i.e. it is encrypted)
            // print("write to \(self.filename), length: \(data.count), '\(String(data: data, encoding: String.Encoding.utf8))'")
        } else {
            // error opening file, reset and try again
            if recur > 0 {
                self._reset() // must call _reset() because we could be inside a locked reset()
                log.error("write_raw_to_end_of_file ERROR recur at \(recur).")
                Thread.sleep(forTimeInterval: Constants.RECUR_SLEEP_DURATION)
                return self.write_raw_to_end_of_file(data, recur: recur - 1)
            }
            // retry failed, time to crash :c
            log.error("Error opening file for writing")
            self.conditionalApplog(event: "file_err", msg: "Error writing to file", d1: self.name, d2: "Error opening file for writing")
            fatalError("unable to open file \(self.filename)")
        }
        if recur != Constants.RECUR_DEPTH {
            log.error("write_raw_to_end_of_file recur SUCCESS at \(recur).")
        }
    }
    
    /// This is the main write function for all write operations from all data streams
    // This function is dumb, it should be replaced entirely by encrypted write once the stupid TODO below is addressed.
    private func _store(_ data: [String]) {
        var sanitizedData: [String]
        if self.sanitize {
            // TODO: survey answers and survey timings files have a (naive) comma replacement behavior.
            // This Should Be Moved out of datastorage before the write operation (this factoring is... horrible.
            // Its So Bad. I cannot even. Who with a brain in their head thought this was a good idea.)
            sanitizedData = []
            for line in data {
                sanitizedData.append(
                    line.replacingOccurrences(of: ",", with: ";")
                        .replacingOccurrences(of: "[\t\n\r]", with: " ", options: .regularExpression)
                )
            }
        } else {
            sanitizedData = data
        }
        self.encrypted_write(sanitizedData.joined(separator: Constants.DELIMITER))
    }
}

/////////////////////////////////////////////////////// EncryptedStorage /////////////////////////////////////////////////////
/////////////////////////////////////////////////////// EncryptedStorage /////////////////////////////////////////////////////
/////////////////////////////////////////////////////// EncryptedStorage /////////////////////////////////////////////////////

// EncryptedStorage Originally included a buffered write pattern in AudioQuestionViewController.
// orig comment: only write multiples of 3, since we are base64 encoding and would otherwise end up with padding
//    if (isFlush) // don't know what this variable is anymore....
//        evenLength = self.currentData.length
//    else
//        evenLength = (self.currentData.length / 3) * 3
//    self._write(new_data, len: new_data.length)
//    self.currentData.replaceBytes(in: NSRange(0..<self.currentData.length), withBytes: nil, length: 0)
class EncryptedStorage {
    // (Binary, mostly for audio files) Encrypted Storage
    // files
    var filename: URL
    var eventualFilename: URL
    var debug_shortname: String
    let fileManager = FileManager.default
    var file_handle: FileHandle?
    // encryption
    var publicKey: String
    var aesKey: Data
    var iv: Data
    var secKeyRef: SecKey
    // machinery
    let encryption_queue: DispatchQueue
    var stream_cryptor: StreamCryptor

    init(data_stream_type: String, suffix: String, patientId: String, publicKey: String, keyRef: SecKey?) {
        // queue name
        self.encryption_queue = DispatchQueue(label: "beiwe.dataqueue." + data_stream_type, qos: .userInteractive, attributes: [])
        // file names
        self.debug_shortname = patientId + "_" + data_stream_type + "_" + String(Int64(Date().timeIntervalSince1970 * 1000))
        self.eventualFilename = DataStorageManager.currentDataDirectory().appendingPathComponent(self.debug_shortname + suffix)
        self.filename = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(self.debug_shortname + suffix)
        // encryption setup
        self.aesKey = Crypto.sharedInstance.newAesKey(Constants.KEYLENGTH)
        self.iv = Crypto.sharedInstance.randomBytes(16)
        self.publicKey = publicKey
        self.secKeyRef = keyRef!
        let data_for_key = (aesKey as NSData).bytes.bindMemory(to: UInt8.self, capacity: self.aesKey.count)
        let data_for_iv = (iv as NSData).bytes.bindMemory(to: UInt8.self, capacity: self.iv.count)
        self.stream_cryptor = StreamCryptor(
            operation: .encrypt,
            algorithm: .aes,
            options: .PKCS7Padding,
            key: Array(UnsafeBufferPointer(start: data_for_key, count: self.aesKey.count)),
            iv: Array(UnsafeBufferPointer(start: data_for_iv, count: self.iv.count))
        )
    }

    func open() {
        self.encryption_queue.sync {
            self.open_actual()
        }
    }

    func close() {
        self.encryption_queue.sync {
            self.close_actual()
        }
    }

    func write(_ data: NSData?, writeLen: Int) {
        // This is called directly in audio file code
        // log.info("write called on \(self.debug_shortname)...")
        encryption_queue.sync {
            self.write_actual(data, writeLen: writeLen)
        }
    }

    private func open_actual(recur: Int = Constants.RECUR_DEPTH) {
        // open file
        if !self.fileManager.createFile(
            atPath: self.filename.path,
            contents: nil,
            attributes: [FileAttributeKey(rawValue: FileAttributeKey.protectionKey.rawValue): FileProtectionType.none])
        {
            if recur > 0 {
                log.error("open_actual recur at \(recur).")
                Thread.sleep(forTimeInterval: Constants.RECUR_SLEEP_DURATION)
                return self.open_actual(recur: recur - 1)
            }
            fatalError("could not create file?")
        }
        self.file_handle = try! FileHandle(forWritingTo: self.filename)

        // write the rsa line and iv immediately
        let rsaLine: String = try! Crypto.sharedInstance.base64ToBase64URL(
            SwiftyRSA.encryptString(
                Crypto.sharedInstance.base64ToBase64URL(self.aesKey.base64EncodedString()),
                publicKey: self.secKeyRef,
                padding: []
            )
        ) + "\n"
        let ivHeader = Crypto.sharedInstance.base64ToBase64URL(self.iv.base64EncodedString()) + ":"
        self.file_handle?.write(rsaLine.data(using: String.Encoding.utf8)!)
        self.file_handle?.write(ivHeader.data(using: String.Encoding.utf8)!)
    }

    private func close_actual() {
        self.file_handle?.closeFile()
        self.file_handle = nil
        try! FileManager.default.moveItem(at: self.filename, to: self.eventualFilename)
        // log.info("moved temp data file \(self.filename) to \(self.eventualFilename)")
    }

    private func write_actual(_ data: NSData?, writeLen: Int) -> Int {
        // core write function, as much as anything here can be said to "write"
        // log.info("write_actual called on \(self.eventualFilename)...")
        let new_data: NSMutableData = NSMutableData()

        // setup to write - this case should be impossible
        if data != nil && writeLen != 0 {
            // log.info("write_actual case 1")
            // Need to encrypt data
            let encryptLen = self.stream_cryptor.getOutputLength(inputByteCount: writeLen)
            let bufferOut = UnsafeMutablePointer<Void>.allocate(capacity: encryptLen)
            var byteCount: Int = 0
            let bufferIn = UnsafeMutableRawPointer(mutating: data!.bytes)
            self.stream_cryptor.update(
                bufferIn: bufferIn,
                byteCountIn: writeLen,
                bufferOut: bufferOut,
                byteCapacityOut: encryptLen,
                byteCountOut: &byteCount
            )
            new_data.append(NSData(bytesNoCopy: bufferOut, length: byteCount) as Data)
        }

        // again, this case should be impossible
        let encryptLen = self.stream_cryptor.getOutputLength(inputByteCount: 0, isFinal: true)
        if encryptLen > 0 {
            // log.info("write_actual case 2")
            // mostly setup of these obscure pointers to an array of data (there must be a better way to do this...)
            let bufferOut = UnsafeMutablePointer<Void>.allocate(capacity: encryptLen)
            var byteCount: Int = 0
            self.stream_cryptor.final(bufferOut: bufferOut, byteCapacityOut: encryptLen, byteCountOut: &byteCount)
            // setup to write an array of appropriate length
            let finalData = NSData(bytesNoCopy: bufferOut, length: byteCount)
            var array = [UInt8](repeating: 0, count: finalData.length / MemoryLayout<UInt8>.size)
            // copy bytes into array (its an array of bytes, length is just length), append to new_data
            finalData.getBytes(&array, length: finalData.length)
            new_data.append(finalData as Data)
        }

        // this was formerly the _write function
        if new_data.length != 0 {
            // log.info("write_actual case 3")
            let dataToWriteBuffer = UnsafeMutableRawPointer(mutating: new_data.bytes)
            let dataToWrite = NSData(bytesNoCopy: dataToWriteBuffer, length: new_data.length, freeWhenDone: false)
            let encodedData: String = Crypto.sharedInstance.base64ToBase64URL(dataToWrite.base64EncodedString(options: []))
            self.file_handle?.write(encodedData.data(using: String.Encoding.utf8)!)
        }
        // log.info("write_actual finished")
        return new_data.length
    }

    deinit {
        if self.file_handle != nil {
            self.file_handle?.closeFile()
            self.file_handle = nil
        }
    }
}
