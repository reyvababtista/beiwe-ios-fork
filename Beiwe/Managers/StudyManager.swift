//
//  StudyManager.swift
//  Beiwe
//
//  Created by Keary Griffin on 3/29/16.
//  Copyright © 2016 Rocketfarm Studios. All rights reserved.
//

import Foundation
import PromiseKit
import ReachabilitySwift
import EmitterKit
import Crashlytics
import Firebase

class StudyManager {
    static let sharedInstance = StudyManager()
    static var real_study_loaded = false

    let MAX_UPLOAD_DATA: Int64 = 250 * (1024 * 1024)
    let appDelegate = UIApplication.shared.delegate as! AppDelegate
    let calendar = Calendar.current
    var keyRef: SecKey?

    var currentStudy: Study?
    var gpsManager: GPSManager?
    var isUploading = false
    let surveysUpdatedEvent: Event<Int> = Event<Int>()
    var isStudyLoaded: Bool {
        return currentStudy != nil
    }
    
    func loadDefaultStudy() -> Promise<Bool> {
        currentStudy = nil
        gpsManager = nil
        return firstly { () -> Promise<[Study]> in
            Recline.shared.queryAll()
        }.then { (studies: [Study]) -> Promise<Bool> in
            if studies.count > 1 {
                log.error("Multiple Studies: \(studies)")
                // Crashlytics.sharedInstance().recordError(NSError(domain: "com.rf.beiwe.studies", code: 1, userInfo: nil))
            }
            if studies.count > 0 {
                self.currentStudy = studies[0]
                AppDelegate.sharedInstance().setDebuggingUser(self.currentStudy?.patientId ?? "unknown")
                StudyManager.real_study_loaded = true
            }
            return .value(true)
        }
    }

    func setApiCredentials() {
        guard let currentStudy = currentStudy, gpsManager == nil else {
            return;
        }
        var pkey: SecKey?;
        /* Setup APIManager's security */
        ApiManager.sharedInstance.password = PersistentPasswordManager.sharedInstance.passwordForStudy() ?? "";
        ApiManager.sharedInstance.customApiUrl = currentStudy.customApiUrl;
        if let patientId = currentStudy.patientId {
            ApiManager.sharedInstance.patientId = patientId;
            if let clientPublicKey = currentStudy.studySettings?.clientPublicKey {
                do {
                    let pkey = try PersistentPasswordManager.sharedInstance.storePublicKeyForStudy(clientPublicKey, patientId: patientId);
                    keyRef = pkey
                } catch {
                    log.error("Failed to store RSA key in keychain.");
                }
            } else {
                log.error("No public key found.  Can't store");
            }
        }
    }
    
    func startStudyDataServices() {
        if gpsManager != nil {
            return;
        }
        setApiCredentials()
        DataStorageManager.sharedInstance.setCurrentStudy(self.currentStudy!, secKeyRef: keyRef);
        self.prepareDataServices();
        NotificationCenter.default.addObserver(self, selector: #selector(self.reachabilityChanged), name: ReachabilityChangedNotification, object: nil)
    }

    func prepareDataServices() {
        guard let studySettings = currentStudy?.studySettings else {
            return;
        }

        log.info("prepareDataServices")

        DataStorageManager.sharedInstance.createDirectories();
        /* Move non current files out.  Probably not necessary, would happen later anyway */
        DataStorageManager.sharedInstance.prepareForUpload();
        gpsManager = GPSManager();
        
        // Check if gps fuzzing is enabled for currentStudy
        gpsManager?.enableGpsFuzzing = studySettings.fuzzGps ? true : false
        gpsManager?.fuzzGpsLatitudeOffset = (currentStudy?.fuzzGpsLatitudeOffset)!
        gpsManager?.fuzzGpsLongitudeOffset = (currentStudy?.fuzzGpsLongitudeOffset)!
        
        gpsManager!.addDataService(AppEventManager.sharedInstance)
        if (studySettings.gps && studySettings.gpsOnDurationSeconds > 0) {
            gpsManager!.addDataService(studySettings.gpsOnDurationSeconds, off: studySettings.gpsOffDurationSeconds, handler: gpsManager!)
        }
        if (studySettings.accelerometer && studySettings.gpsOnDurationSeconds > 0) {
            gpsManager!.addDataService(studySettings.accelerometerOnDurationSeconds, off: studySettings.accelerometerOffDurationSeconds, handler: AccelerometerManager());
        }
        if (studySettings.powerState) {
            gpsManager!.addDataService(PowerStateManager());
        }
        if (studySettings.proximity) {
            gpsManager!.addDataService(ProximityManager());
        }
        if (studySettings.reachability) {
            gpsManager!.addDataService(ReachabilityManager());
        }
        if (studySettings.gyro) {
            gpsManager!.addDataService(studySettings.gyroOnDurationSeconds, off: studySettings.gyroOffDurationSeconds, handler: GyroManager());
        }
        if (studySettings.magnetometer && studySettings.magnetometerOnDurationSeconds > 0) {
            gpsManager!.addDataService(studySettings.magnetometerOnDurationSeconds, off: studySettings.magnetometerOffDurationSeconds, handler: MagnetometerManager());
        }
        if (studySettings.motion && studySettings.motionOnDurationSeconds > 0) {
            gpsManager!.addDataService(studySettings.motionOnDurationSeconds, off: studySettings.motionOffDurationSeconds, handler: DeviceMotionManager());
        }
        gpsManager!.startGpsAndTimer();
    }

    func setConsented() -> Promise<Bool> {
        guard let study = currentStudy, let studySettings = study.studySettings else {
            return .value(false)
        }
        setApiCredentials()
        let currentTime: Int64 = Int64(Date().timeIntervalSince1970);
        study.nextUploadCheck = currentTime + Int64(studySettings.uploadDataFileFrequencySeconds);
        study.nextSurveyCheck = currentTime + Int64(studySettings.checkForNewSurveysFreqSeconds);

        study.participantConsented = true;
        DataStorageManager.sharedInstance.setCurrentStudy(study, secKeyRef: keyRef)
        DataStorageManager.sharedInstance.createDirectories();
        return Recline.shared.save(study).then { _ -> Promise<Bool> in
            return self.checkSurveys();
        }
    }

    func purgeStudies() -> Promise<Bool> {
        return firstly { () -> Promise<[Study]> in
            return Recline.shared.queryAll()
            }.then { (studies: [Study]) -> Promise<Bool> in
                var promise = Promise<Bool>.value(true)
                for study in studies {
                    promise = promise.then { _ in
                        return Recline.shared.purge(study)
                    }
                }
                return promise
        }
    }

    func stop() -> Promise<Bool> {
        var promise: Promise<Void>
        if (gpsManager != nil) {
            promise = gpsManager!.stopAndClear()
        } else {
            promise = Promise();
        }
        
        return promise.then(on: DispatchQueue.global(qos: .default)) { _ -> Promise<Bool> in
            //self.gpsManager = nil;
            self.currentStudy = nil;
            StudyManager.real_study_loaded = false
            return .value(true)
        }
        // catch is not needed since we are just assigning
//        .catch(on: DispatchQueue.global(qos: .default)) {_ in
//                print("Caught err")
//        }

    }

    func leaveStudy() -> Promise<Bool> {

        /*
        guard let study = currentStudy else {
            return Promise(true);
        }
        */

        NotificationCenter.default.removeObserver(self, name: ReachabilityChangedNotification, object:nil);

        var promise: Promise<Void>
        if (gpsManager != nil) {
            promise = gpsManager!.stopAndClear()
        } else {
            promise = Promise();
        }


        UIApplication.shared.cancelAllLocalNotifications()
        return promise.then { _ -> Promise<Bool> in
            self.gpsManager = nil;
                return self.purgeStudies().then { _ -> Promise<Bool> in
                let fileManager = FileManager.default
                var enumerator = fileManager.enumerator(atPath: DataStorageManager.uploadDataDirectory().path);

                if let enumerator = enumerator {
                    while let filename = enumerator.nextObject() as? String {
                        if (true /*filename.hasSuffix(DataStorageManager.dataFileSuffix)*/) {
                            let filePath = DataStorageManager.uploadDataDirectory().appendingPathComponent(filename);
                            try fileManager.removeItem(at: filePath);
                        }
                    }
                }

                enumerator = fileManager.enumerator(atPath: DataStorageManager.currentDataDirectory().path);

                if let enumerator = enumerator {
                    while let filename = enumerator.nextObject() as? String {
                        if (true /* filename.hasSuffix(DataStorageManager.dataFileSuffix) */) {
                            let filePath = DataStorageManager.currentDataDirectory().appendingPathComponent(filename);
                            try fileManager.removeItem(at: filePath);
                        }
                    }
                }
                
                self.currentStudy = nil;
                ApiManager.sharedInstance.patientId = "";
                let instance = InstanceID.instanceID()
                instance.deleteID { (error) in
                    print(error.debugDescription)
                    log.error(error.debugDescription)
                }
                
                return .value(true)
                
            }
        }

    }

    @objc func reachabilityChanged(_ notification: Notification){
        Promise().done() { _ in
            log.info("Reachability changed, running periodic.");
            self.periodicNetworkTransfers();
        }
    }

    func periodicNetworkTransfers() {
        guard let currentStudy = currentStudy, let studySettings = currentStudy.studySettings else {
            return;
        }

        let reachable = studySettings.uploadOverCellular ? self.appDelegate.reachability!.isReachable : self.appDelegate.reachability!.isReachableViaWiFi

        // Good time to compact the database
        let currentTime: Int64 = Int64(Date().timeIntervalSince1970);
        let nextSurvey = currentStudy.nextSurveyCheck ?? 0;
        let nextUpload = currentStudy.nextUploadCheck ?? 0;
        if (currentTime > nextSurvey || (reachable && currentStudy.missedSurveyCheck)) {
            /* This will be saved because setNextUpload saves the study */
            currentStudy.missedSurveyCheck = !reachable
            self.setNextSurveyTime().done { _ -> Void in
                if (reachable) {
                    self.checkSurveys();
                }
                }.catch { _ -> Void in
                    log.error("Error checking for surveys");
            }
        }
        else if (currentTime > nextUpload || (reachable && currentStudy.missedUploadCheck)) {
            /* This will be saved because setNextUpload saves the study */
            currentStudy.missedUploadCheck = !reachable
            self.setNextUploadTime().done { _ -> Void in
                self.upload(!reachable);
                }.catch { _ -> Void in
                    log.error("Error checking for uploads")
            }
        }


    }

    func cleanupSurvey(_ activeSurvey: ActiveSurvey) {
//        removeNotificationForSurvey(activeSurvey);
        if let surveyId = activeSurvey.survey?.surveyId {
            let timingsName = TrackingSurveyPresenter.timingDataType + "_" + surveyId;
            DataStorageManager.sharedInstance.closeStore(timingsName);
        }
    }

    func submitSurvey(_ activeSurvey: ActiveSurvey, surveyPresenter: TrackingSurveyPresenter? = nil) {
        if let survey = activeSurvey.survey, let surveyId = survey.surveyId, let surveyType = survey.surveyType, surveyType == .TrackingSurvey {
            var trackingSurvey: TrackingSurveyPresenter;
            if (surveyPresenter == nil) {
                trackingSurvey = TrackingSurveyPresenter(surveyId: surveyId, activeSurvey: activeSurvey, survey: survey)
                trackingSurvey.addTimingsEvent("expired", question: nil)
            } else {
                trackingSurvey = surveyPresenter!;
            }
            trackingSurvey.finalizeSurveyAnswers();
            
            // increment number of submitted surveys
            if (activeSurvey.bwAnswers.count > 0) {
                if let surveyType = survey.surveyType {
                    switch (surveyType) {
                    case .AudioSurvey:
                        currentStudy?.submittedAudioSurveys = (currentStudy?.submittedAudioSurveys ?? 0) + 1;
                    case .TrackingSurvey:
                        currentStudy?.submittedTrackingSurveys = (currentStudy?.submittedTrackingSurveys ?? 0) + 1;

                    }
                }
            }
        }

        cleanupSurvey(activeSurvey);
    }

    func updateActiveSurveys(_ forceSave: Bool = false) -> TimeInterval {
        log.info("Updating active surveys...")
        let currentDate = Date();
        let currentTime = currentDate.timeIntervalSince1970;
        let currentDay = (calendar as NSCalendar).component(.weekday, from: currentDate) - 1;
        var nowDateComponents = (calendar as NSCalendar).components([NSCalendar.Unit.day, NSCalendar.Unit.year, NSCalendar.Unit.month, NSCalendar.Unit.timeZone], from: currentDate);
        nowDateComponents.hour = 0;
        nowDateComponents.minute = 0;
        nowDateComponents.second = 0;

        var closestNextSurveyTime: TimeInterval = currentTime + (60.0*60.0*24.0*7);

        guard let study = currentStudy, let dayBegin = calendar.date(from: nowDateComponents)  else {
            return Date().addingTimeInterval((15.0*60.0)).timeIntervalSince1970;
        }


        var surveyDataModified = false;

        /* For all active surveys that aren't complete, but have expired, submit them */
        for (id, activeSurvey) in study.activeSurveys {
            // THIS is basically the same thing as the else if statement below, EXCEPT we are resetting the survey.
            // this is so that we reset the state for a permananent survey. If we do not have this,
            // the survey stays at the "done" stage after you have completed the survey and does not allow
            // you to go back and retake a survey.  also, every time you load the survey to the done page,
            // it resaves a new version of the data in a file.
            if(activeSurvey.survey?.alwaysAvailable ?? false && activeSurvey.isComplete){
                log.info("ActiveSurvey \(id) expired.");
//                activeSurvey.isComplete = true;
                surveyDataModified = true;
                //  adding submitSurvey creates a new file; therefore we get 2 files of data- one when you
                //  hit the confirm button and one when this code executes. we DO NOT KNOW why this is in the else if statement
                //  below - however we are not keeping it in this if statement for the aforementioned problem.
                // submitSurvey(activeSurvey)
                activeSurvey.reset(activeSurvey.survey)
            }
            // TODO: we need to determine the correct exclusion logic, currently this submits ALL permanent surveys when ANY permanent survey loads.
            // This function gets called whenever you try to display the home page, thus it happens at a very odd time.
            // If the survey has not been completed, but it is time for the next survey
            else if (!activeSurvey.isComplete /*&& activeSurvey.nextScheduledTime > 0 && activeSurvey.nextScheduledTime <= currentTime*/) {
                log.info("ActiveSurvey \(id) expired.");
//                activeSurvey.isComplete = true;
                surveyDataModified = true;
                submitSurvey(activeSurvey);
            }
        }

        var allSurveyIds: [String] = [ ];
        /* Now for each survey from the server, check on the scheduling */
        for survey in study.surveys {
            if let id = survey.surveyId  {
                allSurveyIds.append(id);
                /* If we don't know about this survey already, add it in there for TRIGGERONFIRSTDOWNLOAD surverys*/
                if study.activeSurveys[id] == nil && (survey.triggerOnFirstDownload /* || next > 0 */) {
                    log.info("Adding survey  \(id) to active surveys");
                    let newActiveSurvey = ActiveSurvey(survey: survey)
                    study.activeSurveys[id] = newActiveSurvey
                    surveyDataModified = true;
                }
                /* We want to display permanent surveys as active, and expect to change some details below (currently identical to the actions we take on a regular active survey) */
                else if study.activeSurveys[id] == nil && (survey.alwaysAvailable) {
                    log.info("Adding survey  \(id) to active surveys");
                    let newActiveSurvey = ActiveSurvey(survey: survey)
                    study.activeSurveys[id] = newActiveSurvey
                    surveyDataModified = true;
                }
            }
        }


        /* Set the badge, and remove surveys no longer on server from our active surveys list */
        var badgeCnt = 0;
        for (id, activeSurvey) in study.activeSurveys {
            if (activeSurvey.isComplete && !allSurveyIds.contains(id)) {
                cleanupSurvey(activeSurvey);
                study.activeSurveys.removeValue(forKey: id);
                surveyDataModified = true;
            } else if (!activeSurvey.isComplete) {
//                if (activeSurvey.nextScheduledTime > 0) {
//                    closestNextSurveyTime = min(closestNextSurveyTime, activeSurvey.nextScheduledTime);
//                }
                badgeCnt += 1;
            }
        }
        log.info("Badge Cnt: \(badgeCnt)");
        UIApplication.shared.applicationIconBadgeNumber = badgeCnt

        if (surveyDataModified || forceSave ) {
            surveysUpdatedEvent.emit(0)
            Recline.shared.save(study).catch { _ in
                log.error("Failed to save study after processing surveys");
            }
        }
        if let gpsManager = gpsManager  {
            gpsManager.resetNextSurveyUpdate(closestNextSurveyTime);
        }
        return closestNextSurveyTime;
    }

    func checkSurveys() -> Promise<Bool> {
        guard let study = currentStudy, let studySettings = study.studySettings else {
            return .value(false)
        }
        log.info("Checking for surveys...");
        return Recline.shared.save(study).then { _ -> Promise<([Survey], Int)> in
                let surveyRequest = GetSurveysRequest();
                return ApiManager.sharedInstance.arrayPostRequest(surveyRequest);
            }.then { (surveys, _) -> Promise<Void> in
                log.info("Surveys: \(surveys)");
                study.surveys = surveys;
                return Recline.shared.save(study).asVoid();
            }.then { _ -> Promise<Bool> in
                self.updateActiveSurveys();
                return .value(true)
            }.recover { _ -> Promise<Bool> in
                return .value(false);
        }

    }

    func setNextUploadTime() -> Promise<Bool> {
        guard let study = currentStudy, let studySettings = study.studySettings else {
            return .value(true)
        }

        study.nextUploadCheck = Int64(Date().timeIntervalSince1970) +  Int64(studySettings.uploadDataFileFrequencySeconds);
        return Recline.shared.save(study).then { _ -> Promise<Bool> in
            return .value(true)
        }
    }

    func setNextSurveyTime() -> Promise<Bool> {
        guard let study = currentStudy, let studySettings = study.studySettings else {            return .value(true)
        }

        study.nextSurveyCheck = Int64(Date().timeIntervalSince1970) + Int64(studySettings.checkForNewSurveysFreqSeconds)
        return Recline.shared.save(study).then { _ -> Promise<Bool> in
            return .value(true)
        }

    }

    func parseFilename(_ filename: String) -> (type: String, timestamp: Int64, ext: String){
        let url = URL(fileURLWithPath: filename)
        let pathExtention = url.pathExtension
        let pathPrefix = url.deletingPathExtension().lastPathComponent

        var type = ""

        let pieces = pathPrefix.split(separator: "_")
        var timestamp: Int64 = 0
        if (pieces.count > 2) {
            type = String(pieces[1])
            timestamp = Int64(String(pieces[pieces.count-1])) ?? 0
        }


        return (type: type, timestamp: timestamp, ext: pathExtention ?? "")
    }

    func purgeUploadData(_ fileList: [String:Int64], currentStorageUse: Int64) -> Promise<Void> {
        var used = currentStorageUse
        return Promise().then(on: DispatchQueue.global(qos: .default)) { _ -> Promise<Void> in
            log.error("EXCESSIVE STORAGE USED, used: \(currentStorageUse), WifiAvailable: \(self.appDelegate.reachability!.isReachableViaWiFi)")
            log.error("Last success: \(self.currentStudy?.lastUploadSuccess)")
            for (filename, len) in fileList {
                log.error("file: \(filename), size: \(len)")
            }
            let keys = fileList.keys.sorted() { (a, b) in
                let fileA = self.parseFilename(a)
                let fileB = self.parseFilename(b)
                return fileA.timestamp < fileB.timestamp
            }

            for file in keys {
                let attrs = self.parseFilename(file)
                if (attrs.ext != "csv" || attrs.type.hasPrefix("survey")) {
                    log.info("Skipping deletion: \(file)")
                    continue
                }
                let filePath = DataStorageManager.uploadDataDirectory().appendingPathComponent(file);
                do {
                    log.warning("Removing file: \(filePath)")
                    try FileManager.default.removeItem(at: filePath);
                    used = used - fileList[file]!
                } catch {
                    log.error("Error removing file: \(filePath)")
                }

                if (used < self.MAX_UPLOAD_DATA) {
                    break
                }

            }

            //Crashlytics.sharedInstance().recordError(NSError(domain: "com.rf.beiwe.studies.excessive", code: 2, userInfo: nil))

            return Promise()
        }
    }

    func clearTempFiles() -> Promise<Void> {
        return Promise().then(on: DispatchQueue.global(qos: .default)) { _ -> Promise<Void> in
            do {
                let alamoTmpDir = NSURL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("com.alamofire.manager")!.appendingPathComponent("multipart.form.data")
                try FileManager.default.removeItem(at: alamoTmpDir)
            } catch {
                //log.error("Error removing tmp files: \(error)")
            }
            return Promise()
        }
    }

    func upload(_ processOnly: Bool) -> Promise<Void> {
        if (isUploading) {
            return Promise();
        }
        log.info("Checking for uploads...");
        isUploading = true;

        var promiseChain: Promise<Bool>

        promiseChain = Recline.shared.compact().then { _ -> Promise<Bool> in
            return DataStorageManager.sharedInstance.prepareForUpload().then { _ -> Promise<Bool> in
                log.info("prepareForUpload finished")
                return .value(true)
            };
        }

        var numFiles = 0;
        var size: Int64 = 0
        var storageInUse: Int64 = 0
        let q = DispatchQueue.global(qos: .default)

        var filesToProcess: [String: Int64] = [:];
        return promiseChain.then(on: q) { (_: Bool) -> Promise<Bool> in
            let fileManager = FileManager.default
            let enumerator = fileManager.enumerator(atPath: DataStorageManager.uploadDataDirectory().path)
//            var uploadChain = Promise<Bool>(value: true)
            var uploadChain = Promise<Bool>.value(true)
            if let enumerator = enumerator {
                while let filename = enumerator.nextObject() as? String {
                    if (DataStorageManager.sharedInstance.isUploadFile(filename)) {
                        let filePath = DataStorageManager.uploadDataDirectory().appendingPathComponent(filename);
                        let attr = try FileManager.default.attributesOfItem(atPath: filePath.path)
                        let fileSize = (attr[FileAttributeKey.size]! as AnyObject).longLongValue
                        filesToProcess[filename] = fileSize
                        size = size + fileSize!
                        //promises.append(promise);
                    }
                }
            }
            storageInUse = size
            if (!processOnly) {
                for (filename, len) in filesToProcess {
                    let filePath = DataStorageManager.uploadDataDirectory().appendingPathComponent(filename);
                    let uploadRequest = UploadRequest(fileName: filename, filePath: filePath.path);
                    uploadChain = uploadChain.then {_ -> Promise<Bool> in
                        log.info("Uploading: \(filename)")
                        return ApiManager.sharedInstance.makeMultipartUploadRequest(uploadRequest, file: filePath).then { _ -> Promise<Bool> in
                            log.info("Finished uploading: \(filename), removing.");
                            AppEventManager.sharedInstance.logAppEvent(event: "uploaded", msg: "Uploaded data file", d1: filename)
                            numFiles = numFiles + 1
                            try fileManager.removeItem(at: filePath);
                            storageInUse = storageInUse - len
                            filesToProcess.removeValue(forKey: filename)
                            return .value(true)
                        }
                    }.recover { error -> Promise<Bool> in
                        AppEventManager.sharedInstance.logAppEvent(event: "upload_file_failed", msg: "Failed Uploaded data file", d1: filename)
                        return .value(true)
                    }
                }
                return uploadChain
            } else {
                log.info("Skipping upload, processing only")
                return .value(true)
            }
        }.then { (results: Bool) -> Promise<Void> in
            log.info("OK uploading \(numFiles). \(results)");
            log.info("Total Size of uploads: \(size)")
            AppEventManager.sharedInstance.logAppEvent(event: "upload_complete", msg: "Upload Complete", d1: String(numFiles))
            if let study = self.currentStudy {
                study.lastUploadSuccess = Int64(NSDate().timeIntervalSince1970)
                return Recline.shared.save(study).asVoid()
            } else {
                return Promise()
            }
        }.recover { error -> Void in
            log.info("Recover")
            AppEventManager.sharedInstance.logAppEvent(event: "upload_incomplete", msg: "Upload Incomplete", d1: String(storageInUse))
        }.then { () -> Promise<Void> in
            log.info("Size left after upload: \(storageInUse)")
            if (storageInUse > self.MAX_UPLOAD_DATA) {
                AppEventManager.sharedInstance.logAppEvent(event: "purge", msg: "Purging too large data files", d1: String(storageInUse))
                return self.purgeUploadData(filesToProcess, currentStorageUse: storageInUse)
            }
            else {
                return Promise()
            }
        }.then {
            return self.clearTempFiles()
        }.always {
            self.isUploading = false
            log.info("Always")
        }
    }
}
