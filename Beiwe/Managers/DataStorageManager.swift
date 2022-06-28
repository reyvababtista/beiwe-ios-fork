//
//  DataStorageManager.swift
//  Beiwe
//
//  Created by Keary Griffin on 3/29/16.
//  Copyright © 2016 Rocketfarm Studios. All rights reserved.
//

import Foundation
import Security
import PromiseKit
import IDZSwiftCommonCrypto

enum DataStorageErrors : Error {
    case cantCreateFile
    case notInitialized
//    case RSA_LINE_FAILED_TO_WRITE
//    case AES_KEY_GENERATION_FAILED_1
//    case AES_KEY_GENERATION_FAILED_2
}


/*
 Encrypted Storage
 */

class EncryptedStorage {

    static let delimiter = ","
    let keyLength = 128

    let data_stream_type: String
    var filename: URL
    let fileManager = FileManager.default
    var file_handle: FileHandle?
    
    var publicKey: String
    var aesKey: Data
    var iv: Data
    var secKeyRef: SecKey
    
    var realFilename: URL
    var patientId: String
    
    let encryption_queue: DispatchQueue
    var stream_cryptor: StreamCryptor
    var currentData: NSMutableData = NSMutableData()  //TODO:100% purge this
    var hasData = false
    
    init(data_stream_type: String, suffix: String, patientId: String, publicKey: String, keyRef: SecKey?) {
        self.patientId = patientId
        self.publicKey = publicKey
        self.data_stream_type = data_stream_type
        self.secKeyRef = keyRef!
        
        self.encryption_queue = DispatchQueue(label: "com.rocketfarm.beiwe.dataqueue." + data_stream_type, attributes: [])
        
        let name = patientId + "_" + self.data_stream_type + "_" + String(Int64(Date().timeIntervalSince1970 * 1000))
        self.realFilename = DataStorageManager.currentDataDirectory().appendingPathComponent(name + suffix)
        self.filename = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name + suffix)
        self.aesKey = Crypto.sharedInstance.newAesKey(keyLength)!
        self.iv = Crypto.sharedInstance.randomBytes(16)!
        
        let data_for_key = (aesKey as NSData).bytes.bindMemory(to: UInt8.self, capacity: aesKey.count)
        let data_for_iv = (iv as NSData).bytes.bindMemory(to: UInt8.self, capacity: iv.count)
        
        self.stream_cryptor = StreamCryptor(
            operation: .encrypt,
            algorithm: .aes,
            options: .PKCS7Padding,
            key: Array(UnsafeBufferPointer(start: data_for_key, count: aesKey.count)),
            iv: Array(UnsafeBufferPointer(start: data_for_iv, count: iv.count))
        )
    }

    func open() -> Promise<Void> {
        return Promise().then(on: self.encryption_queue) {_ -> Promise<Void> in
            self.open_actual()
            return Promise()
        }
    }
    
    fileprivate func open_actual() -> Void {
        if (!self.fileManager.createFile(
            atPath: self.filename.path,
            contents: nil,
            attributes: [FileAttributeKey(rawValue: FileAttributeKey.protectionKey.rawValue): FileProtectionType.none])
        ) {
            // return closure 1
            fatalError("could not create file?")
        } else {
            log.info("Created a new encrypted file: \(self.filename)")
        }
        self.file_handle = try! FileHandle(forWritingTo: self.filename)
        
        // how do I catch this failing?
        var rsaLine: String = try! Crypto.sharedInstance.base64ToBase64URL(
            SwiftyRSA.encryptString(
                Crypto.sharedInstance.base64ToBase64URL(self.aesKey.base64EncodedString()),
                publicKey: self.secKeyRef,
                padding: []
            )
        )
        
        rsaLine = rsaLine + "\n"
        let line1 = rsaLine.data(using: String.Encoding.utf8)!
        let ivHeader = Crypto.sharedInstance.base64ToBase64URL(self.iv.base64EncodedString()) + ":"
        let line2 = ivHeader.data(using: String.Encoding.utf8)!
        log.info("write the rsa line 1 (rsa key): '\(rsaLine)', '\(line1)'")
        log.info("write the rsa line 2 (iv): '\(ivHeader)', '\(line2)'")
        self.file_handle?.write(line1)
        self.file_handle?.write(line2)
    }
    
    func close() -> Promise<Void> {
        return Promise().then(on: self.encryption_queue) { _ -> Promise<Void> in
            self.close_actual()
            return Promise()
        }
    }
    
    private func close_actual() {
        self.write_actual(nil, writeLen: 0)
        self.file_handle?.closeFile()
        self.file_handle = nil
        log.info("moved temp data file \(self.filename) to \(self.realFilename)")
        try! FileManager.default.moveItem(at: self.filename, to: self.realFilename)
    }
    
    private func _write(_ data: NSData, len: Int) -> Void {
        // TODO; what the hell is this return case? why is len even passed in?
        if (len == 0) {
            return
        }
        self.hasData = true
        let dataToWriteBuffer = UnsafeMutableRawPointer(mutating: data.bytes)
        let dataToWrite = NSData(bytesNoCopy: dataToWriteBuffer, length: len, freeWhenDone: false)
        let encodedData: String = Crypto.sharedInstance.base64ToBase64URL(dataToWrite.base64EncodedString(options: []))
        self.file_handle?.write(encodedData.data(using: String.Encoding.utf8)!)
    }
    
    func write(_ data: NSData?, writeLen: Int) -> Promise<Int> {
        // This is called directly in audio file code
        return Promise().then(on: self.encryption_queue) { _ -> Promise<Int> in
            let len: Int = self.write_actual(data, writeLen: writeLen)
            return .value(len)
        }
    }
    
    private func write_actual(_ data: NSData?, writeLen: Int) -> Int {
        // core write function, as much as anything here can be said to "write"
        if (data != nil && writeLen != 0) {
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
            self.currentData.append(NSData(bytesNoCopy: bufferOut, length: byteCount) as Data)
        }
        
        //TODO: why can this be 0, and what happens if this occurs
        let encryptLen = self.stream_cryptor.getOutputLength(inputByteCount: 0, isFinal: true)
        if (encryptLen > 0) {
            let bufferOut = UnsafeMutablePointer<Void>.allocate(capacity: encryptLen)
            var byteCount: Int = 0
            self.stream_cryptor.final(bufferOut: bufferOut, byteCapacityOut: encryptLen, byteCountOut: &byteCount)
            
            // setup to write
            let finalData = NSData(bytesNoCopy: bufferOut, length: byteCount)
            let count = finalData.length / MemoryLayout<UInt8>.size
            var array = [UInt8](repeating: 0, count: count)  // array of appropriate length:

            // copy bytes into array
            finalData.getBytes(&array, length:count * MemoryLayout<UInt8>.size)
            self.currentData.append(finalData as Data)
        }
        
        // Original comment;
        // Only write multiples of 3, since we are base64 encoding and would otherwise end up with padding
        //TODO: this is either purely base64 padding, or it interaccts with the self.currentdata nonsense
//        var evenLength: Int
//        if (isFlush) {
//            evenLength = self.currentData.length
//        } else {
//            evenLength = (self.currentData.length / 3) * 3
//        }
        
        self._write(self.currentData, len: self.currentData.length)
        self.currentData.replaceBytes(in: NSRange(0..<self.currentData.length), withBytes: nil, length: 0)  //TODO: delete this line?
        return self.currentData.length
    }
    

    deinit {
        if (self.file_handle != nil) {
            self.file_handle?.closeFile()
            self.file_handle = nil
        }
    }
}

/*
 Data Storage
 */

class DataStorage {

    static let delimiter = ","

    let flushLines = 100  // TODO PURGE
    let keyLength = 128

    var headers: [String]
    var type: String
    var lines: [String] = [ ]
    var aesKey: Data?
    var publicKey: String
    var hasData: Bool = false  //TODO: PURGE
    var filename: URL?
    var realFilename: URL?
    var dataPoints = 0
    var patientId: String
    var bytesWritten = 0  // TODO: check usage but probably PURGE
    var hasError = false  // TODO: PURGE
    var errMsg: String = ""
    var noBuffer = false  // TODO: PURGE
    var sanitize = false
    let moveOnClose: Bool
    let storage_ops_queue: DispatchQueue
    var name = ""
    var logClosures:[()->()] = [ ]
    var secKeyRef: SecKey?
    
    // flag used if the aes key generation ever fails, if it failse twice we fatally exit.
    var AES_KEY_GEN_FAIL: Bool = false
    

    init(type: String, headers: [String], patientId: String, publicKey: String, moveOnClose: Bool = false, keyRef: SecKey?) {
//        log.info("DataStorage.init")
//        log.info("type: \(type)")
//        log.info("headers: \(headers)")
//        log.info("patientId: \(patientId)")
//        log.info("publicKey: \(publicKey)")
//        log.info("moveOnClose: \(moveOnClose)")
//        log.info("keyRef: \(keyRef)")

        self.type = type
        self.patientId = patientId
        self.publicKey = publicKey
        
        self.headers = headers
        self.moveOnClose = moveOnClose
        self.secKeyRef = keyRef

        self.storage_ops_queue = DispatchQueue(label: "com.rocketfarm.beiwe.dataqueue." + type, attributes: [])
        self.logClosures = []
        self.reset()
        self.outputLogClosures()
    }

    private func outputLogClosures() {
        // TODO: this appears to be the place where we queue up and now execute any app log events.
        let tmpLogClosures: [()->()] = logClosures
        self.logClosures = []
        for a_promise in tmpLogClosures {
            a_promise()
        }
    }

    private func reset() {
        // called when max filesize is reached, inside flush when the file is empty,
        log.info("DataStorage.reset called...")
        if let filename = filename, let realFilename = realFilename, moveOnClose == true && hasData == true {
            do {
                try FileManager.default.moveItem(at: filename, to: realFilename)
                log.info("moved temp data file \(filename) to \(realFilename)")
            } catch {
                log.error("Error moving temp data \(filename) to \(realFilename)")
                fatalError("Error moving temp data \(filename) to \(realFilename)")
            }
        } else {
            log.info("weird non-reset reset scenario moveonclose was \(moveOnClose) and hasdata was \(hasData).")
        }
        let name = patientId + "_" + type + "_" + String(Int64(Date().timeIntervalSince1970 * 1000))
        self.name = name
        self.errMsg = ""
        self.hasError = false

        self.realFilename = DataStorageManager.currentDataDirectory().appendingPathComponent(name + DataStorageManager.dataFileSuffix)
        if (moveOnClose) {
            self.filename = URL(fileURLWithPath:  NSTemporaryDirectory()).appendingPathComponent(name + DataStorageManager.dataFileSuffix)
        } else {
            self.filename = realFilename
        }
        self.lines = [ ]
        self.dataPoints = 0
        self.bytesWritten = 0
        self.hasData = false
        self.aesKey = Crypto.sharedInstance.newAesKey(keyLength)
        
        if let aesKey = self.aesKey {  //TODO: make this not-optional
            do {
                var rsaLine: String?
                if let keyRef = self.secKeyRef {
                    rsaLine = try Crypto.sharedInstance.base64ToBase64URL(
                        SwiftyRSA.encryptString(
                            Crypto.sharedInstance.base64ToBase64URL(aesKey.base64EncodedString()),
                            publicKey: keyRef,
                            padding: []
                        )) + "\n"
                } else {
                    rsaLine = try Crypto.sharedInstance.base64ToBase64URL(
                        SwiftyRSA.encryptString(
                            Crypto.sharedInstance.base64ToBase64URL(aesKey.base64EncodedString()),
                            publicKeyId: PersistentPasswordManager.sharedInstance.publicKeyName(self.patientId),
                            padding: []
                        )) + "\n"
                }
                self.lines = [ rsaLine! ]
                self._writeLine(headers.joined(separator: DataStorage.delimiter))
            
            } catch let unkErr {
                // just error, this has actually been tested and doesn't seem to occur?  should be safe tho?
                self.errMsg = "RSAEncErr: " + String(describing: unkErr)
                self.lines = [ errMsg + "\n" ]
                self.hasError = true
                log.error(errMsg)
                log.error("AES KEY GENERATION FAILED, error clause 1, EXITING APP.")
            
                // We NEED an encryption key, that can't be allowed to fail.
                if AES_KEY_GEN_FAIL {
                    fatalError("AES KEY GENERATION FAILED, error clause 1.")
                } else {
                    self.AES_KEY_GEN_FAIL = true
                    self.reset()
                    self.AES_KEY_GEN_FAIL = false
                    return
                }
            }
        } else {
            self.errMsg = "Failed to generate AES key"
            self.lines = [ errMsg + "\n" ]
            self.hasError = true
            log.error(errMsg)
            log.error("AES KEY GENERATION FAILED, error clause 2, EXITING APP.")
            
            // We NEED an encryption key, that can't be allowed to fail.
            if AES_KEY_GEN_FAIL {
                fatalError("AES KEY GENERATION FAILED, error clause 2.")
            } else {
                self.AES_KEY_GEN_FAIL = true
                self.reset()  // TODO: this is insanely ugly code....
                self.AES_KEY_GEN_FAIL = false
                return
            }
        }

        if (self.type != "ios_log") {
            self.logClosures.append() {
                AppEventManager.sharedInstance.logAppEvent(
                    event: "file_init", msg: "Init new data file",
                    d1: name, d2: String(self.hasError), d3: self.errMsg
                )
            }
        }
    }

    private func _writeLine(_ line: String) {
        let iv: Data? = Crypto.sharedInstance.randomBytes(16)
        if let iv = iv, let aesKey = aesKey {
            let encrypted = Crypto.sharedInstance.aesEncrypt(iv, key: aesKey, plainText: line)
            if let encrypted = encrypted  {
                self.lines.append(
                    Crypto.sharedInstance.base64ToBase64URL(iv.base64EncodedString(options: []))
                    + ":"
                    + Crypto.sharedInstance.base64ToBase64URL(encrypted.base64EncodedString(options: []))
                    + "\n"
                )
                //TODO: ALWAYS FLUSH
                if (lines.count >= flushLines) {
                    self.flush(false)
                }
            }
        } else {
            //TODO: ABSOLUTELY NOT THIS CASE SHOULD CRASH
            self.errMsg = "Can't generate IV, skipping data"
            log.error(self.errMsg)
            self.hasError = true
            fatalError("ABSOLUTELY NOT THIS CASE SHOULD CRASH")
        }
    }

    private func writeLine(_ line: String) {
        self.hasData = true
        self.dataPoints = dataPoints + 1
        self._writeLine(line)
        if (self.noBuffer) {  // TODO: ALWAYS FLUSH WHYYYYY
            self.flush(false)
        }
    }

    func store(_ data: [String]) {
        // This appears to be the main write function for most app datastreams
        var sanitizedData: [String]
        
        if (self.sanitize) {
            // survey answers and survey timings files have a (naive) comma replacement behavior.
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
        let csv = sanitizedData.joined(separator: DataStorage.delimiter)
        self.writeLine(csv)
    }

    func flush(_ do_reset: Bool = false) -> Void {
        // TODO: remove entire reset concept in flush
        // flush does not flush. Like all other file io it appends to the list of closures.
        var force_reset = false
        self.logClosures = [ ]

// I am officially disabling this case. We will handle any fallout on the backend.
// This code is simply too stupid. Flush needs to actually do fileio in all possible scenarios.
//        if (!self.hasData || self.lines.count == 0) {
//            log.info("That insane flush case that makes no sense 1")
//            if (reset) {
//                log.info("That insane flush case that makes no sense 2")
//                self.reset()
//            }
//            return
//        }
            
        let data = self.lines.joined(separator: "").data(using: String.Encoding.utf8)
        self.lines = [ ]
        // TODO: this is getting purged later...
        if (self.type != "ios_log") {  //
            self.logClosures.append() {
                AppEventManager.sharedInstance.logAppEvent(
                    event: "file_flush", msg: "Flushing lines to file",
                    d1: self.name, d2: String(self.lines.count)
                )
            }
        }
            
        if let filename = self.filename, let data = data  {
            // if file name and data are populated
            let fileManager = FileManager.default
            
            if (!fileManager.fileExists(atPath: filename.path)) {
                // if no file exists
                if (!fileManager.createFile(
                    atPath: filename.path,
                    contents: data,
                    attributes: [FileAttributeKey(rawValue: FileAttributeKey.protectionKey.rawValue): FileProtectionType.none]
                )) {
                    // if creating a file failed
                    self.hasError = true
                    self.errMsg = "Failed to create file."
                    log.info(self.errMsg)
                    log.error(self.errMsg)
                    self.logClosures.append() {
                        AppEventManager.sharedInstance.logAppEvent(
                            event: "file_create", msg: "Could not new data file",
                            d1: self.name, d2: String(self.hasError), d3: self.errMsg
                        )
                    }
                    // almost definitely blocks the above log statement
                    fatalError("Could not create new data file - 1")
                } else {
                    // if creating a file succeeded
                    log.info("Create new data file: \(filename)")
                }
                if (self.type != "ios_log") {
                    // ios log special case
                    self.logClosures.append() {
                        AppEventManager.sharedInstance.logAppEvent(
                            event: "file_create", msg: "Create new data file",
                            d1: self.name, d2: String(self.hasError), d3: self.errMsg
                        )
                    }
                }
            } else {
                // if fie exists
                if let fileHandle = try? FileHandle(forWritingTo: filename) {
                    // if file handle instantiated (file open)
                    defer {
                        fileHandle.closeFile()
                    }
                    let seekPos = fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                    self.bytesWritten = self.bytesWritten + data.count
                    
                    // this data variable is a string of the full line in base64 including the iv. (i.e. it is encrypted)
                    log.info("Appended data to file: \(filename), size: \(seekPos): \(data)")
                } else {
                    // if error opening file
                    self.hasError = true
                    self.errMsg = "Error opening file for writing"
                    log.info(self.errMsg)
                    log.error(self.errMsg)
                    if (self.type != "ios_log") {
                        self.logClosures.append() {
                            AppEventManager.sharedInstance.logAppEvent(
                                event: "file_err", msg: "Error writing to file",
                                d1: self.name, d2: String(self.hasError), d3: self.errMsg
                            )
                        }
                    }
                    log.info("another unacceptable failure mode.")
                    fatalError("this is not a valid failure mode for this app")
                }
            }
        } else {
            // if there was no data or no filename
            self.errMsg = "No filename.  NO data??"
            log.error(self.errMsg)
            self.hasError = true
            if (self.type != "ios_log") {
                self.logClosures.append() {
                    AppEventManager.sharedInstance.logAppEvent(
                        event: "file_err", msg: "Error writing to file",
                        d1: self.name, d2: String(self.hasError), d3: self.errMsg
                    )
                }
            }
            force_reset = true
        }
        
        if (do_reset || force_reset) {
            // conditionally call reset
            self.reset()
        }
        self.outputLogClosures()
    }
}

class DataStorageManager {
    static let sharedInstance = DataStorageManager()
    static let dataFileSuffix = ".csv"

    var publicKey: String?
    var storageTypes: [String: DataStorage] = [:]
    var study: Study?
    var secKeyRef: SecKey?
    
    // FUXME: we are using the cache directory, we should be using applicationSupportDirectory (Library/Application support/)
    // https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html
    static func currentDataDirectory() -> URL {
        let cacheDir = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        return URL(fileURLWithPath: cacheDir).appendingPathComponent("currentdata")
    }

    static func uploadDataDirectory() -> URL {
        let cacheDir = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        return URL(fileURLWithPath: cacheDir).appendingPathComponent("uploaddata")
    }

    func createDirectories() {
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
            log.error("Failed to create directories.")
            fatalError("Failed to create directories.")
        }
    }

    func setCurrentStudy(_ study: Study, secKeyRef: SecKey?) {
        self.study = study
        self.secKeyRef = secKeyRef
        if let publicKey = study.studySettings?.clientPublicKey {
            self.publicKey = publicKey
        }

    }

    // TODO: WHYY IS THIS RETURN OPTIONAL
    func createStore(_ type: String, headers: [String]) -> DataStorage? {
        if (storageTypes[type] == nil) {
            if let publicKey = publicKey, let patientId = study?.patientId {
                storageTypes[type] = DataStorage(
                    type: type,
                    headers: headers,
                    patientId: patientId,
                    publicKey: publicKey,
                    keyRef: secKeyRef
                )
            } else {
                fatalError("No public key found! Can't store data")
                log.error("No public key found! Can't store data")
                return nil
            }
        }
        return storageTypes[type]!
    }

// This was the first result of removing then re-adding the promise, but I don't think it works as desired
//    func closeStore(_ type: String) -> Promise<Void> {
//        // has to return a promise due to conformance to a Protocol
//        let the_queue = DispatchQueue(label: "com.rocketfarm.beiwe.dataqueue." + type, attributes: [])
//        return Promise().then(on: the_queue) { _ -> Promise<Void> in
//            if let storage = self.storageTypes[type] {
//                self.storageTypes.removeValue(forKey: type)
//                storage.flush(false)
//            }
//            return Promise()
//        }
//    }
    
//    This is the original function
//    func closeStore(_ type: String) -> Promise<Void> {
//        // has to return a promise due to conformance to a Protocol
//        if let storage = storageTypes[type] {
//            self.storageTypes.removeValue(forKey: type)
//            return storage.flush(false)
//        }
//        return Promise()
//    }

    // OK, I think this is the best solution.
    // Keep the above commented code until actually sure about what this code... is for?
    func closeStore(_ type: String) -> Promise<Void> {
        // has to return a promise due to conformance to a Protocol
        if let storage = storageTypes[type] {
            self.storageTypes.removeValue(forKey: type)
            storage.flush(false)
        }
        return Promise()
    }

    
    func _flushAll() -> Void {
        // calls flush for all files
        for (_, storage) in storageTypes {
            storage.flush(true)
        }
    }
    
//    func _flushAll_old() -> Promise<Void> {
//        // calls flush for all files
//        var promises: [Promise<Void>] = []
//        for (_, storage) in storageTypes {
//            promises.append(storage.flush(true))
//        }
//        return when(fulfilled: promises)
//    }

    func isUploadFile(_ filename: String) -> Bool {
        return filename.hasSuffix(DataStorageManager.dataFileSuffix) || filename.hasSuffix(".mp4") || filename.hasSuffix(".wav")
    }
    
    private func _moveFile(_ src: URL, dst: URL) {
        do {
            try FileManager.default.moveItem(at: src, to: dst)
            log.info("moved \(src) to \(dst)")
        } catch {
            log.error("Error moving \(src) to \(dst)")
        }
    }
    
    func prepareForUpload() -> Promise<Void> {
        let prepQ = DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default)
        return Promise().then(on: prepQ) { _ -> Promise<Void> in
            self.prepareForUpload_actual()
            return Promise()
        }
    }
    
    private func prepareForUpload_actual() -> Void {
        //TODO: this is a really dangerous general solution to ensuring files are getting uploaded...
        let prepQ = DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default)
//        let prepQ = DispatchQueue.global(qos: DispatchQoS.QoSClass.utility)  // this is the fix for the warning, not changing atm.
        var filesToUpload: [String] = [ ]
        
        /* Flush once to get all of the files currently processing */
        self._flushAll()
        /* And record their names */
        let path = DataStorageManager.currentDataDirectory().path
        if let enumerator = FileManager.default.enumerator(atPath: path) {
            while let filename = enumerator.nextObject() as? String {
                if (self.isUploadFile(filename)) {
                    filesToUpload.append(filename)
                } else {
                    log.warning("Non upload file sitting in directory: \(filename)")
                }
            }
        }
        
        // TODO: This next section is almost definitely garbage
//        /* Need to flush again, because there is (very slim) one of those files was created after the flush */
//        /** This line is the best candidate for corrupted files. */
//        self._flushAll()
//        return
        // and move files
        for filename in filesToUpload {
            self._moveFile(DataStorageManager.currentDataDirectory().appendingPathComponent(filename),
                           dst: DataStorageManager.uploadDataDirectory().appendingPathComponent(filename))
        }
    }
    
    func createEncryptedFile(type: String, suffix: String) -> EncryptedStorage {
        return EncryptedStorage(
            data_stream_type: type,
            suffix: suffix,
            patientId: study!.patientId!,
            publicKey: PersistentPasswordManager.sharedInstance.publicKeyName(study!.patientId!),
            keyRef: secKeyRef
        )
    }
    
    func _printFileInfo(_ file: URL) {
        // debugging function - unused
        let path = file.path
        var seekPos: UInt64 = 0
        var firstLine: String = ""
        
        log.info("infoBeginForFile: \(path)")
        if let fileHandle = try? FileHandle(forReadingFrom: file) {
            defer {
                fileHandle.closeFile()
            }
            let dataString = String(data: fileHandle.readData(ofLength: 2048), encoding: String.Encoding.utf8)
            let dataArray = dataString?.split{$0 == "\n"}.map(String.init)
            if let dataArray = dataArray, dataArray.count > 0 {
                firstLine = dataArray[0]
            } else {
                log.warning("No first line found!!")
            }
            seekPos = fileHandle.seekToEndOfFile()
            fileHandle.closeFile()
        } else {
            log.error("Error opening file: \(path) for info")
        }
        log.info("infoForFile: len: \(seekPos), line: \(firstLine), filename: \(path)")
    }
}
