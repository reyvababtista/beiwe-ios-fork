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
}

let DELIMITER = ","
let KEYLENGTH = 128

// TODO: convert All fatalError calls to sentry error reports with real error information.

/*
 Encrypted Storage
 */

class EncryptedStorage {
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
        
        let new_name = patientId + "_" + self.data_stream_type + "_" + String(Int64(Date().timeIntervalSince1970 * 1000))
        self.realFilename = DataStorageManager.currentDataDirectory().appendingPathComponent(new_name + suffix)
        self.filename = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(new_name + suffix)
        self.aesKey = Crypto.sharedInstance.newAesKey(KEYLENGTH)
        self.iv = Crypto.sharedInstance.randomBytes(16)
        
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
    
    private func open_actual() -> Void {
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
    var headers: [String]
    var type: String
    var aesKey: Data
    var publicKey: String
    var filename: URL
    var realFilename: URL
    var patientId: String
    var hasError = false  // This is used as a return value from io operations in other parts of the codebase
    var errMsg: String = ""
    var sanitize = false
    let moveOnClose: Bool
    var name = ""
    var secKeyRef: SecKey?  //TODO: make non-optional

    init(type: String, headers: [String], patientId: String, publicKey: String, moveOnClose: Bool = false, keyRef: SecKey?) {
        self.type = type
        self.patientId = patientId
        self.publicKey = publicKey
        
        self.headers = headers
        self.moveOnClose = moveOnClose
        self.secKeyRef = keyRef
        
        // these need to be instantiated to allow non-optionals, they are immediately reset in self.reset()
        self.aesKey = Crypto.sharedInstance.newAesKey(KEYLENGTH)
        self.realFilename = URL(fileURLWithPath:  NSTemporaryDirectory()).appendingPathComponent(self.name + DataStorageManager.dataFileSuffix)
        self.filename = realFilename

        self.reset() // properly creates mutables
    }
    
    private func reset() {
        // called when max filesize is reached, inside flush when the file is empty
        // generally resets all object assets and creates a new filename.
        log.info("DataStorage.reset called on \(self.name)...")
        if moveOnClose == true {
            do {
                if check_file_exists() {
                    try FileManager.default.moveItem(at: self.filename, to: self.realFilename)
                    log.info("moved temp data file \(self.filename) to \(self.realFilename)")
                }
            } catch {
                log.error("Error moving temp data \(self.filename) to \(self.realFilename)")
                fatalError("Error moving temp data \(self.filename) to \(self.realFilename)")
            }
        }
        self.errMsg = ""
        self.hasError = false
        // set new name, filenames
        self.name = patientId + "_" + type + "_" + String(Int64(Date().timeIntervalSince1970 * 1000))
        self.realFilename = DataStorageManager.currentDataDirectory().appendingPathComponent(self.name + DataStorageManager.dataFileSuffix)
        
        if (moveOnClose) {
            self.filename = URL(fileURLWithPath:  NSTemporaryDirectory()).appendingPathComponent(self.name + DataStorageManager.dataFileSuffix)
        } else {
            self.filename = realFilename
        }
        
        // generate and write encryptiion key
        self.aesKey = Crypto.sharedInstance.newAesKey(KEYLENGTH)
        self.write_raw_to_end_of_file(self.get_rsa_line())
        self.encrypted_write(headers.joined(separator: DELIMITER))

        // log creating new file.
        self.conditionalApplog(event: "file_init", msg: "Init new data file", d1: self.name)
    }
    
    private func get_rsa_line() -> Data {
        // Returns the entire raw string of the first line of a file containing an RSA-encoded decryption key.
        // TODO: why are these two functions are not identical, the call to encryptString
        //   have different args, publicKey vs publicKeyId. And self.secKeyRef is sometimes not present?
        
        if let keyRef = self.secKeyRef {
            return try! Crypto.sharedInstance.base64ToBase64URL(
                (SwiftyRSA.encryptString(
                    Crypto.sharedInstance.base64ToBase64URL(aesKey.base64EncodedString()),
                    publicKey: keyRef,
                    padding: []
                )) + "\n" ).data(using: String.Encoding.utf8)!
        } else {
            return try! Crypto.sharedInstance.base64ToBase64URL(
                (SwiftyRSA.encryptString(
                    Crypto.sharedInstance.base64ToBase64URL(aesKey.base64EncodedString()),
                    publicKeyId: PersistentPasswordManager.sharedInstance.publicKeyName(self.patientId),
                    padding: []
                )) + "\n").data(using: String.Encoding.utf8)!
        }
    }
    
    private func encrypted_write(_ line: String) {
        self.ensure_file_exists()
        let iv: Data = Crypto.sharedInstance.randomBytes(16)
        let encrypted = Crypto.sharedInstance.aesEncrypt(iv, key: aesKey, plainText: line)!
        let base64_data = (
            Crypto.sharedInstance.base64ToBase64URL(iv.base64EncodedString(options: []))
            + ":"
            + Crypto.sharedInstance.base64ToBase64URL(encrypted.base64EncodedString(options: []))
            + "\n"
        ).data(using: String.Encoding.utf8)!
        write_raw_to_end_of_file(base64_data)
    }
    
    func check_file_exists() -> Bool {
        return FileManager.default.fileExists(atPath: filename.path)
    }
    
    func ensure_file_exists() {
        // if there is no file, create it with these permissions and no data
        if (!check_file_exists()) {
            let created = FileManager.default.createFile(
                atPath: filename.path,
                contents: "".data(using: String.Encoding.utf8),
                attributes: [FileAttributeKey(rawValue: FileAttributeKey.protectionKey.rawValue): FileProtectionType.none]
            )
            var message: String
            if created {
                message = "Create new data file"
            } else {
                message = "Could not create new data file"
            }
            log.error("\(message): \(filename)")
            self.conditionalApplog(event: "file_create", msg: message, d1: self.name, d2: self.errMsg)
            if !created {
                //TODO; this is a really bad fatal error, need to not actually crash the app in this scenario
                fatalError(message)
            }
        }
    }
    
    func write_raw_to_end_of_file(_ data: Data) {
        ensure_file_exists()
        // if file handle instantiated (file open) append data (a line) to the end of the file.
        // it appears to be the case that lines are constructed ending with \n, so we don't handle that here.
        if let fileHandle = try? FileHandle(forWritingTo: self.filename) {
            defer {
                fileHandle.closeFile()
            }
            let seekPos = fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
            
            // this data variable is a string of the full line in base64 including the iv. (i.e. it is encrypted)
            // log.info("Appended data to file: \(filename), size: \(seekPos): \(data)")
            if seekPos == 0 {
                log.error("empty file write to \(self.filename): '\(data)'")
            }
        } else { // error opening file
            self.hasError = true
            self.errMsg = "Error opening file for writing"
            log.error(self.errMsg)
            self.conditionalApplog(
                event: "file_err", msg: "Error writing to file", d1: self.name, d2: self.errMsg
            )
            // TODO: make this not crash the app...
            fatalError("unable to open file \(self.filename)")
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
        // This code was originally writted as follows (pseudocode)
        //   ln[1]: self.do_actual_file_io_immediately(some_data)
        //   ln[2]: self.flush()
        // The problem is that flush function simply isn't a classic io-is-buffered-so-call-flush-to-be-sure call.
        // Instead the code [used to, I'm trying to remove it] implemented a caching mechanism, and flush would flush the cache.
        // This function explicitly bypassed the cache, and would write to the file before other cached/buffered file io executed.
        // If the initial write operation of a file, the RSA-encrypted decryption key, was in the cache (it would be) then that
        // line would occur after `some_data` was written, breaking the expected format of the data.
        // Until we make all io immediate (in progress) the order needs to be reversed.
        self.encrypted_write(sanitizedData.joined(separator: DELIMITER))
    }
    
    func flush(_ do_reset: Bool = false) -> Void {
        // This flush call currently exists to allow conditional calls to reset, I guess.
        if (do_reset) {
            // conditionally call reset
            self.reset()
        }
    }
    
    private func conditionalApplog(event: String, msg: String = "", d1: String = "", d2: String = "", d3: String = "", d4: String = "") {
        if (self.type != "ios_log") {
            AppEventManager.sharedInstance.logAppEvent(event: event, msg: msg, d1: d1, d2: d2, d3: d3, d4: d4)
        }
    }
}

class DataStorageManager {
    static let sharedInstance = DataStorageManager()
    static let dataFileSuffix = ".csv"

    var publicKey: String?
    var storageTypes: [String: DataStorage] = [:]
    var study: Study?
    var secKeyRef: SecKey?
    
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
