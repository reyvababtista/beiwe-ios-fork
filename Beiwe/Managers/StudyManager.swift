import Crashlytics
import EmitterKit
import Firebase
import Foundation
import ObjectMapper
import PromiseKit
import ReachabilitySwift

let DEVICE_SETTINGS_INTERVAL: Int64 = 30 * 60 // hardcoded thirty minutes
let DEFAULT_INTERVAL: Double = 15.0 * 60.0

/// Contains all sorts of miiscellaneous study related functionality - this is badly factored and should be refactored into classes that contain their own well-defirned things
class StudyManager {
    static let sharedInstance = StudyManager() // singleton reference
    
    // General code assets
    let appDelegate = UIApplication.shared.delegate as! AppDelegate
    let calendar = Calendar.current
    
    // Really critical app components
    var currentStudy: Study?
    var timerManager: TimerManager = TimerManager()
    var gpsManager: GPSManager? // gps manager is slightly special because we use it to keep the app open in the background
    var keyRef: SecKey? // the study's security key
    
    // State tracking variables
    var sensorsStartedEver = false
    var isUploading = false
    let surveysUpdatedEvent: Event<Int> = Event<Int>() // I don't know what this is. sometimes we emit events, like when closing a survey
    static var real_study_loaded = false
    
    var isStudyLoaded: Bool { // returns true if self.currentStudy is populated
        return self.currentStudy != nil
    }
    
    // Common getters
    
    /// getters, mutators all the ids of active surveys - not used (anymore?
    func getActiveSurveyIds() -> [String] {
        guard let study = self.currentStudy else {
            return []
        }
        return Array(study.activeSurveys.keys)
    }
    
    /// iterates over all the surveys IN THE DATABASE, gives you survey ids
    func getAllSurveyIds() -> [String] {
        guard let study = self.currentStudy else {
            return []
        }
        var allSurveyIds: [String] = []
        for survey in study.surveys where survey.surveyId != nil { // this comes from a mappable in RecLine
            allSurveyIds.append(survey.surveyId!)
        }
        return allSurveyIds
    }
    
    /// saves study data....?
    /// FIXME: I need to work out what these emmitters are
    func emit_survey_updates_save_study_data() {
        guard let study = self.currentStudy else {
            return
        }
        self.surveysUpdatedEvent.emit(0) // what is this>?
        Recline.shared.save(study)
    }
    
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////// Setup and UnSetup ///////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    /// sets (but also clears?) the current study, and the gpsManager, sets real_study_loaded to true
    /// called just after registration, and when app is loaded with a registered study
    // func loadDefaultStudy() -> Promise<Bool> {
    //     // print("(loadDefaultStudy) actual run start")
    //     self.currentStudy = nil
    //     self.gpsManager = nil // this seems like a bug waiting to happen
    //     let studies: [Study] = Recline.shared.queryAll()
    //     // mostly sets real_study_loaded to true...
    //     return firstly { () -> Promise<[Study]> in
    //         // print("(loadDefaultStudy) firstly queryall start")
    //         Recline.shared.queryAll() // this returns a list of all studies as a parameter to the next promise.
    //         // I don't understand but trying to refactor as follows for a print statement doesn't work?
    //         // print(print("(loadDefaultStudy) firstly queryall done"))
    //         // return x
    //     }.then { (studies: [Study]) -> Promise<Bool> in
    //         // print("(loadDefaultStudy) then...")
    //         // if there is more than one study, log a warning? this is pointless
    //         if studies.count > 1 {
    //             log.warning("Multiple Studies: \(studies)")
    //         }
    //         // grab the first study and the first study only, set the patient id (but not), real_study_loaded to true
    //         if studies.count > 0 {
    //             self.currentStudy = studies[0]
    //             // print("(loadDefaultStudy) WE SET CURRENT STUDY")
    //             // print("self.currentStudy.patientId: \(self.currentStudy?.patientId)")
    //             // AppDelegate.sharedInstance().setDebuggingUser(self.currentStudy?.patientId ?? "unknown") // this doesn't do anything...
    //             StudyManager.real_study_loaded = true
    //             // print("(loadDefaultStudy) real_study_loaded = true")
    //             self.updateActiveSurveys()
    //         } else {
    //             // print("(loadDefaultStudy) UHOH STUDY COUNT IS 0")
    //         }
    //         
    //         return .value(true)
    //     }
    // }
    
    func loadDefaultStudy() {
        self.currentStudy = nil
        self.gpsManager = nil // this seems like a bug waiting to happen
        let studies: [Study] = Recline.shared.queryAll() // its a list of studies
        if studies.count > 1 {
            log.warning("Multiple Studies: \(studies)") // should we now error on this??
        }
        if studies.count < 1 {
            return // participant not registered.
        }
        self.currentStudy = studies[0]
        StudyManager.real_study_loaded = true
        self.updateActiveSurveys()
    }
    
    /// pretty much an initializer for data services, for some reason gpsManager is the test if we are already initialized
    func startStudyDataServices() {
        // if there is no study return immediately (this should probably throw an error, such an app state is too invalid to support)
        if !self.isStudyLoaded {
            return
        }
        self.setApiCredentials()
        DataStorageManager.sharedInstance.dataStorageManagerInit(self.currentStudy!, secKeyRef: self.keyRef)
        self.prepareDataServices() // prepareDataServices was 90% of the function body
        NotificationCenter.default.addObserver(self, selector: #selector(self.reachabilityChanged), name: ReachabilityChangedNotification, object: nil)
        
        self.heartbeat_on_dispatch_queue()
    }
    
    /// ACTUAL initialization - initializes the weirdly complex self.gpsManager and everything else
    private func prepareDataServices() {
        // current study and study settings are null of course
        guard let studySettings: StudySettings = currentStudy?.studySettings else {
            // this should probably be a crash...
            return
        }
        
        if self.sensorsStartedEver {
            self.timerManager.clearPollTimer()
            self.timerManager.stop() // this one may take real time on another thread soooooo I guess we sleep?
            self.timerManager.clear()
            Thread.sleep(forTimeInterval: 0.5)
        }
        
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
            self.timerManager.addDataService(on_duration: studySettings.gpsOnDurationSeconds, off_duration: studySettings.gpsOffDurationSeconds, dataService: self.gpsManager!)
        }
        if studySettings.accelerometer && studySettings.gpsOnDurationSeconds > 0 {
            self.timerManager.addDataService(on_duration: studySettings.accelerometerOnDurationSeconds, off_duration: studySettings.accelerometerOffDurationSeconds, dataService: AccelerometerManager())
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
            self.timerManager.addDataService(on_duration: studySettings.gyroOnDurationSeconds, off_duration: studySettings.gyroOffDurationSeconds, dataService: GyroManager())
        }
        if studySettings.magnetometer && studySettings.magnetometerOnDurationSeconds > 0 {
            self.timerManager.addDataService(on_duration: studySettings.magnetometerOnDurationSeconds, off_duration: studySettings.magnetometerOffDurationSeconds, dataService: MagnetometerManager())
        }
        if studySettings.motion && studySettings.motionOnDurationSeconds > 0 {
            self.timerManager.addDataService(on_duration: studySettings.motionOnDurationSeconds, off_duration: studySettings.motionOffDurationSeconds, dataService: DeviceMotionManager())
        }
        
        self.gpsManager!.startGps()
        self.timerManager.start()
        self.sensorsStartedEver = true
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
        DataStorageManager.sharedInstance.dataStorageManagerInit(study, secKeyRef: self.keyRef)
        DataStorageManager.sharedInstance.createDirectories()
        // update study stuff?
        Recline.shared.save(study)
        return self.checkSurveys()
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
        if let patientId = currentStudy.patientId { // again WHY is this even allowed to happen on a null participant id
            ApiManager.sharedInstance.patientId = patientId
            if let clientPublicKey = currentStudy.studySettings?.clientPublicKey {
                do {
                    // failure means a null key
                    self.keyRef = try PersistentPasswordManager.sharedInstance.storePublicKeyForStudy(clientPublicKey, patientId: patientId)
                } catch {
                    log.error("Failed to store RSA key in keychain.") // why are we not crashing...
                }
            } else {
                log.error("No public key found.  Can't store") // why are we not crashing...
            }
        }
    }
    
    /// takes a(n active) survey and creates the survey answers file
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
                trackingSurvey = surveyPresenter! // current survey I think?
            }
            trackingSurvey.finalizeSurveyAnswers() // its done, do the its-done thing (writes file)
            
            // increment number of submitted surveys
            if activeSurvey.bwAnswers.count > 0 {
                if let surveyType = survey.surveyType { // ... isn't this already instantiated?
                    switch surveyType {
                    case .AudioSurvey:
                        self.currentStudy?.submittedAudioSurveys = (self.currentStudy?.submittedAudioSurveys ?? 0) + 1
                    case .TrackingSurvey:
                        self.currentStudy?.submittedTrackingSurveys = (self.currentStudy?.submittedTrackingSurveys ?? 0) + 1
                    }
                }
            }
        }
        self.cleanupSurvey(activeSurvey) // call cleanup
    }
    
    /// miniscule portion of finishing a survey answers file creation, finalizes file sorta; also called in audio surveys
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
    /// Called from, AudioQuestionsViewController.saveButtonPressed, StudyManager.checkSurveys,
    ///  and inside TrackingSurveyPresenter when the survey is completed.
    func updateActiveSurveys(_ forceSave: Bool = false) {
        // if for some reason we don't have a current study, return 15 minutes (used when surveys are scheduled tells something to wait 15 minutes)
        guard let study = currentStudy else {
            return
        }
        
        // logic that refreshes survey list
        let activeSurveysModified_1 = self.clear_out_submitted_surveys()
        let activeSurveysModified_2 = self.ensure_active_surveys()
        let activeSurveysModified_3 = self.removeOldSurveys()
        self.updateBadgerCount()
        
        // save survey data
        if activeSurveysModified_1 || activeSurveysModified_2 || activeSurveysModified_3 || forceSave {
            self.emit_survey_updates_save_study_data()
        }
    }
    
    func clear_out_submitted_surveys() -> Bool {
        guard let study = currentStudy else {
            return false
        }
        
        // For all active surveys that aren't complete, but have expired, submit them. (id is a string)
        var surveyDataModified = false
        for activeSurvey in study.activeSurveys.values where activeSurvey.survey != nil {
            // case: always available survey
            // reset the survey, behavior if we don't is the survey stays in the "done" stage you can't retake it.
            // (It loads the survey to the done page, which will resave a new version of the data in a file.)
            if activeSurvey.survey!.alwaysAvailable && activeSurvey.isComplete {
                surveyDataModified = true
                activeSurvey.reset(activeSurvey.survey)
            } else if activeSurvey.isComplete {
                // case normal survey, is complete
                surveyDataModified = true
                // why was this still here... This was supposed to be disabled in 2.4.9 but had to comment it out in 2.4.10.
                // I guess this is what was causing the race condition bug in 2.4.9, but it also _wasn't_ causing
                // the extra submitted survey files submitted bug in 2.4.9. This was very confusing.
                // self.submitSurvey(activeSurvey)
            }
        }
        
        // the old code reset a survey timer by 1 week, but that's not even correct because absolute time and relative schedules exist.
        return surveyDataModified
    }
    
    // func buggy_submit_survey() -> (TimeInterval, Bool) {
    //     guard let study = currentStudy else {
    //         return (Date().addingTimeInterval(15.0 * 60.0).timeIntervalSince1970, false)
    //     }
    //
    //     let currentDate = Date()
    //     let currentTime = currentDate.timeIntervalSince1970
    //     // let currentDay = (calendar as NSCalendar).component(.weekday, from: currentDate) - 1
    //     var nowDateComponents: DateComponents = (calendar as NSCalendar).components(
    //         [NSCalendar.Unit.day, NSCalendar.Unit.year, NSCalendar.Unit.month, NSCalendar.Unit.timeZone], from: currentDate
    //     )
    //     nowDateComponents.hour = 0
    //     nowDateComponents.minute = 0
    //     nowDateComponents.second = 0
    //
    //     // For all active surveys that aren't complete, but have expired, submit them. (id is a string)
    //     var surveyDataModified = false
    //     for (surveyId, activeSurvey) in study.activeSurveys {
    //         // case: always displayed survey
    //         // almost the same as the else-if statement below, except we are resetting the survey, so that we reset the state for a permananent
    //         // survey. If we don't the survey stays in the "done" stage after it is completed and you can't retake it.  It loads the survey to
    //         // the done page, which will resave a new version of the data in a file.
    //         if activeSurvey.survey?.alwaysAvailable ?? false && activeSurvey.isComplete {
    //             print("\nActiveSurvey \(surveyId) expired, this means the file is getting reset.\n")
    //             // activeSurvey.isComplete = true
    //             surveyDataModified = true
    //             //  adding submitSurvey creates a new file; therefore we get 2 files of data- one when you
    //             //  hit the confirm button and one when this code executes. we DO NOT KNOW why this is in the else if statement
    //             //  below - however we are not keeping it in this if statement for the aforementioned problem.
    //             // submitSurvey(activeSurvey)
    //             activeSurvey.reset(activeSurvey.survey)
    //         }
    //         // submits ALL permanent surveys when ANY permanent survey loads. <- (I think that's ok, it doesn't create a file unless opened - I think.
    //         //   No data bugs because of it, possibly due to the deduplication step.)
    //         // case: If the survey not been completed, but it is time for the next survey
    //         // TODO: why don't we have nextScheduleTime on active (or normal) surveys? oh we have no schedule inspection logic riiight.
    //         else if !activeSurvey.isComplete /* && activeSurvey.nextScheduledTime > 0 && activeSurvey.nextScheduledTime <= currentTime */ {
    //             log.info("ActiveSurvey \(surveyId) expired.")
    //             // activeSurvey.isComplete = true;
    //             surveyDataModified = true
    //             self.submitSurvey(activeSurvey)
    //         }
    //     }
    //
    //     // calculate the duration the survey can be active/not be reset for (always 1 week) and return that time.
    //     // FIXME: it was in trying to track down why on earth this was hardcoded to 1 week that I discovered there is no code to parse the survey schedules
    //     let closestNextSurveyTime: TimeInterval = currentTime + (60.0 * 60.0 * 24.0 * 7)
    //     self.timerManager.resetNextSurveyUpdate(closestNextSurveyTime)
    //     return (closestNextSurveyTime, surveyDataModified)
    // }
    
    /// Checks the database for surveys that should exist, removes active surveys that are not in that list.
    // FIXME: This does not do anything if surveys are not removed from the database when the app checks for new surveys. NEED TO TEST.
    func removeOldSurveys() -> Bool {
        guard let study = self.currentStudy else {
            return false
        }
        var surveyDataModified = false
        let allSurveyIds = self.getAllSurveyIds() // this is, in-fact, sourced from RecLine
        for (surveyId, activeSurvey) in study.activeSurveys {
            if activeSurvey.isComplete && !allSurveyIds.contains(surveyId) {
                study.activeSurveys.removeValue(forKey: surveyId)
                surveyDataModified = true
            }
        }
        return surveyDataModified
    }
    
    /// Set the badger count - a count of untaken surveys, excluding always-available surveys.
    func updateBadgerCount() {
        guard let study = self.currentStudy else {
            return
        }
        var bdgrCnt = 0
        for activeSurvey in study.activeSurveys.values where activeSurvey.survey != nil {
            // if survey is not complete and the survey is not an always available survey
            if !activeSurvey.isComplete && !activeSurvey.survey!.alwaysAvailable {
                bdgrCnt += 1
            }
        }
        // print("Setting badge count to: \(bdgrCnt)")
        UIApplication.shared.applicationIconBadgeNumber = bdgrCnt
    }
    
    // /// Has some very incoherent logical statements.
    // func updateBadgerCount_old() -> Bool {
    //     guard let study = self.currentStudy else {
    //         return false
    //     }
    //
    //     // Set the badge, and remove surveys no longer on server from our active surveys list
    //     let allSurveyIds = self.getAllSurveyIds()
    //     var surveyDataModified = false
    //     var badgeCnt = 0
    //     for (id, activeSurvey) in study.activeSurveys {
    //         if activeSurvey.isComplete && !allSurveyIds.contains(id) {
    //             self.cleanupSurvey(activeSurvey)
    //             study.activeSurveys.removeValue(forKey: id)
    //             surveyDataModified = true
    //         } else if !activeSurvey.isComplete {
    //             // if (activeSurvey.nextScheduledTime > 0) {
    //             //     closestNextSurveyTime = min(closestNextSurveyTime, activeSurvey.nextScheduledTime);
    //             // }
    //             badgeCnt += 1
    //         }
    //     }
    //     // print("Setting badge count to: \(badgeCnt)")
    //     UIApplication.shared.applicationIconBadgeNumber = badgeCnt
    //     return surveyDataModified
    // }
    
    /// changes from check_surveys_old
    /// radically simplified equivalent logic
    /// doesn't generate list of survey ids
    /// we have no effective scheduling logic here ANYWAY
    /// FIXME: there is no way this is not bugged even though the logic is equivalent to the old version, because always available and triggerOnFirstDownload are treated identically
    func ensure_active_surveys() -> Bool {
        guard let study = self.currentStudy else {
            return false
        }
        
        var surveyDataModified = false
        
        // for each survey, check on its availability
        for survey in study.surveys where survey.surveyId != nil {
            // `study.activeSurveys[id] == nil` means the study is not activated...
            // If so and the survey is a triggerOnFirstDownload or alwaysAvailable survey, add it to active surveys list
            if study.activeSurveys[survey.surveyId!] == nil && (survey.triggerOnFirstDownload || survey.alwaysAvailable) {
                print("Adding survey \(survey.name) to active surveys survey.triggerOnFirstDownload: \(survey.triggerOnFirstDownload), survey.alwaysAvailable: \(survey.alwaysAvailable)")
                study.activeSurveys[survey.surveyId!] = ActiveSurvey(survey: survey)
                surveyDataModified = true
            }
        }
        return surveyDataModified
    }
    
    /// This is the old version of the code that checked survey properties and status for adding them to activeSurveys.
    /// The original comments have been preservered, the logic has been radically simplified in check_surveys_new above.
    /// This code is real dumb, I don't think it logically makes sense. I don't understand how the ios app workd with this
    /// degree of crappy, wrote checks checks for which surveys should be active - triggerOnFirstDownload has the exact
    /// same activation logic as alwaysAvailable
    // func ensure_active_surveys_old() -> Bool {
    //     guard let study = self.currentStudy else {
    //         return false
    //     }
    //     print("new check_surveys")
    //     var surveyDataModified = false
    //
    //     // for each survey from the server, check on the scheduling
    //     var allSurveyIds: [String] = []
    //     for survey in study.surveys {
    //         if let id = survey.surveyId {
    //             allSurveyIds.append(id)
    //             // If we don't know about this survey already, add it in there for TRIGGERONFIRSTDOWNLOAD surverys
    //             if study.activeSurveys[id] == nil && (survey.triggerOnFirstDownload /* || next > 0 */ ) {
    //                 print("Adding survey  \(id) to active surveys")
    //                 let newActiveSurvey = ActiveSurvey(survey: survey)
    //                 study.activeSurveys[id] = newActiveSurvey
    //                 surveyDataModified = true
    //             }
    //             // We want to display permanent surveys as active, and expect to change some details below (currently
    //             // identical to the actions we take on a regular active survey)
    //             else if study.activeSurveys[id] == nil && (survey.alwaysAvailable) {
    //                 print("Adding survey  \(id) to active surveys")
    //                 let newActiveSurvey = ActiveSurvey(survey: survey)
    //                 study.activeSurveys[id] = newActiveSurvey
    //                 surveyDataModified = true
    //             }
    //         }
    //     }
    //     return surveyDataModified
    // }
    
    ///
    /// Timers! They do what they say and aren't even complicated! Holy !#*&$@#*!
    ///    okay but they do all use completely unnecessary promises.
    
    func setNextUploadTime() -> Promise<Bool> {
        guard let study = currentStudy, let studySettings = study.studySettings else {
            return .value(true)
        }
        study.nextUploadCheck = Int64(Date().timeIntervalSince1970) + Int64(studySettings.uploadDataFileFrequencySeconds)
        Recline.shared.save(study)
        return Promise.value(true)
    }
    
    func setNextSurveyTime() -> Promise<Bool> {
        guard let study = currentStudy, let studySettings = study.studySettings else {
            return .value(true)
        }
        study.nextSurveyCheck = Int64(Date().timeIntervalSince1970) + Int64(studySettings.checkForNewSurveysFreqSeconds)
        Recline.shared.save(study)
        return Promise.value(true)
    }
    
    func setNextDeviceSettingsTime() -> Promise<Bool> {
        guard let study = currentStudy else {
            return .value(true)
        }
        study.nextDeviceSettingsCheck = Int64(Date().timeIntervalSince1970) + DEVICE_SETTINGS_INTERVAL
        Recline.shared.save(study)
        return Promise.value(true)
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
    
    /// runs network operations inside of promises, handles checking and updating timer values on the timer.
    /// called from Timer and a couple other places.
    func periodicNetworkTransfers() {
        // fail early logic, get study settings and study.
        guard let currentStudy = currentStudy, let studySettings = currentStudy.studySettings else {
            return
        }
        // check the uploadOverCellular study detail.
        let reachable = studySettings.uploadOverCellular ? self.appDelegate.reachability!.isReachable : self.appDelegate.reachability!.isReachableViaWiFi
        let now: Int64 = Int64(Date().timeIntervalSince1970)
        let nextSurvey = currentStudy.nextSurveyCheck ?? 0
        let nextUpload = currentStudy.nextUploadCheck ?? 0
        let nextDeviceSettings = currentStudy.nextDeviceSettingsCheck ?? 0
        
        // print("reachable: \(reachable), missedSurveyCheck: \(currentStudy.missedSurveyCheck), missedUploadCheck: \(currentStudy.missedUploadCheck)")
        // print("now: \(now), nextSurvey: \(nextSurvey), nextUpload: \(nextUpload), nextDeviceSettings: \(nextDeviceSettings)")
        
        // logic for checking for surveys
        if now > nextSurvey || (reachable && currentStudy.missedSurveyCheck) {
            // This (missedSurveyCheck?) will be saved because setNextSurveyTime saves the study
            currentStudy.missedSurveyCheck = !reachable // whut?
            self.setNextSurveyTime().done { (_: Bool) in
                if reachable {
                    _ = self.checkSurveys()
                }
            }.catch { (_: Error) in
                log.error("Error checking for surveys")
            }
        }
        
        // logic for running uploads code
        if now > nextUpload || (reachable && currentStudy.missedUploadCheck) {
            // This (missedUploadCheck?) will be saved because setNextUpload saves the study
            currentStudy.missedUploadCheck = !reachable
            self.setNextUploadTime().done { (_: Bool) in
                _ = self.upload(!reachable)
            }.catch { (_: Error) in
                log.error("Error checking for uploads") // this is kindof unnecessary
            }
        }
        
        // logic for updating the study's device settings.
        if now > nextDeviceSettings && reachable {
            // print("Checking for updated device settings...")
            self.setNextDeviceSettingsTime().done { (_: Bool) in
                self.updateDeviceSettings()
            }.catch { (_: Error) in
                log.error("Error checking for updated device settings") // this is kindof unnecessary
            }
        }
    }
    
    func heartbeat_on_dispatch_queue() {
        print("Enqueuing heartbeat...")
        HEARTBEAT_QUEUE.asyncAfter(deadline: .now() + Constants.HEARTBEAT_INTERVAL, execute: {
            print("running heartbeat on dispatch queue \(Date())")
            self.heartbeat("DispatchQueue \(Constants.HEARTBEAT_INTERVAL) secondly - \(countBackgroundTasks())")
            self.heartbeat_on_dispatch_queue()
        })
    }
    
    /// dispatches the heartbeat task to run in a loop forever every 5 minutes.
    func heartbeat(_ message: String) {
        print("Sending heartbeat...")
        ApiManager.sharedInstance.extremelySimplePostRequest(
            "/mobile-heartbeat/",
            extra_parameters: ["message": message]
        )
    }
    
    /// called from self.setConsented, periodicNetworkTasks, and a debug menu button (I think)
    /// THE RETURN VALUE IS NOT USED BECAUSE OF COURSE NOT
    func checkSurveys() -> Promise<Bool> {
        // return early if there is no study or no study settings (retaining studysettings check for safety)
        guard let study = currentStudy, let _ = study.studySettings else {
            return .value(false)
        }
        log.info("Checking for surveys...")
        
        // save the study and then....
        Recline.shared.save(study)
        let surveyRequest = GetSurveysRequest()
        return ApiManager.sharedInstance.arrayPostRequest(surveyRequest).then { surveys, _ -> Promise<Void> in
            // then... we receive the surveys from the api manager request possibly?
            // (This is another reason why promises are bad, they pointless obscure critical information)
            log.info("Surveys: \(surveys)")
            study.surveys = surveys
            Recline.shared.save(study)
            return Promise<Void>()
        }.then { _ -> Promise<Bool> in // its an error type
            // then update the active surveys because the surveys may have just changed
            self.updateActiveSurveys()
            return .value(true)
        }.recover { _ -> Promise<Bool> in // _ is of some error type
            // and if anything went wrong return false  --  IT IS NEVER USED
            .value(false)
        }
    }
    
    /// This abomination of a function queries the server for new study settings, applies them, and then restarts sensors if anything changed
    func updateDeviceSettings() {
        // assert that these are instantiated
        guard let _ = self.currentStudy, let _ = self.currentStudy?.studySettings else {
            return
        }
        // make the post request, convert to json, convert to a JustStudySettings mapper
        _ = ApiManager.sharedInstance.makePostRequest(UpdateDeviceSettingsRequest()).done { (response: BodyResponse, some_int: Int) in
            if let body_string = response.body {
                let newSettings: JustStudySettings? = Mapper<JustStudySettings>().map(JSONString: body_string) // manually calling the mapper
                // Check EVERY SETTING, record if anything changed, assign any new values
                if let newSettings = newSettings {
                    var anything_changed: Bool = false
                    if self.currentStudy?.studySettings?.accelerometer != newSettings.accelerometer {
                        anything_changed = true
                        self.currentStudy?.studySettings?.accelerometer = newSettings.accelerometer
                        // print("accelerometer changed to: \(newSettings.accelerometer)")
                    }
                    if self.currentStudy?.studySettings?.accelerometerOffDurationSeconds != newSettings.accelerometerOffDurationSeconds {
                        anything_changed = true
                        self.currentStudy?.studySettings?.accelerometerOffDurationSeconds = newSettings.accelerometerOffDurationSeconds
                        // print("accelerometerOffDurationSeconds changed to: \(newSettings.accelerometerOffDurationSeconds)")
                    }
                    if self.currentStudy?.studySettings?.accelerometerOnDurationSeconds != newSettings.accelerometerOnDurationSeconds {
                        anything_changed = true
                        self.currentStudy?.studySettings?.accelerometerOnDurationSeconds = newSettings.accelerometerOnDurationSeconds
                        // print("accelerometerOnDurationSeconds changed to: \(newSettings.accelerometerOnDurationSeconds)")
                    }
                    if self.currentStudy?.studySettings?.accelerometerFrequency != newSettings.accelerometerFrequency {
                        anything_changed = true
                        self.currentStudy?.studySettings?.accelerometerFrequency = newSettings.accelerometerFrequency
                        // print("accelerometerFrequency changed to: \(newSettings.accelerometerFrequency)")
                    }
                    if self.currentStudy?.studySettings?.aboutPageText != newSettings.aboutPageText {
                        anything_changed = true
                        self.currentStudy?.studySettings?.aboutPageText = newSettings.aboutPageText
                        // print("aboutPageText changed to: \(newSettings.aboutPageText)")
                    }
                    if self.currentStudy?.studySettings?.callClinicianText != newSettings.callClinicianText {
                        anything_changed = true
                        self.currentStudy?.studySettings?.callClinicianText = newSettings.callClinicianText
                        // print("callClinicianText changed to: \(newSettings.callClinicianText)")
                    }
                    if self.currentStudy?.studySettings?.consentFormText != newSettings.consentFormText {
                        anything_changed = true
                        self.currentStudy?.studySettings?.consentFormText = newSettings.consentFormText
                        // print("consentFormText changed to: \(newSettings.consentFormText)")
                    }
                    if self.currentStudy?.studySettings?.checkForNewSurveysFreqSeconds != newSettings.checkForNewSurveysFreqSeconds {
                        anything_changed = true
                        self.currentStudy?.studySettings?.checkForNewSurveysFreqSeconds = newSettings.checkForNewSurveysFreqSeconds
                        // print("checkForNewSurveysFreqSeconds changed to: \(newSettings.checkForNewSurveysFreqSeconds)")
                    }
                    if self.currentStudy?.studySettings?.createNewDataFileFrequencySeconds != newSettings.createNewDataFileFrequencySeconds {
                        anything_changed = true
                        self.currentStudy?.studySettings?.createNewDataFileFrequencySeconds = newSettings.createNewDataFileFrequencySeconds
                        // print("createNewDataFileFrequencySeconds changed to: \(newSettings.createNewDataFileFrequencySeconds)")
                    }
                    if self.currentStudy?.studySettings?.gps != newSettings.gps {
                        anything_changed = true
                        self.currentStudy?.studySettings?.gps = newSettings.gps
                        // print("gps changed to: \(newSettings.gps)")
                    }
                    if self.currentStudy?.studySettings?.gpsOffDurationSeconds != newSettings.gpsOffDurationSeconds {
                        anything_changed = true
                        self.currentStudy?.studySettings?.gpsOffDurationSeconds = newSettings.gpsOffDurationSeconds
                        // print("gpsOffDurationSeconds changed to: \(newSettings.gpsOffDurationSeconds)")
                    }
                    if self.currentStudy?.studySettings?.gpsOnDurationSeconds != newSettings.gpsOnDurationSeconds {
                        anything_changed = true
                        self.currentStudy?.studySettings?.gpsOnDurationSeconds = newSettings.gpsOnDurationSeconds
                        // print("gpsOnDurationSeconds changed to: \(newSettings.gpsOnDurationSeconds)")
                    }
                    if self.currentStudy?.studySettings?.powerState != newSettings.powerState {
                        anything_changed = true
                        self.currentStudy?.studySettings?.powerState = newSettings.powerState
                        // print("powerState changed to: \(newSettings.powerState)")
                    }
                    if self.currentStudy?.studySettings?.secondsBeforeAutoLogout != newSettings.secondsBeforeAutoLogout {
                        anything_changed = true
                        self.currentStudy?.studySettings?.secondsBeforeAutoLogout = newSettings.secondsBeforeAutoLogout
                        // print("secondsBeforeAutoLogout changed to: \(newSettings.secondsBeforeAutoLogout)")
                    }
                    if self.currentStudy?.studySettings?.submitSurveySuccessText != newSettings.submitSurveySuccessText {
                        anything_changed = true
                        self.currentStudy?.studySettings?.submitSurveySuccessText = newSettings.submitSurveySuccessText
                        // print("submitSurveySuccessText changed to: \(newSettings.submitSurveySuccessText)")
                    }
                    if self.currentStudy?.studySettings?.uploadDataFileFrequencySeconds != newSettings.uploadDataFileFrequencySeconds {
                        anything_changed = true
                        self.currentStudy?.studySettings?.uploadDataFileFrequencySeconds = newSettings.uploadDataFileFrequencySeconds
                        // print("uploadDataFileFrequencySeconds changed to: \(newSettings.uploadDataFileFrequencySeconds)")
                    }
                    if self.currentStudy?.studySettings?.voiceRecordingMaxLengthSeconds != newSettings.voiceRecordingMaxLengthSeconds {
                        anything_changed = true
                        self.currentStudy?.studySettings?.voiceRecordingMaxLengthSeconds = newSettings.voiceRecordingMaxLengthSeconds
                        // print("voiceRecordingMaxLengthSeconds changed to: \(newSettings.voiceRecordingMaxLengthSeconds)")
                    }
                    if self.currentStudy?.studySettings?.wifi != newSettings.wifi {
                        anything_changed = true
                        self.currentStudy?.studySettings?.wifi = newSettings.wifi
                        // print("wifi changed to: \(newSettings.wifi)")
                    }
                    if self.currentStudy?.studySettings?.wifiLogFrequencySeconds != newSettings.wifiLogFrequencySeconds {
                        anything_changed = true
                        self.currentStudy?.studySettings?.wifiLogFrequencySeconds = newSettings.wifiLogFrequencySeconds
                        // print("wifiLogFrequencySeconds changed to: \(newSettings.wifiLogFrequencySeconds)")
                    }
                    if self.currentStudy?.studySettings?.proximity != newSettings.proximity {
                        anything_changed = true
                        self.currentStudy?.studySettings?.proximity = newSettings.proximity
                        // print("proximity changed to: \(newSettings.proximity)")
                    }
                    if self.currentStudy?.studySettings?.magnetometer != newSettings.magnetometer {
                        anything_changed = true
                        self.currentStudy?.studySettings?.magnetometer = newSettings.magnetometer
                        // print("magnetometer changed to: \(newSettings.magnetometer)")
                    }
                    if self.currentStudy?.studySettings?.magnetometerOffDurationSeconds != newSettings.magnetometerOffDurationSeconds {
                        anything_changed = true
                        self.currentStudy?.studySettings?.magnetometerOffDurationSeconds = newSettings.magnetometerOffDurationSeconds
                        // print("magnetometerOffDurationSeconds changed to: \(newSettings.magnetometerOffDurationSeconds)")
                    }
                    if self.currentStudy?.studySettings?.magnetometerOnDurationSeconds != newSettings.magnetometerOnDurationSeconds {
                        anything_changed = true
                        self.currentStudy?.studySettings?.magnetometerOnDurationSeconds = newSettings.magnetometerOnDurationSeconds
                        // print("magnetometerOnDurationSeconds changed to: \(newSettings.magnetometerOnDurationSeconds)")
                    }
                    if self.currentStudy?.studySettings?.gyro != newSettings.gyro {
                        anything_changed = true
                        self.currentStudy?.studySettings?.gyro = newSettings.gyro
                        // print("gyro changed to: \(newSettings.gyro)")
                    }
                    if self.currentStudy?.studySettings?.gyroOffDurationSeconds != newSettings.gyroOffDurationSeconds {
                        anything_changed = true
                        self.currentStudy?.studySettings?.gyroOffDurationSeconds = newSettings.gyroOffDurationSeconds
                        // print("gyroOffDurationSeconds changed to: \(newSettings.gyroOffDurationSeconds)")
                    }
                    if self.currentStudy?.studySettings?.gyroOnDurationSeconds != newSettings.gyroOnDurationSeconds {
                        anything_changed = true
                        self.currentStudy?.studySettings?.gyroOnDurationSeconds = newSettings.gyroOnDurationSeconds
                        // print("gyroOnDurationSeconds changed to: \(newSettings.gyroOnDurationSeconds)")
                    }
                    if self.currentStudy?.studySettings?.gyroFrequency != newSettings.gyroFrequency {
                        anything_changed = true
                        self.currentStudy?.studySettings?.gyroFrequency = newSettings.gyroFrequency
                        // print("gyroFrequency changed to: \(newSettings.gyroFrequency)")
                    }
                    if self.currentStudy?.studySettings?.motion != newSettings.motion {
                        anything_changed = true
                        self.currentStudy?.studySettings?.motion = newSettings.motion
                        // print("motion changed to: \(newSettings.motion)")
                    }
                    if self.currentStudy?.studySettings?.motionOffDurationSeconds != newSettings.motionOffDurationSeconds {
                        anything_changed = true
                        self.currentStudy?.studySettings?.motionOffDurationSeconds = newSettings.motionOffDurationSeconds
                        // print("motionOffDurationSeconds changed to: \(newSettings.motionOffDurationSeconds)")
                    }
                    if self.currentStudy?.studySettings?.motionOnDurationSeconds != newSettings.motionOnDurationSeconds {
                        anything_changed = true
                        self.currentStudy?.studySettings?.motionOnDurationSeconds = newSettings.motionOnDurationSeconds
                        // print("motionOnDurationSeconds changed to: \(newSettings.motionOnDurationSeconds)")
                    }
                    if self.currentStudy?.studySettings?.reachability != newSettings.reachability {
                        anything_changed = true
                        self.currentStudy?.studySettings?.reachability = newSettings.reachability
                        // print("reachability changed to: \(newSettings.reachability)")
                    }
                    if self.currentStudy?.studySettings?.consentSections != newSettings.consentSections {
                        anything_changed = true
                        self.currentStudy?.studySettings?.consentSections = newSettings.consentSections
                        // print("consentSections changed to: \(newSettings.consentSections)")
                    }
                    if self.currentStudy?.studySettings?.uploadOverCellular != newSettings.uploadOverCellular {
                        anything_changed = true
                        self.currentStudy?.studySettings?.uploadOverCellular = newSettings.uploadOverCellular
                        // print("uploadOverCellular changed to: \(newSettings.uploadOverCellular)")
                    }
                    if self.currentStudy?.studySettings?.fuzzGps != newSettings.fuzzGps {
                        anything_changed = true
                        self.currentStudy?.studySettings?.fuzzGps = newSettings.fuzzGps
                        // print("fuzzGps changed to: \(newSettings.fuzzGps)")
                    }
                    if self.currentStudy?.studySettings?.callClinicianButtonEnabled != newSettings.callClinicianButtonEnabled {
                        anything_changed = true
                        self.currentStudy?.studySettings?.callClinicianButtonEnabled = newSettings.callClinicianButtonEnabled
                        // print("callClinicianButtonEnabled changed to: \(newSettings.callClinicianButtonEnabled)")
                    }
                    if self.currentStudy?.studySettings?.callResearchAssistantButtonEnabled != newSettings.callResearchAssistantButtonEnabled {
                        anything_changed = true
                        self.currentStudy?.studySettings?.callResearchAssistantButtonEnabled = newSettings.callResearchAssistantButtonEnabled
                        // print("callResearchAssistantButtonEnabled changed to: \(newSettings.callResearchAssistantButtonEnabled)")
                    }
                    // if anything changed, reset all data services.
                    Recline.shared.save(self.currentStudy!)
                    
                    if anything_changed {
                        self.prepareDataServices()
                    }
                }
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
        RECLINE_QUEUE.sync { Recline.shared.compact() }
        DataStorageManager.sharedInstance.prepareForUpload()
        // THIS ISN'T A PROMISECHAIN THAT'S A REAL THING AND NOT A THIS
        let promiseChain: Promise<Bool> = Promise<Bool>.value(true)
        // most of the function is after the return statement, duh.
        return promiseChain.then(on: GLOBAL_DEFAULT_QUEUE) { (_: Bool) -> Promise<Bool> in
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
                var uploadChain = Promise<Bool>.value(true) // iinstantiate the start (end? yeah its the end) of the promise chain
                for filename in filesToProcess {
                    let filePath = DataStorageManager.uploadDataDirectory().appendingPathComponent(filename)
                    let uploadRequest = UploadRequest(fileName: filename, filePath: filePath.path)
                    
                    // add the upload operation to the upload chain
                    uploadChain = uploadChain.then { (_: Bool) -> Promise<Bool> in
                        // do an upload
                        ApiManager.sharedInstance.makeMultipartUploadRequest(uploadRequest, file: filePath).then { (_: (UploadRequest.ApiReturnType, Int)) -> Promise<Bool> in
                            // print("Finished uploading: \(filename), deleting.")
                            AppEventManager.sharedInstance.logAppEvent(event: "uploaded", msg: "Uploaded data file", d1: filename)
                            numFiles = numFiles + 1
                            try FileManager.default.removeItem(at: filePath) // ok I guess this can fail...?
                            return .value(true)
                        }
                    }.recover { (_: Error) -> Promise<Bool> in
                        // in case of errors...
                        // log.warning("upload failed: \(filename)")
                        AppEventManager.sharedInstance.logAppEvent(event: "upload_file_failed", msg: "Failed Uploaded data file", d1: filename)
                        return .value(true)
                    }
                }
                return uploadChain
            } else {
                // log.info("Skipping upload, processing only")
                return .value(true)
            }
            // the rest of this is logging and then marking isUploading as false using ensure
        }.then { (results: Bool) -> Promise<Void> in
            // does this happen first? why are we using promises......
            log.verbose("OK uploading \(numFiles). \(results)")
            AppEventManager.sharedInstance.logAppEvent(event: "upload_complete", msg: "Upload Complete", d1: String(numFiles))
            if let study = self.currentStudy {
                study.lastUploadSuccess = Int64(NSDate().timeIntervalSince1970)
                Recline.shared.save(study)
                return Promise()
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
    
    // The reason this code is still present is because we need to handle the case of a user dismissing or exiting the
    // app during the registration or consent sections stage of registration.  We would probably be fine without it,
    // but this is some free safety so until it becomes a maintenance burden we will keep it.
    
    /// the bulk of the leave study feature.
    func leaveStudy() {
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
        
        // clear out remaining active study objects
        self.gpsManager = nil
        self.timerManager.clear() // this may deallocate all sensors.  I think.
        self.purgeStudies()
        
        // delete upload diirectory using ugly code
        var enumerator = FileManager.default.enumerator(atPath: DataStorageManager.uploadDataDirectory().path)
        if let enumerator = enumerator {
            while let filename = enumerator.nextObject() as? String {
                if true /* filename.hasSuffix(DataStorageManager.dataFileSuffix) */ {
                    let filePath = DataStorageManager.uploadDataDirectory().appendingPathComponent(filename)
                    do {
                        try FileManager.default.removeItem(at: filePath)
                    } catch {
                        log.error("(1) Failed to delete file: \(filename) with error \(error)")
                    }
                }
            }
        }
        
        // delete data directory using ugly code
        enumerator = FileManager.default.enumerator(atPath: DataStorageManager.currentDataDirectory().path)
        if let enumerator = enumerator {
            while let filename = enumerator.nextObject() as? String {
                let filePath = DataStorageManager.currentDataDirectory().appendingPathComponent(filename)
                do {
                    try FileManager.default.removeItem(at: filePath)
                } catch {
                    log.error("(2) Failed to delete file: \(filename) with error \(error)")
                }
            }
        }
        
        // clear the study, patient id
        self.currentStudy = nil // self.isStudyLoaded will now fail
        ApiManager.sharedInstance.patientId = ""
        
        // I don't know what this is and I don't think it matters.
        let instance = InstanceID.instanceID()
        instance.deleteID { (error: Error?) in
            log.error(error.debugDescription)
        }
    }
    
    /// deletes all studies - used in registration for some reason
    // func purgeStudies() {
    //     let studies: [Study] = Recline.shared.queryAll()
    //     for study in studies {
    //         Recline.shared.purge(study)
    //     }
    // }
    
    func purgeStudies() {
        let studies = Recline.shared.queryAll() // this returns a list of studies, ignore the templated type
        for study in studies {
            Recline.shared.purge(study)
        }
    }
    
    ///
    /// Miscellaneous utility functions
    ///
    
    /// only called from AppDelegate.applicationWillTerminate
    func stop() {
        // stop gps because it interacts with app persistence...?
        if self.gpsManager != nil {
            self.gpsManager!.stopGps()
            self.gpsManager = nil
        }
        
        // stop all recording, clear registered timer events
        self.timerManager.stop()
        self.timerManager.clear()
        
        // clear currentStudy - this originally ran on the default background queue inside a promisekit promise,
        // but it was only called in applicationWillTerminate, so we can just run it on the main thread?
        self.currentStudy = nil
        StudyManager.real_study_loaded = false
    }
}
