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


class EncryptedStorage {

    static let delimiter = ","
    let keyLength = 128

    let type: String
    var filename: URL
    let fileManager = FileManager.default
    var file_handle: FileHandle?
    
    var publicKey: String
    var aesKey: Data
    var iv: Data
    var secKeyRef: SecKey?
    
    var realFilename: URL
    var patientId: String
    
    let encryption_queue: DispatchQueue
    var stream_cryptor: StreamCryptor
    var currentData: NSMutableData = NSMutableData()
    var hasData = false
    
    init(type: String, suffix: String, patientId: String, publicKey: String, keyRef: SecKey?) {
        self.patientId = patientId
        self.publicKey = publicKey
        self.type = type
        self.secKeyRef = keyRef
        
        self.encryption_queue = DispatchQueue(label: "com.rocketfarm.beiwe.dataqueue." + type, attributes: [])
        
        let name = patientId + "_" + type + "_" + String(Int64(Date().timeIntervalSince1970 * 1000))
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
        // THIS FUNCTION IS ONLY USED IN MEDIA FILE ENCRYPTION
        return Promise().then(on: self.encryption_queue) {_ -> Promise<Void> in
            // closure 1
            if (!self.fileManager.createFile(
                atPath: self.filename.path,
                contents: nil,
                attributes: [FileAttributeKey(rawValue: FileAttributeKey.protectionKey.rawValue): FileProtectionType.none])
            ) {
                // return closure 1
                return Promise(error: DataStorageErrors.cantCreateFile)
            } else {
                log.info("Create new enc file: \(self.filename)")
            }
            self.file_handle = try? FileHandle(forWritingTo: self.filename)
            
            // what case does this handle and why doesn't it count as bad initialization?
            var rsaLine: String = ""
            var rsaLine_fail_1 = false
            var rsaLine_fail_2 = false
            if let keyRef = self.secKeyRef {
                log.info("that keyRef EXISTS case when creating an encrypted file - 1")
                rsaLine_fail_1 = true
                rsaLine = try Crypto.sharedInstance.base64ToBase64URL(
                    SwiftyRSA.encryptString(
                        Crypto.sharedInstance.base64ToBase64URL(self.aesKey.base64EncodedString()),
                        publicKey: keyRef,
                        padding: []
                    )
                )
            } else {
                log.info("that keyRef DOES NOT EXIST case when creating an encrypted file - 2")
                rsaLine_fail_2 = true
                rsaLine = try Crypto.sharedInstance.base64ToBase64URL(
                    SwiftyRSA.encryptString(
                        Crypto.sharedInstance.base64ToBase64URL(self.aesKey.base64EncodedString()),
                        publicKeyId: PersistentPasswordManager.sharedInstance.publicKeyName(self.patientId),
                        padding: []
                    )
                )
            }
            
            if rsaLine == "" {
                if rsaLine_fail_1 {
                    fatalError("RSA LINE FAILED TO WRITE, CONDITION 1")
                } else if rsaLine_fail_2 {
                    fatalError("RSA LINE FAILED TO WRITE, CONDITION 2")
                } else {
                    fatalError("RSA LINE FAILED TO WRITE, UNCONDITION 3")
                }
            }
            
            rsaLine = rsaLine + "\n"
            let line1 = rsaLine.data(using: String.Encoding.utf8)!
            let ivHeader = Crypto.sharedInstance.base64ToBase64URL(self.iv.base64EncodedString()) + ":"
            let line2 = ivHeader.data(using: String.Encoding.utf8)!
            log.info("write the rsa line 1 (rsa key): '\(rsaLine)', '\(line1)'")
            log.info("write the rsa line 2 (iv): '\(ivHeader)', '\(line2)'")
            self.file_handle?.write(line1)
            self.file_handle?.write(line2)
            
            return Promise() // return closure
        }
    }

    func close() -> Promise<Void> {
        return write(nil, writeLen: 0, isFlush: true).then(on: self.encryption_queue) { _ -> Promise<Void> in
            if let handle = self.file_handle {
                handle.closeFile()
                self.file_handle = nil
                try FileManager.default.moveItem(at: self.filename, to: self.realFilename)
                log.info("moved temp data file \(self.filename) to \(self.realFilename)")
            }
            return Promise()
        }
    }

    func _write(_ data: NSData, len: Int) -> Promise<Int> {
        if (len == 0) {
            return .value(0)
        }
        return Promise().then(on: self.encryption_queue) { _ -> Promise<Int> in
            self.hasData = true
            let dataToWriteBuffer = UnsafeMutableRawPointer(mutating: data.bytes)
            let dataToWrite = NSData(bytesNoCopy: dataToWriteBuffer, length: len, freeWhenDone: false)
            let encodedData: String = Crypto.sharedInstance.base64ToBase64URL(dataToWrite.base64EncodedString(options: []))
            self.file_handle?.write(encodedData.data(using: String.Encoding.utf8)!)
            return .value(len)
        }

    }

    func write(_ data: NSData?, writeLen: Int, isFlush: Bool = false) -> Promise<Void> {
        // core write function, as much as anything here can be said to "write"
        return Promise().then(on: self.encryption_queue) { _ -> Promise<Int> in
            
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
            
            if (isFlush) {
                let encryptLen = self.stream_cryptor.getOutputLength(inputByteCount: 0, isFinal: true)
                if (encryptLen > 0) {
                    let bufferOut = UnsafeMutablePointer<Void>.allocate(capacity: encryptLen)
                    var byteCount: Int = 0
                    self.stream_cryptor.final(bufferOut: bufferOut, byteCapacityOut: encryptLen, byteCountOut: &byteCount)
                    let finalData = NSData(bytesNoCopy: bufferOut, length: byteCount)

                    let count = finalData.length / MemoryLayout<UInt8>.size

                    // create array of appropriate length:
                    var array = [UInt8](repeating: 0, count: count)

                    // copy bytes into array
                    finalData.getBytes(&array, length:count * MemoryLayout<UInt8>.size)
                    self.currentData.append(finalData as Data)
                }
            }
            
            // Only write multiples of 3, since we are base64 encoding and would otherwise end up with padding
            var evenLength: Int
            if (isFlush) {
                evenLength = self.currentData.length
            } else {
                evenLength = (self.currentData.length / 3) * 3
            }
            
            return self._write(self.currentData, len: evenLength)
            
        }.done(on: self.encryption_queue) { evenLength in
            self.currentData.replaceBytes(in: NSRange(0..<evenLength), withBytes: nil, length: 0)
        }
    }

    deinit {
        if (self.file_handle != nil) {
            self.file_handle?.closeFile()
            self.file_handle = nil
        }
    }
}

class DataStorage {

    static let delimiter = ","

    let flushLines = 100
    let keyLength = 128

    var headers: [String]
    var type: String
    var lines: [String] = [ ]
    var aesKey: Data?
    var publicKey: String
    var hasData: Bool = false
    var filename: URL?
    var realFilename: URL?
    var dataPoints = 0
    var patientId: String
    var bytesWritten = 0
    var hasError = false
    var errMsg: String = ""
    var noBuffer = false
    var sanitize = false
    let moveOnClose: Bool
    let storage_ops_queue: DispatchQueue
    var name = ""
    var logClosures:[()->()] = [ ]
    var secKeyRef: SecKey?
    
    // flag used if the aes key generation ever fails, if it failse twice we literally exit with a error code 1.
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

    fileprivate func outputLogClosures() {
        // THIS IS A SYNCHRONIZATION PRIMITIVE
        // in order to handle all write synchronization all write operations are created as promises and then executed on *here*
        let tmpLogClosures: [()->()] = logClosures
        self.logClosures = []
        for a_promise in tmpLogClosures {
            a_promise()
        }
    }

    fileprivate func reset() {
        // called when max filesize is reached, inside flush when the file is empty,
        log.info("DataStorage.reset called...")
        if let filename = filename, let realFilename = realFilename, moveOnClose == true && hasData == true {
            do {
                try FileManager.default.moveItem(at: filename, to: realFilename)
                log.info("moved temp data file \(filename) to \(realFilename)")
            } catch {
                log.error("Error moving temp data \(filename) to \(realFilename)")
            }
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
        
        if let aesKey = self.aesKey {
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
                self.reset()
                self.AES_KEY_GEN_FAIL = false
                return
            }
        }

        if (type != "ios_log") {
            self.logClosures.append() {
                AppEventManager.sharedInstance.logAppEvent(
                    event: "file_init",
                    msg: "Init new data file",
                    d1: name,
                    d2: String(self.hasError),
                    d3: self.errMsg
                )
            }
        }
    }

    fileprivate func _writeLine(_ line: String) {
        let iv: Data? = Crypto.sharedInstance.randomBytes(16)
        if let iv = iv, let aesKey = aesKey {
            let encrypted = Crypto.sharedInstance.aesEncrypt(iv, key: aesKey, plainText: line)
            if let encrypted = encrypted  {
                lines.append(
                    Crypto.sharedInstance.base64ToBase64URL(iv.base64EncodedString(options: []))
                    + ":"
                    + Crypto.sharedInstance.base64ToBase64URL(encrypted.base64EncodedString(options: []))
                    + "\n"
                )
                if (lines.count >= flushLines) {
                    self.flush(false)
                }
            }
        } else {
            self.errMsg = "Can't generate IV, skipping data"
            log.error(self.errMsg)
            self.hasError = true
        }
    }

    fileprivate func writeLine(_ line: String) {
        self.hasData = true
        self.dataPoints = dataPoints + 1
        self._writeLine(line)
        if (noBuffer) {
            self.flush(false)
        }
    }

    func store(_ data: [String]) -> Promise<Void> {
        return Promise().then(on: storage_ops_queue) { _ -> Promise<Void> in
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
            return Promise()
        }
    }

    func flush(_ do_reset: Bool = false) -> Promise<Void> {
        // flush does not flush. Like all other file io it appends to the list of closures.
        var force_reset = false
        return Promise().then(on: storage_ops_queue) { _ -> Promise<Void> in
            self.logClosures = [ ]

// I am officially disabling this case. We will handle any fallout on the backend.
// This code is simply too stupid. Flush needs to actually do fileio in all possible scenarios.
//            if (!self.hasData || self.lines.count == 0) {
//                log.info("That insane flush case that makes no sense 1")
//                if (reset) {
//                    log.info("That insane flush case that makes no sense 2")
//                    self.reset()
//                }
//                return Promise()
//            }
            
            let data = self.lines.joined(separator: "").data(using: String.Encoding.utf8)
            self.lines = [ ]
            if (self.type != "ios_log") {
                self.logClosures.append() {
                    AppEventManager.sharedInstance.logAppEvent(
                        event: "file_flush",
                        msg: "Flushing lines to file",
                        d1: self.name,
                        d2: String(self.lines.count)
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
                                event: "file_create",
                                msg: "Could not new data file",
                                d1: self.name,
                                d2: String(self.hasError),
                                d3: self.errMsg
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
                                event: "file_create",
                                msg: "Create new data file",
                                d1: self.name,
                                d2: String(self.hasError),
                                d3: self.errMsg
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
                                    event: "file_err",
                                    msg: "Error writing to file",
                                    d1: self.name,
                                    d2: String(self.hasError),
                                    d3: self.errMsg
                                )
                            }
                        }
                        
                        log.info("another unacceptable failure mode.")
                        exit(1)
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
                            event: "file_err",
                            msg: "Error writing to file",
                            d1: self.name,
                            d2: String(self.hasError),
                            d3: self.errMsg
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
            return Promise()
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

    static func currentDataDirectory() -> URL {
        let dirPaths = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
        let cacheDir = dirPaths[0]
        return URL(fileURLWithPath: cacheDir).appendingPathComponent("currentdata")
    }

    static func uploadDataDirectory() -> URL {
        let dirPaths = NSSearchPathForDirectoriesInDomains(.cachesDirectory,
                                                           .userDomainMask, true)

        let cacheDir = dirPaths[0]
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
        }
    }

    func setCurrentStudy(_ study: Study, secKeyRef: SecKey?) {
        self.study = study
        self.secKeyRef = secKeyRef
        if let publicKey = study.studySettings?.clientPublicKey {
            self.publicKey = publicKey
        }

    }

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
                log.error("No public key found! Can't store data")
                return nil
            }
        }
        return storageTypes[type]!
    }

    func closeStore(_ type: String) -> Promise<Void> {
        if let storage = storageTypes[type] {
            self.storageTypes.removeValue(forKey: type)
            return storage.flush(false)
        }
        return Promise()
    }

    func _flushAll() -> Promise<Void> {
        // calls flush for all files
        var promises: [Promise<Void>] = []
        for (_, storage) in storageTypes {
            promises.append(storage.flush(true))
        }
        return when(fulfilled: promises)
    }

    func isUploadFile(_ filename: String) -> Bool {
        return filename.hasSuffix(DataStorageManager.dataFileSuffix) || filename.hasSuffix(".mp4") || filename.hasSuffix(".wav")
    }
    
    func _moveFile(_ src: URL, dst: URL) {
        do {
            try FileManager.default.moveItem(at: src, to: dst)
            log.info("moved \(src) to \(dst)")
        } catch {
            log.error("Error moving \(src) to \(dst)")
        }
    }
    
    func prepareForUpload() -> Promise<Void> {
        let prepQ = DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default)
//        let prepQ = DispatchQueue.global(qos: DispatchQoS.QoSClass.utility)  // this is the fix for the warning, not changing atm.
        var filesToUpload: [String] = [ ]
        
        /* Flush once to get all of the files currently processing */
        return self._flushAll().then(on: prepQ) { _ -> Promise<Void> in
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
        
            /* Need to flush again, because there is (very slim) one of those files was created after the flush */
            /** This line is the best candidate for corrupted files. */
            return self._flushAll()
        }.then(on: prepQ) { _ -> Promise<Void> in
            for filename in filesToUpload {
                self._moveFile(DataStorageManager.currentDataDirectory().appendingPathComponent(filename),
                               dst: DataStorageManager.uploadDataDirectory().appendingPathComponent(filename))
            }
            return Promise()
        }
    }
    
    func createEncryptedFile(type: String, suffix: String) -> EncryptedStorage {
        return EncryptedStorage(
            type: type,
            suffix: suffix,
            patientId: study!.patientId!,
            publicKey: PersistentPasswordManager.sharedInstance.publicKeyName(study!.patientId!),
            keyRef: secKeyRef
        )
    }
    
    func _printFileInfo(_ file: URL) {
        // debugging function
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
