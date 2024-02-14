import Alamofire
import Crashlytics
import EmitterKit
import Firebase
import Foundation
import ObjectMapper
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
    var files_in_flight = [String]() // the filees we are currently trying to upload.
    var sensorsStartedEver = false
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
        guard let studySettings: StudySettings = self.currentStudy?.studySettings else {
            return // this should probably be a crash...
        }
        
        if self.sensorsStartedEver {
            self.timerManager.clearPollTimer()
            self.timerManager.stop() // this one may take real time on another thread soooooo I guess we sleep?
            self.timerManager.clear()
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        DataStorageManager.sharedInstance.createDirectories()
        // Move non current files out.  (Probably unnecessary, would happen later anyway)
        DataStorageManager.sharedInstance.prepareForUpload()
        
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
    // ok I have not tested whether removing the promise from this impacts registration...
    func setConsented() {
        // fail if current study or study settings are null
        guard let study = currentStudy, let studySettings = study.studySettings else {
            return
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
        self.checkSurveys()
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
            DataStorageManager.sharedInstance.closeStore(timingsName)
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
    
    // FIXME: there these two functions: updateActiveSurveys, setActiveSurveys
    // Are diverged versions of related code, see fixme next to duplicated download surveys code
    
    /// sets the active survey on the main app page, force-enables any specified surveys.
    func setActiveSurveys(surveyIds: [String], sentTime: TimeInterval = 0) {
        guard let study = self.currentStudy else {
            return
        }
        
        // force reload all always-available surveys and any passed in surveys
        for survey in study.surveys {
            let surveyId = survey.surveyId!, from_notification = surveyIds.contains(surveyId)
            
            if from_notification || survey.alwaysAvailable {
                let activeSurvey = ActiveSurvey(survey: survey)
                // when we receive a notification we need to record that, this is used to sort surveys on the main screen (I think)
                if from_notification {
                    activeSurvey.received = sentTime
                    // FIXME: study.receivedAudioSurveys and study.receivedTrackingSurveys are junk, they are assigned but never used.
                    if let surveyType = survey.surveyType {
                        switch surveyType {
                        case .AudioSurvey:
                            study.receivedAudioSurveys = (study.receivedAudioSurveys) + 1
                        case .TrackingSurvey:
                            study.receivedTrackingSurveys = (study.receivedTrackingSurveys) + 1
                        }
                    }
                }
                study.activeSurveys[surveyId] = activeSurvey
            }
        }
        
        // if the survey id doesn't exist record a log statement
        for surveyId in surveyIds {
            if !study.surveyExists(surveyId: surveyId) {
                print("Could not get survey \(surveyId)")
                AppEventManager.sharedInstance.logAppEvent(event: "survey_download", msg: "Could not get obtain survey for ActiveSurvey")
            }
        }
        
        // Emits a surveyUpdated event to the listener
        StudyManager.sharedInstance.surveysUpdatedEvent.emit(0)
        Recline.shared.save(study)
        
        // set badge number
        UIApplication.shared.applicationIconBadgeNumber = study.activeSurveys.count
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
    
    /// Timers! They now do what they say they do and aren't even complicated! Holy !#*&$@#*!
    /// AND NOW THEY DON'T USE PROMISES
    
    func setNextUploadTime() {
        guard let study = currentStudy, let studySettings = study.studySettings else {
            return
        }
        study.nextUploadCheck = Int64(Date().timeIntervalSince1970) + Int64(studySettings.uploadDataFileFrequencySeconds)
        Recline.shared.save(study)
    }
    
    func setNextSurveyTime() {
        guard let study = currentStudy, let studySettings = study.studySettings else {
            return
        }
        study.nextSurveyCheck = Int64(Date().timeIntervalSince1970) + Int64(studySettings.checkForNewSurveysFreqSeconds)
        Recline.shared.save(study)
    }
    
    func setNextDeviceSettingsTime() {
        guard let study = currentStudy else {
            return
        }
        study.nextDeviceSettingsCheck = Int64(Date().timeIntervalSince1970) + DEVICE_SETTINGS_INTERVAL
        Recline.shared.save(study)
    }
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////// Network Operations ////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    /// some kind of reachability thing, calls periodicNetworkTransfers
    @objc func reachabilityChanged(_ notification: Notification) {
        print("Reachability changed, running periodic network transfers.")
        self.periodicNetworkTransfers()
    }
    
    /// runs network operations, handles checking and updating timer values on the timer.
    /// called from Timer and a couple other places.
    func periodicNetworkTransfers() {
        // fail early logic, get study settings and study.
        guard let currentStudy = currentStudy, let studySettings = currentStudy.studySettings else {
            return
        }
        // check the uploadOverCellular study detail.
        let reachable = studySettings.uploadOverCellular ?
            self.appDelegate.reachability!.isReachable : self.appDelegate.reachability!.isReachableViaWiFi
        let now: Int64 = Int64(Date().timeIntervalSince1970)
        let nextSurvey = currentStudy.nextSurveyCheck ?? 0
        let nextUpload = currentStudy.nextUploadCheck ?? 0
        let nextDeviceSettings = currentStudy.nextDeviceSettingsCheck ?? 0
        
        // print("reachable: \(reachable), missedSurveyCheck: \(currentStudy.missedSurveyCheck), missedUploadCheck: \(currentStudy.missedUploadCheck)")
        // print("now: \(now), nextSurvey: \(nextSurvey), nextUpload: \(nextUpload), nextDeviceSettings: \(nextDeviceSettings)")
        
        // logic for checking for surveys
        if now > nextSurvey || (reachable && currentStudy.missedSurveyCheck) {
            // This (missedSurveyCheck?) will be saved because setNextSurveyTime saves the study
            currentStudy.missedSurveyCheck = !reachable // if not reachable we missed the survey check
            self.setNextSurveyTime()
            if reachable {
                self.checkSurveys()
            }
        }
        
        // logic for running uploads code
        if now > nextUpload || (reachable && currentStudy.missedUploadCheck) {
            // This (missedUploadCheck?) will be saved because setNextUpload saves the study
            currentStudy.missedUploadCheck = !reachable // if not reachable we missed the upload check
            self.setNextUploadTime()
            if reachable {
                self.upload()
            }
        }
        
        // logic for updating the study's device settings.
        if now > nextDeviceSettings && reachable {
            // print("Checking for updated device settings...")
            self.setNextDeviceSettingsTime()
            self.updateDeviceSettings()
        }
    }
    
    func heartbeat_on_dispatch_queue() {
        print("Scheduling dispatchqueue heartbeat...")
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
    func checkSurveys() {
        guard let study = currentStudy else {
            return
        }
        print("inside duplicate survey checker function 1")
        
        // save the study and then....
        Recline.shared.save(study)
        
        ApiManager.sharedInstance.makePostRequest(
            GetSurveysRequest(), completion_handler: { (response: DataResponse<String>) in
                var error_message = ""
                switch response.result {
                case .success:
                    if let statusCode = response.response?.statusCode {
                        // valid 200 range response
                        if statusCode >= 200 && statusCode < 300 {
                            let body_response = BodyResponse(body: response.result.value)
                            if let body_string = body_response.body {
                                if let newSurveys: [Survey] = Mapper<Survey>().mapArray(JSONString: body_string) {
                                    // we have survey data!
                                    study.surveys = newSurveys
                                    Recline.shared.save(study)
                                    self.updateActiveSurveys() // differs from other version of code.
                                } else {
                                    error_message = "download surveys: \(response) - but body was nil"
                                }
                            }
                        } else { // all non-200 error codes
                            error_message = "download surveys: statuscode: \(statusCode), value/body: \(String(describing: response.result.value))"
                        }
                    } else { // no error code?
                        error_message = "download surveys: no status code?"
                    }
                case .failure: // general failure?
                    error_message = "download surveys - error: \(String(describing: response.error))"
                }
                
                if error_message != "" {
                    log.error(error_message)
                    AppEventManager.sharedInstance.logAppEvent(event: "survey_download", msg: error_message)
                }
            }
        )
    }

    // FIXME: this code got duplicated and the diverged. we should only have one checksurveys function
    // but instead we now have two. Both of these have been stripped of the promise architecture
    // and should retain their basic unique details.
    // downloadSurveys() was called from push notifications
    // checkSurveys() was called from timers
    // The todo here is merge them, which is non trivial because setActiveSurveys and updateActiveSurveys now do different things.
        
    /// there was a bunch of duplicated code, one version of the code was in appDelegate
    func downloadSurveys(surveyIds: [String], sentTime: TimeInterval = 0) {
        guard let study = self.currentStudy else {
            return
        }
        print("inside duplicate survey checker function 2")
        
        // this code always saved the study beforehand
        Recline.shared.save(study)
        
        // our logic requires those passed-in parameters,
        ApiManager.sharedInstance.makePostRequest(
            GetSurveysRequest(), completion_handler: { (response: DataResponse<String>) in
                var error_message = ""
                switch response.result {
                case .success:
                    if let statusCode = response.response?.statusCode {
                        // valid 200 range response
                        if statusCode >= 200 && statusCode < 300 {
                            let body_response = BodyResponse(body: response.result.value)
                            if let body_string = body_response.body {
                                if let newSurveys: [Survey] = Mapper<Survey>().mapArray(JSONString: body_string) {
                                    // we have survey data!
                                    study.surveys = newSurveys
                                    Recline.shared.save(study)
                                } else {
                                    error_message = "download surveys: \(response) - but body was nil"
                                }
                            }
                        } else { // all non-200 error codes
                            error_message = "download surveys: statuscode: \(statusCode), value/body: \(String(describing: response.result.value))"
                        }
                    } else { // no error code?
                        error_message = "download surveys: no status code?"
                    }
                case .failure: // general failure?
                    error_message = "download surveys - error: \(String(describing: response.error))"
                }
                
                // log app event if it couldn't hit the server
                if error_message != "" {
                    log.error(error_message)
                    AppEventManager.sharedInstance.logAppEvent(event: "survey_download", msg: error_message)
                }
                
                // even if we didn't get new surveys we need to call setActiveSurveys with the survey ids
                self.setActiveSurveys(surveyIds: surveyIds, sentTime: sentTime)
            }
        )
    }
    
    /// Queries the server for new study settings, hand off to completion handler
    func updateDeviceSettings() {
        // assert that these are instantiated
        guard let _ = self.currentStudy, let _ = self.currentStudy?.studySettings else {
            return
        }
        // make the post request, convert to json, convert to a JustStudySettings mapper
        ApiManager.sharedInstance.makePostRequest(
            UpdateDeviceSettingsRequest(), completion_handler: self.updateSettingsCompletionHandler)
    }

    /// callback for the updateDeviceSettings function, handles output of the post request, determines if we have any input data.
    func updateSettingsCompletionHandler(response: DataResponse<String>) {
        var error_message = ""
        
        // this could be cleaned up, but don't bother? it is tested and works.
        // All the error cases are "fine", we just try again later regardless of current success,
        // so we only print the error type.
        switch response.result {
        case .success:
            if let statusCode = response.response?.statusCode {
                if statusCode >= 200 && statusCode < 300 {
                    // 200 codes
                    let body_response = BodyResponse(body: response.result.value)
                    if let body_string = body_response.body {
                        // use the custom-purpose JustStudySettings class
                        if let newSettings: JustStudySettings = Mapper<JustStudySettings>().map(JSONString: body_string) {
                            self.updateSettings(newSettings: newSettings)
                        } else {
                            error_message = "update settings response: \(response) - but body was nil"
                        }
                    }
                } else {
                    // all other status codes
                    error_message = "update settings response: \(response) , statuscode: \(statusCode), value/body: \(String(describing: response.result.value))"
                }
            } else {
                // no status code
                error_message = "update settings response: \(response) - no status code?"
            }
        case .failure:
            // general failure
            error_message = "update settings response: \(response) - error: \(String(describing: response.error))"
        }
        
        if error_message != "" {
            log.error(error_message)
        }
    }
    
    /// This abomination of a function updates study settings if they have changed
    func updateSettings(newSettings: JustStudySettings) {
        // Check EVERY SETTING, record if anything changed, assign any new values
        var anything_changed: Bool = false
        
        // TODO: find a way to make this introspective (BUT SAFE) and less verbose.
        // I encountered problems using anything other than "self.currentStudy?.studySettings?.accelerometer"
        // to access and update the study settings for the device
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
        
        // accedentally tested it like this outside of if anything_changed, it's fine.
        Recline.shared.save(self.currentStudy!)
        
        // if anything changed, reset all data services.
        if anything_changed {
            self.prepareDataServices()
        }
    }
    
    /// This function always runs on the POST_UPLOAD_QUEUE
    /// Beiwe servers only respond with statuscodes on data upload. 200 means it was uploaded
    /// and we should delete the file, everything else means it didn't work and we should try again.
    func uploadAttemptResponseHandler(
        _ dataResponse: DataResponse<String>, filename: String, filePath: URL
    ) {
        var error_message = ""
        switch dataResponse.result {
        case .success:
            if let statusCode = dataResponse.response?.statusCode {
                var body_response_string = BodyResponse(body: dataResponse.result.value).body ?? "(no message)"
                if body_response_string == "" { body_response_string = "(no message)" }
                
                if statusCode >= 200 && statusCode < 300 {
                    print("Success uploading: \(filename) with message '\(body_response_string)'.")
                    AppEventManager.sharedInstance.logAppEvent(
                        event: "uploaded", msg: "Uploaded data file", d1: filename)
                    AppEventManager.sharedInstance.logAppEvent(
                        event: "upload_complete", msg: "Upload Complete")
                    self.currentStudy!.lastUploadSuccess = Int64(NSDate().timeIntervalSince1970)
                    Recline.shared.save(self.currentStudy!)
                    
                    do {
                        try FileManager.default.removeItem(at: filePath) // ok I guess this can fail...?
                    } catch {
                        let minipath = filePath.path.split(separator: "/").last!
                        
                        // this seems to happen whenever we have overlapping runs of uploading the same file.
                        print("Error deleting file '\(minipath)': \(error) (wtaf)")
                        // fatalError("could not delete a file??")
                    }
                    
                } else {
                    // non-200 status codes
                    error_message = "bad statuscode: \(statusCode) for file \(filename) with message '\(body_response_string)'"
                }
            } else {
                error_message = "upload failed - no status code or .failure case? for file \(filename)"
            }
        case .failure:
            // this case triggers when there are normal kinds of errors like a timeout.
            error_message = "upload ERROR: \(String(describing: dataResponse.error)) for file \(filename)"
        }
        
        if error_message != "" {
            print(error_message)
        }
        
        // there should REALLY only be one of these but just in case we will do all of them
        self.files_in_flight.removeAll(where: { $0 == filename })
    }
    
    /// business logic of the upload.
    /// processOnly means don't upload (it's based on reachability)
    func upload() {
        log.info("Checking for uploads...")
        DataStorageManager.sharedInstance.prepareForUpload()
        
        // if we can't enumerate files, that's insane, crash.
        let fileEnumerator: FileManager.DirectoryEnumerator =
            FileManager.default.enumerator(atPath: DataStorageManager.uploadDataDirectory().path)!
        var filesToProcess: [String] = []
        
        // loop over all and check if each file can be uploaded, assemble the list.
        while let filename = fileEnumerator.nextObject() as? String {
            if DataStorageManager.sharedInstance.isUploadFile(filename) {
                if self.files_in_flight.contains(filename) {
                    let minipath = filename.split(separator: "/").last!
                    print("skipping \(minipath) because its already being uploaded right now")
                    continue
                }
                filesToProcess.append(filename)
            }
        }
        
        for filename in filesToProcess {
            let filePath: URL = DataStorageManager.uploadDataDirectory().appendingPathComponent(filename)
            let uploadRequest = UploadRequest(fileName: filename, filePath: filePath.path)
            
            // do an upload - this does not block. it dispatches the upload operation onto the
            // AlamoFire root queue, and then eventually our callbacks get called.
            ApiManager.sharedInstance.makeMultipartUploadRequest(
                uploadRequest,
                file: filePath,
                completionQueue: POST_UPLOAD_QUEUE,
                httpSuccessCompletionHandler: { (dataResponse: DataResponse<String>) in
                    self.uploadAttemptResponseHandler(dataResponse, filename: filename, filePath: filePath)
                },
                encodingErrorHandler: { (error: Error) in
                    AppEventManager.sharedInstance.logAppEvent(
                        event: "upload_file_failed", msg: "Failed Uploaded data file", d1: filename)
                    log.error("Encoding error?: \(error)")
                    
                    // ok we will MINIMIZE the impact of this to once-per-app-launch by just never
                    // removing it from files_in_flight.
                    
                    // fatalError("we need to find a way to report these? \(error)")
                }
            )
            self.files_in_flight.append(filename)
            print("upload for \(filename) dispatched")
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
