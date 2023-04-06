import Crashlytics
import EmitterKit
import Firebase
import Foundation
import PromiseKit
import ReachabilitySwift


/// Contains all sorts of miiscellaneous study related functionality - this is badly factored and should be defactored into classes that contain their own well-defirned things
class StudyManager {
    static let sharedInstance = StudyManager()  // singleton reference
    
    // General code assets
    let appDelegate = UIApplication.shared.delegate as! AppDelegate
    let calendar = Calendar.current
    
    // Really critical app components
    var currentStudy: Study?
    var timerManager: TimerManager = TimerManager()
    var gpsManager: GPSManager?  // gps manager is slightly special because we use it to keep the app open in the background
    var keyRef: SecKey?  // the study's security key
    
    // State tracking variables
    var isUploading = false
    let surveysUpdatedEvent: Event<Int> = Event<Int>()
    static var real_study_loaded = false
    
    var isStudyLoaded: Bool {  // returns true if self.currentStudy is populated
        return self.currentStudy != nil
    }
    
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////// Setup and UnSetup ///////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    /// sets (but also clears?) the current study, and the gpsManager, sets real_study_loaded to true
    func loadDefaultStudy() -> Promise<Bool> {
        self.currentStudy = nil
        self.gpsManager = nil
        
        // mostly sets real_study_loaded to true...
        return firstly { () -> Promise<[Study]> in
            Recline.shared.queryAll()  // this returns a list of all studies as a parameter to the next promise.
        }.then { (studies: [Study]) -> Promise<Bool> in
            // if there is more than one study, log a warning? this is pointless
            if studies.count > 1 {
                log.warning("Multiple Studies: \(studies)")
            }
            // grab the first study and the first study only, set the patient id (but not), real_study_loaded to true
            if studies.count > 0 {
                self.currentStudy = studies[0]
                print("self.currentStudy.patientId: \(self.currentStudy?.patientId)")
                AppDelegate.sharedInstance().setDebuggingUser(self.currentStudy?.patientId ?? "unknown")  // this doesn't do anything...
                StudyManager.real_study_loaded = true
            }
            return .value(true)
        }
    }
    
    /// pretty much an initializer for data services, for some reason gpsManager is the test if we are already initialized
    func startStudyDataServices() {
        // if there is no study return immediately (this should probably throw an error, such an app state is too invalid to support)
        if !self.isStudyLoaded {
            return
        }
        self.setApiCredentials()
        DataStorageManager.sharedInstance.setCurrentStudy(self.currentStudy!, secKeyRef: self.keyRef)
        self.prepareDataServices()  // okay prepareDataServices is 90% of the function body
        NotificationCenter.default.addObserver(self, selector: #selector(self.reachabilityChanged), name: ReachabilityChangedNotification, object: nil)
    }
    
    /// ACTUAL initialization - initializes the weirdly complex self.gpsManager and everything else
    private func prepareDataServices() {
        // current study and study settings are null of course
        guard let studySettings: StudySettings = currentStudy?.studySettings else {
            return
        }
        log.info("prepareDataServices")
        
        DataStorageManager.sharedInstance.createDirectories()
        // Move non current files out.  (Probably unnecessary, would happen later anyway)
        _ = DataStorageManager.sharedInstance.prepareForUpload()
        
        // GPS, Check if gps fuzzing is enabled for currentStudy
        self.gpsManager = GPSManager()
        self.gpsManager?.enableGpsFuzzing = studySettings.fuzzGps ? true : false
        self.gpsManager?.fuzzGpsLatitudeOffset = (self.currentStudy?.fuzzGpsLatitudeOffset)!
        self.gpsManager?.fuzzGpsLongitudeOffset = (self.currentStudy?.fuzzGpsLongitudeOffset)!
        
        // iOS Log (app events)
        self.timerManager.addDataService(AppEventManager.sharedInstance)
        
        // every sensor, which for unfathomable reasons are contained inside the gps manager, activate them
        if studySettings.gps && studySettings.gpsOnDurationSeconds > 0 {
            self.timerManager.addDataService(on_duration: studySettings.gpsOnDurationSeconds, off_duration: studySettings.gpsOffDurationSeconds, handler: self.gpsManager!)
        }
        if studySettings.accelerometer && studySettings.gpsOnDurationSeconds > 0 {
            self.timerManager.addDataService(on_duration: studySettings.accelerometerOnDurationSeconds, off_duration: studySettings.accelerometerOffDurationSeconds, handler: AccelerometerManager())
        }
        if studySettings.powerState {
            self.timerManager.addDataService(PowerStateManager())
        }
        if studySettings.proximity {
            self.timerManager.addDataService(ProximityManager())
        }
        if studySettings.reachability {
            self.timerManager.addDataService(ReachabilityManager())
        }
        if studySettings.gyro {
            self.timerManager.addDataService(on_duration: studySettings.gyroOnDurationSeconds, off_duration: studySettings.gyroOffDurationSeconds, handler: GyroManager())
        }
        if studySettings.magnetometer && studySettings.magnetometerOnDurationSeconds > 0 {
            self.timerManager.addDataService(on_duration: studySettings.magnetometerOnDurationSeconds, off_duration: studySettings.magnetometerOffDurationSeconds, handler: MagnetometerManager())
        }
        if studySettings.motion && studySettings.motionOnDurationSeconds > 0 {
            self.timerManager.addDataService(on_duration: studySettings.motionOnDurationSeconds, off_duration: studySettings.motionOffDurationSeconds, handler: DeviceMotionManager())
        }
        self.gpsManager!.startGps()
        timerManager.start()
    }
    
    /// sets the study as consented, sets api credentials
    func setConsented() -> Promise<Bool> {
        // fail if current study or study settings are null
        guard let study = currentStudy, let studySettings = study.studySettings else {
            return .value(false)
        }
        // api setup
        self.setApiCredentials()
        let currentTime: Int64 = Int64(Date().timeIntervalSince1970)
        // kick off survey timers
        study.nextUploadCheck = currentTime + Int64(studySettings.uploadDataFileFrequencySeconds)
        study.nextSurveyCheck = currentTime + Int64(studySettings.checkForNewSurveysFreqSeconds)
        // set consented to true (checked over in AppDelegate)
        study.participantConsented = true
        // some io stuff
        DataStorageManager.sharedInstance.setCurrentStudy(study, secKeyRef: self.keyRef)
        DataStorageManager.sharedInstance.createDirectories()
        // update study stuff?
        return Recline.shared.save(study).then { (_: Study) -> Promise<Bool> in
            self.checkSurveys()
        }
    }
    
    // FIXME: This function has 4 unacceptable failure modes -- called only from setConsented (study registration) and startStudyDataServices
    /// Sets up the password (api) credential for backend calls
    func setApiCredentials() {
        // if there is no study.... don't do this.
        guard let currentStudy: Study = self.currentStudy else {
            return
        }
        // Setup APIManager's security
        // Why is this EVER allowed to be the empty string? that's silent failure FOREVER
        ApiManager.sharedInstance.password = PersistentPasswordManager.sharedInstance.passwordForStudy() ?? ""
        ApiManager.sharedInstance.customApiUrl = currentStudy.customApiUrl
        if let patientId = currentStudy.patientId {  // again WHY is this even allowed to happen on a null participant id
            ApiManager.sharedInstance.patientId = patientId
            if let clientPublicKey = currentStudy.studySettings?.clientPublicKey {
                do {
                    // failure means a null key
                    self.keyRef = try PersistentPasswordManager.sharedInstance.storePublicKeyForStudy(clientPublicKey, patientId: patientId)
                } catch {
                    log.error("Failed to store RSA key in keychain.")  // why are we not crashing...
                }
            } else {
                log.error("No public key found.  Can't store")  // why are we not crashing...
            }
        }
    }
    
    /// takes a(n active) survey and creates the suvey answers file
    func submitSurvey(_ activeSurvey: ActiveSurvey, surveyPresenter: TrackingSurveyPresenter? = nil) {
        // only run if this stuff exists and it is a TrackingSurvey, but then later there is checking of the survey type so maybe not.
        if let survey = activeSurvey.survey, let surveyId = survey.surveyId, let surveyType = survey.surveyType, surveyType == .TrackingSurvey {
            // get the survey data and write it out
            var trackingSurvey: TrackingSurveyPresenter
            if surveyPresenter == nil {
                // expiration logic? what is "expired?"
                trackingSurvey = TrackingSurveyPresenter(surveyId: surveyId, activeSurvey: activeSurvey, survey: survey)
                trackingSurvey.addTimingsEvent("expired", question: nil)
            } else {
                trackingSurvey = surveyPresenter!  // current survey I think?
            }
            trackingSurvey.finalizeSurveyAnswers()  // its done, do the its-done thing
            
            // increment number of submitted surveys
            if activeSurvey.bwAnswers.count > 0 {
                if let surveyType = survey.surveyType {  // ... isn't this already instantiated?
                    switch surveyType {
                    case .AudioSurvey:
                        self.currentStudy?.submittedAudioSurveys = (self.currentStudy?.submittedAudioSurveys ?? 0) + 1
                    case .TrackingSurvey:
                        self.currentStudy?.submittedTrackingSurveys = (self.currentStudy?.submittedTrackingSurveys ?? 0) + 1
                    }
                }
            }
        }
        self.cleanupSurvey(activeSurvey)  // call cleanup
    }
    
    /// miniscule portion of finishing a survey answefrs file creation, finalizes file sorta; also called in audio surveys
    func cleanupSurvey(_ activeSurvey: ActiveSurvey) {
        // removeNotificationForSurvey(activeSurvey)  // I don't know why we don't call this, but we don't.
        if let surveyId = activeSurvey.survey?.surveyId {
            let timingsName = TrackingSurveyPresenter.timingDataType + "_" + surveyId
            _ = DataStorageManager.sharedInstance.closeStore(timingsName)
        }
    }
    
    ///
    /// Survey checking logic
    ///
    
    /// updates the list of surveys in the app ui based on the study timers,
    /// updates the badge count, submits completed surveys, and updates the relevant survey timer.
    /// (this is a mess, it should be broken down some, but it does all that needs to happen at this time)
    /// Called from GpsManager.pollServices, AudioQuestionsViewController.saveButtonPressed, StudyManager.checkSurveys,
    ///  and inside TrackingSurveyPresenter when the survey is completed.
    func updateActiveSurveys(_ forceSave: Bool = false) -> TimeInterval {
        log.info("Updating active surveys...")
        let currentDate = Date()
        let currentTime = currentDate.timeIntervalSince1970
        let currentDay = (calendar as NSCalendar).component(.weekday, from: currentDate) - 1
        var nowDateComponents: DateComponents = (calendar as NSCalendar).components(
            [NSCalendar.Unit.day, NSCalendar.Unit.year, NSCalendar.Unit.month, NSCalendar.Unit.timeZone], from: currentDate
        )
        nowDateComponents.hour = 0
        nowDateComponents.minute = 0
        nowDateComponents.second = 0
        // if for some reason we don't have a current study, returne 15 minutes (presumably this tells something to wait 15 minutes)
        guard let study = currentStudy else {
            return Date().addingTimeInterval(15.0 * 60.0).timeIntervalSince1970
        }
        
        // For all active surveys that aren't complete, but have expired, submit them
        var surveyDataModified = false
        for (id, activeSurvey) in study.activeSurveys {
            // almost the same as the else-if statement below, except we are resetting the survey, so that we reset the state for a permananent
            // survey. If we don't the survey stays in the "done" stage after it is completed and you can't retake it.  It loads the survey to
            // the done page, which will resave a new version of the data in a file.
            if activeSurvey.survey?.alwaysAvailable ?? false && activeSurvey.isComplete {
                log.info("ActiveSurvey \(id) expired.")
                // activeSurvey.isComplete = true
                surveyDataModified = true
                //  adding submitSurvey creates a new file; therefore we get 2 files of data- one when you
                //  hit the confirm button and one when this code executes. we DO NOT KNOW why this is in the else if statement
                //  below - however we are not keeping it in this if statement for the aforementioned problem.
                // submitSurvey(activeSurvey)
                activeSurvey.reset(activeSurvey.survey)
            }
            // TODO: we need to determine the correct exclusion logic, currently this submits ALL permanent surveys when ANY permanent survey loads.
            // This function gets called whenever you try to display the home page, which is a very odd time.
            // If the survey has not been completed, but it is time for the next survey
            else if !activeSurvey.isComplete /* && activeSurvey.nextScheduledTime > 0 && activeSurvey.nextScheduledTime <= currentTime */ {
                log.info("ActiveSurvey \(id) expired.")
                // activeSurvey.isComplete = true;
                surveyDataModified = true
                self.submitSurvey(activeSurvey)
            }
        }
        
        // for each survey from the server, check on the scheduling
        var allSurveyIds: [String] = []
        for survey in study.surveys {
            if let id = survey.surveyId {
                allSurveyIds.append(id)
                // If we don't know about this survey already, add it in there for TRIGGERONFIRSTDOWNLOAD surverys
                if study.activeSurveys[id] == nil && (survey.triggerOnFirstDownload /* || next > 0 */ ) {
                    log.info("Adding survey  \(id) to active surveys")
                    let newActiveSurvey = ActiveSurvey(survey: survey)
                    study.activeSurveys[id] = newActiveSurvey
                    surveyDataModified = true
                }
                // We want to display permanent surveys as active, and expect to change some details below (currently
                // identical to the actions we take on a regular active survey) */
                else if study.activeSurveys[id] == nil && (survey.alwaysAvailable) {
                    log.info("Adding survey  \(id) to active surveys")
                    let newActiveSurvey = ActiveSurvey(survey: survey)
                    study.activeSurveys[id] = newActiveSurvey
                    surveyDataModified = true
                }
            }
        }
        
        /* Set the badge, and remove surveys no longer on server from our active surveys list */
        var badgeCnt = 0
        for (id, activeSurvey) in study.activeSurveys {
            if activeSurvey.isComplete && !allSurveyIds.contains(id) {
                self.cleanupSurvey(activeSurvey)
                study.activeSurveys.removeValue(forKey: id)
                surveyDataModified = true
            } else if !activeSurvey.isComplete {
                // if (activeSurvey.nextScheduledTime > 0) {
                //     closestNextSurveyTime = min(closestNextSurveyTime, activeSurvey.nextScheduledTime);
                // }
                badgeCnt += 1
            }
        }
        log.info("Badge Count: \(badgeCnt)")
        UIApplication.shared.applicationIconBadgeNumber = badgeCnt
        
        // save surveyy data
        if surveyDataModified || forceSave {
            self.surveysUpdatedEvent.emit(0)
            Recline.shared.save(study).catch { _ in
                log.error("Failed to save study after processing surveys")
            }
        }
        
        // calculate the next survey time for use and return it
        let closestNextSurveyTime: TimeInterval = currentTime + (60.0 * 60.0 * 24.0 * 7)
        timerManager.resetNextSurveyUpdate(closestNextSurveyTime)
        return closestNextSurveyTime
    }
    
    ///
    /// Timers! They do what they say and aren't even complicated! Holy !#*&$@#*!
    ///
    
    func setNextUploadTime() -> Promise<Bool> {
        guard let study = currentStudy, let studySettings = study.studySettings else {
            return .value(true)
        }
        study.nextUploadCheck = Int64(Date().timeIntervalSince1970) + Int64(studySettings.uploadDataFileFrequencySeconds)
        return Recline.shared.save(study).then { (_: Study) -> Promise<Bool> in
                .value(true)
        }
    }
    
    func setNextSurveyTime() -> Promise<Bool> {
        guard let study = currentStudy, let studySettings = study.studySettings else {
            return .value(true)
        }
        study.nextSurveyCheck = Int64(Date().timeIntervalSince1970) + Int64(studySettings.checkForNewSurveysFreqSeconds)
        return Recline.shared.save(study).then { (_: Study) -> Promise<Bool> in
                .value(true)
        }
    }
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////// Network Operations ////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    /// some kind of reachability thing, calls periodicNetworkTransfers in a promise (of course it does)
    @objc func reachabilityChanged(_ notification: Notification) {
        _ = Promise().done { _ in
            log.info("Reachability changed, running periodic.")
            self.periodicNetworkTransfers()
        }
    }
    
    /// called from self.setConsented, periodicNetworkTasks, and a debug menu button (I think)
    /// THE RETURN VALUE IS NOT USED BECAUSE OF COURSE NOT
    func checkSurveys() -> Promise<Bool> {
        // return early if there is no study or no study settings (retaining studysettings check for safety)
        guard let study = currentStudy, let _ = study.studySettings else {
            return .value(false)
        }
        log.info("Checking for surveys...")
        
        // save the study (whatever that means), and then....
        return Recline.shared.save(study).then { (_: Study) -> Promise<([Survey], Int)> in
            // do the survey request (its json into a ~mappable)
            let surveyRequest = GetSurveysRequest()
            return ApiManager.sharedInstance.arrayPostRequest(surveyRequest)
        }.then { surveys, _ -> Promise<Void> in
            // then... we receive the surveys from the api manager request possibly?
            // (This is another reason why promises are bad, they pointless obscure critical information)
            log.info("Surveys: \(surveys)")
            study.surveys = surveys
            return Recline.shared.save(study).asVoid()
        }.then { _ -> Promise<Bool> in  // its an error type
            // then update the active surveys because the surveys may have just changed
            _ = self.updateActiveSurveys()
            return .value(true)
        }.recover { _ -> Promise<Bool> in  // _ is of some error type
            // and if anything went wron return false  --  IT IS NEVER USED
                .value(false)
        }
    }
    
    /// runs network operations inside of promises
    func periodicNetworkTransfers() {
        // fail early logic.
        guard let currentStudy = currentStudy, let studySettings = currentStudy.studySettings else {
            return
        }
        // check the uploadOverCellular study detail.
        let reachable = studySettings.uploadOverCellular ? self.appDelegate.reachability!.isReachable : self.appDelegate.reachability!.isReachableViaWiFi
        // Good time to compact the database
        let currentTime: Int64 = Int64(Date().timeIntervalSince1970)
        let nextSurvey = currentStudy.nextSurveyCheck ?? 0
        let nextUpload = currentStudy.nextUploadCheck ?? 0
        
        // logic for checking for studion and runnning the data upload code
        if currentTime > nextSurvey || (reachable && currentStudy.missedSurveyCheck) {
            // This (missedSurveyCheck?) will be saved because setNextUpload saves the study
            currentStudy.missedSurveyCheck = !reachable  // whut?
            self.setNextSurveyTime().done { _ in
                if reachable {
                    _ = self.checkSurveys()
                }
            }.catch { _ in
                log.error("Error checking for surveys")
            }
        } else if currentTime > nextUpload || (reachable && currentStudy.missedUploadCheck) {
            // This (missedUploadCheck?) will be saved because setNextUpload saves the study
            currentStudy.missedUploadCheck = !reachable
            self.setNextUploadTime().done { _ in
                _ = self.upload(!reachable)
            }.catch { _ in
                log.error("Error checking for uploads")  // this is kindof unnecessary
            }
        }
    }
    
    /// business logic of the upload, except it isn't because we use PromiseKit and can't have nice things.
    func upload(_ processOnly: Bool) -> Promise<Void> {
        log.info("Checking for uploads...")
        // return immediately if already uploading
        if self.isUploading {
            return Promise()
        }
        
        // state tracking variables
        self.isUploading = true
        var numFiles = 0
        
        // oh good a promiseChain...
        let promiseChain: Promise<Bool> = Recline.shared.compact().then { (_: Void) -> Promise<Bool> in
            // run prepare for upload
            DataStorageManager.sharedInstance.prepareForUpload().then { (_: Void) -> Promise<Bool> in
                log.info("prepareForUpload finished")
                return .value(true)
            }
        }
        
        // most of the function is after the return statement, duh.
        return promiseChain.then(on: DispatchQueue.global(qos: .default)) { (_: Bool) -> Promise<Bool> in
            // if we can't enumerate files, that's insane, crash.
            let fileEnumerator: FileManager.DirectoryEnumerator = FileManager.default.enumerator(atPath: DataStorageManager.uploadDataDirectory().path)!
            var filesToProcess: [String] = []
            
            // loop over all and check if each file can be uploaded, assemble the list.
            while let filename = fileEnumerator.nextObject() as? String {
                if DataStorageManager.sharedInstance.isUploadFile(filename) {
                    filesToProcess.append(filename)
                }
            }
            
            // we call with processOnly=true when we have no network access
            if !processOnly {
                var uploadChain = Promise<Bool>.value(true)  // iinstantiate the start (end? yeah its the end) of the promise chain
                for filename in filesToProcess {
                    let filePath = DataStorageManager.uploadDataDirectory().appendingPathComponent(filename)
                    let uploadRequest = UploadRequest(fileName: filename, filePath: filePath.path)
                    
                    // add the upload operation to the upload chain
                    uploadChain = uploadChain.then { (_: Bool) -> Promise<Bool> in
                        // do an upload
                        return ApiManager.sharedInstance.makeMultipartUploadRequest(uploadRequest, file: filePath).then { (_: (UploadRequest.ApiReturnType, Int)) -> Promise<Bool> in
                            log.warning("Finished uploading: \(filename), deleting.")
                            AppEventManager.sharedInstance.logAppEvent(event: "uploaded", msg: "Uploaded data file", d1: filename)
                            numFiles = numFiles + 1
                            try FileManager.default.removeItem(at: filePath)  // ok I guess this can fail...?
                            return .value(true)
                        }
                    }.recover { (_: Error) -> Promise<Bool> in
                        // in case of errors...
                        log.warning("upload failed: \(filename)")
                        AppEventManager.sharedInstance.logAppEvent(event: "upload_file_failed", msg: "Failed Uploaded data file", d1: filename)
                        return .value(true)
                    }
                }
                return uploadChain
            } else {
                log.info("Skipping upload, processing only")
                return .value(true)
            }
            // the rest of this is logging and then marking isUploading as false using ensure
        }.then { (results: Bool) -> Promise<Void> in
            // does this happen first? why are we using promises......
            log.verbose("OK uploading \(numFiles). \(results)")
            AppEventManager.sharedInstance.logAppEvent(event: "upload_complete", msg: "Upload Complete", d1: String(numFiles))
            if let study = self.currentStudy {
                study.lastUploadSuccess = Int64(NSDate().timeIntervalSince1970)
                return Recline.shared.save(study).asVoid()
            } else {
                return Promise()
            }
        }.recover { _ in
            log.verbose("Upload Recover")
            AppEventManager.sharedInstance.logAppEvent(event: "upload_incomplete", msg: "Upload Incomplete")
        }.ensure {
            self.isUploading = false
        }
    }
    
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////// The Leave Study Code //////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    /// the bulk of the leave study feature.
    func leaveStudy() -> Promise<Bool> {
        fatalError("this is not supposed to run")
        
        // disable gps - gps is special because it interacts with app persistence
        if self.gpsManager != nil {
            self.gpsManager!.stopGps()
        }
        // stop all timers
        self.timerManager.stop()
        self.timerManager.clear()
        
        // kill notifications
        NotificationCenter.default.removeObserver(self, name: ReachabilityChangedNotification, object: nil)
        UIApplication.shared.cancelAllLocalNotifications()
        
        var promise: Promise<Void> = Promise()
        // and then alllll code is located after return statement because Promises are totally meant to be used like this. hooray!
        return promise.then { (_: Void) -> Promise<Bool> in
            self.gpsManager = nil
            self.timerManager.clear()  // this may deallocate all sensors.  I think.
            
            // call purge studies and insert a _second_ return statement 🙄
            return self.purgeStudies().then { (_: Bool) -> Promise<Bool> in
                // delete upload diirectory using ugly code
                var enumerator = FileManager.default.enumerator(atPath: DataStorageManager.uploadDataDirectory().path)
                if let enumerator = enumerator {
                    while let filename = enumerator.nextObject() as? String {
                        if true /* filename.hasSuffix(DataStorageManager.dataFileSuffix) */ {
                            let filePath = DataStorageManager.uploadDataDirectory().appendingPathComponent(filename)
                            try FileManager.default.removeItem(at: filePath)
                        }
                    }
                }
                // delete data directory using ugly code
                enumerator = FileManager.default.enumerator(atPath: DataStorageManager.currentDataDirectory().path)
                if let enumerator = enumerator {
                    while let filename = enumerator.nextObject() as? String {
                        if true /* filename.hasSuffix(DataStorageManager.dataFileSuffix) */ {
                            let filePath = DataStorageManager.currentDataDirectory().appendingPathComponent(filename)
                            try FileManager.default.removeItem(at: filePath)
                        }
                    }
                }
                // clear the study, patient id
                self.currentStudy = nil  // self.isStudyLoaded will now fail
                ApiManager.sharedInstance.patientId = ""
                
                // I don't know what this is and I don't think it matters.
                let instance = InstanceID.instanceID()
                instance.deleteID { (error: Error?) in
                    print(error.debugDescription)
                    log.error(error.debugDescription)
                }
                return .value(true)  // ohey a third return statement 🙄
            }
        }
    }
    
    /// deletes all studies - ok? - used in registration for some reason
    func purgeStudies() -> Promise<Bool> {
        /// reaches into the database, removes the study, no clue what the queryall does
        return firstly { () -> Promise<[Study]> in
            Recline.shared.queryAll()  // this returns a list of all studies as a parameter to the next promise.
        }.then { (studies: [Study]) -> Promise<Bool> in
            // delete all the studies
            var promise = Promise<Bool>.value(true)
            for study in studies {
                promise = promise.then { (_: Bool) in
                    Recline.shared.purge(study)
                }
            }
            return promise
        }
    }
    
    ///
    /// Miscellaneous utility functions
    ///
    
    /// returns a tuple of the filetype (data stream name?), the timestamp, and the file extension
    func parseFilename(_ filename: String) -> (type: String, timestamp: Int64, ext: String) {
        // I can't tell if this code has extra variables, or if deletingPathExtension mutates the url maybe?
        let url = URL(fileURLWithPath: filename)
        let pathExtention = url.pathExtension
        let pathPrefix = url.deletingPathExtension().lastPathComponent
        let pieces = pathPrefix.split(separator: "_")
        var type = ""
        var timestamp: Int64 = 0
        if pieces.count > 2 {
            type = String(pieces[1])
            timestamp = Int64(String(pieces[pieces.count - 1])) ?? 0
        }
        return (type: type, timestamp: timestamp, ext: pathExtention)
    }
    
    /// only called from AppDelegate.applicationWillTerminate
    func stop() -> Promise<Bool> {
        // stop gps because it interacts with app persistence.
        if self.gpsManager != nil {
            self.gpsManager!.stopGps()
            self.gpsManager = nil
        }
        
        // stop all recording, clear registered
        self.timerManager.stop()
        self.timerManager.clear()
        var promise: Promise<Void> = Promise()
        // clear currentStudy
        return promise.then(on: DispatchQueue.global(qos: .default)) { _ -> Promise<Bool> in
            // self.gpsManager = nil  // I guess this is unnecessary?
            self.currentStudy = nil
            StudyManager.real_study_loaded = false
            return .value(true)
        }
    }
}
