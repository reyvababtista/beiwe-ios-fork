import CoreMotion
import Crashlytics
import EmitterKit
import Fabric
import Firebase
import Foundation
import PromiseKit
import ReachabilitySwift
import ResearchKit
import Sentry
import UIKit
import XCGLogger

let log = XCGLogger(identifier: "advancedLogger", includeDefaultDestinations: false)

extension String: LocalizedError {
    public var errorDescription: String? { return self }
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, CLLocationManagerDelegate {
    // dev stuff
    var transition_count = 0
    let debugEnabled = false

    // constants
    let gcmMessageIDKey = "gcm.message_id"

    // ui stuff
    var window: UIWindow? // this needs to be present according to docs
    var storyboard: UIStoryboard?
    var currentRootView: String? = "launchScreen"

    // app capability stuff (why do these need to be here? at all?
    let motionManager = CMMotionManager()
    var reachability: Reachability? // tells us about our network access
    
    var canOpenTel = false
    var locationPermission = false
    let locManager: CLLocationManager = CLLocationManager()

    // app state
    var isLoggedIn: Bool = false
    var timeEnteredBackground: Date?

    // this is a weird location for an object, its used in powerstatemanager, unclear why this is here.
    let lockEvent = EmitterKit.Event<Bool>()
    
    func setupLogging() {
        // Create a destination for the system console log (via NSLog), add the destination to the logger
        let systemLogDestination = AppleSystemLogDestination(owner: log, identifier: "advancedLogger.systemLogDestination")
        systemLogDestination.outputLevel = self.debugEnabled ? .debug : .warning
        systemLogDestination.showLogIdentifier = true
        systemLogDestination.showFunctionName = true
        systemLogDestination.showThreadName = true
        systemLogDestination.showLevel = true
        systemLogDestination.showFileName = true
        systemLogDestination.showLineNumber = true
        systemLogDestination.showDate = true
        log.add(destination: systemLogDestination)
    }

    func appStartLog() {
        print("AppUUID: \(PersistentAppUUID.sharedInstance.uuid)")
        let uiDevice = UIDevice.current
        // let modelVersionId = UIDevice.current.model + "/" + UIDevice.current.systemVersion  // this used to be a (completely usused class variable)
        print("name: \(uiDevice.name)")
        print("systemName: \(uiDevice.systemName)")
        print("systemVersion: \(uiDevice.systemVersion)")
        print("model: \(uiDevice.model)")
        print("platform: \(platform())")
    }

    /// starts reachability
    func initializeReachability() {
        do {
            self.reachability = Reachability()
            try self.reachability!.startNotifier()
        } catch {
            print("Unable to create or start Reachability")
        }
    }

    func printLoadedStudyInfo() {
        print("\n\n\n")
        print("patient id: '\(String(describing: ApiManager.sharedInstance.patientId))'")
        print("fcmToken: '\(String(describing: ApiManager.sharedInstance.fcmToken))'")
        print("patientId: '\(String(describing: ApiManager.sharedInstance.patientId))'")
        print("customApiUrl: '\(String(describing: ApiManager.sharedInstance.customApiUrl))'")
        print("baseApiUrl: '\(String(describing: ApiManager.sharedInstance.baseApiUrl))'")
        print("firebase app: '\(String(describing: FirebaseApp.app()))'")
        print("\n\n\n")
    }

    static func sharedInstance() -> AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }

    /// The AppDelegate started function
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // initialize Sentry IMMEDIATELY
        self.setupSentry()
        self.setupLogging()
        // setupCrashLytics()  // not currently using crashlytics
        AppEventManager.sharedInstance.didLaunch(launchOptions: launchOptions)
        // appStartLog()  // this is very verbose
        self.initializeReachability()
        self.initializeUI()

        // determine whether phone call bump is available (should be true ios 10+? or is there a permission you have to ask for?)
        self.canOpenTel = UIApplication.shared.canOpenURL(URL(string: "tel:6175551212")!)

        // Start the database, eg LOAD STUDY STUFF
        Recline.shared.open().then { (_: Bool) -> Promise<Bool> in
            print("Database opened")
            return StudyManager.sharedInstance.loadDefaultStudy()
        }.done { (_: Bool) in
            // IF A NOTIFICATION WAS RECEIVED while app was in killed state there will be launch options!
            if launchOptions != nil {
                let userInfoDictionary = launchOptions?[UIApplication.LaunchOptionsKey.remoteNotification] as? Dictionary<AnyHashable, Any>
                if userInfoDictionary != nil {
                    self.handleSurveyNotification(userInfo: userInfoDictionary!)
                }
            }
            // get any (delivered) notifications
            UNUserNotificationCenter.current().getDeliveredNotifications { (notifications: [UNNotification]) in
                for notification in notifications {
                    self.handleSurveyNotification(userInfo: notification.request.content.userInfo)
                }
            }
            // okay we currently are removing notifications, not ideal.
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            self.transitionToLoadedAppState() // transition to loaded app state
        }.catch { (_: Error) in
            print("Database open failed, probably should just crash the app tbh")
        }

        self.firebaseLoop()
        return true
    }

    /// anything that depends on app state at initialization time needs to go after this has run
    func transitionToLoadedAppState() {
        self.transition_count += 1
        print("transitionToLoadedAppState incremented to \(self.transition_count)")

        if let currentStudy = StudyManager.sharedInstance.currentStudy {
            if currentStudy.participantConsented {
                StudyManager.sharedInstance.startStudyDataServices()
            }
            
            if !self.isLoggedIn {
                // Load up the log in view
                self.changeRootViewControllerWithIdentifier("login")
            } else {
                // We are logged in, so if we've completed onboarding load main interface, Otherwise continue onboarding.
                if currentStudy.participantConsented {
                    self.changeRootViewControllerWithIdentifier("mainView")
                } else {
                    self.changeRootViewController(ConsentManager().consentViewController)
                }
            }
            self.initializeFirebase() // this is safe to call
        } else {
            // If there is no study loaded, then it's obvious.  We need the onboarding flow from the beginning.
            self.changeRootViewController(OnboardingManager().onboardingViewController)
        }
    }

    /// Compares password to the stored password, but also sets password if there is no password due a bug where
    /// the app (or keychain?) up and forgets the password. This app doesn't actually have any data to show the user,
    /// the password is for show/getting the app through the original IRB/participant security theater.
    func checkPasswordAndLogin(_ password: String) -> Bool {
        // uncomment these lines to make login always succeed, useful for debugging patterns.
        // ApiManager.sharedInstance.password = PersistentPasswordManager.sharedInstance.passwordForStudy() ?? ""
        // self.isLoggedIn = true
        // return true
        
        // 2.2.1: there was a bug where access of passwordForStudy using the optional-force operoter (then line 169), e.g.
        //    PersistentPasswordManager.sharedInstance.passwordForStudy()!
        // would error as null. Using the optional coalescing operator should fix it
        var storedPassword: String = PersistentPasswordManager.sharedInstance.passwordForStudy() ?? ""
        // print("incoming password: '\(password)'")
        // print("current password: '\(storedPassword)'")

        // If there is somehow a situation where no stored password is set, take the new password and set it.
        //  THIS EXISTS PURELY TO FIX A THEORETICAL BUG WHERE PASSWORDS WERE SOMEHOW RESET,
        //  BUT THE SOURCE OF THAT BUG WAS PROBABLY A CHANGE OF APP BUILD CREDENTIALS.
        if storedPassword.isEmpty {
            PersistentPasswordManager.sharedInstance.storePassword(password)
            storedPassword = PersistentPasswordManager.sharedInstance.passwordForStudy()!
        }
        
        if password == storedPassword {
            ApiManager.sharedInstance.password = storedPassword
            self.isLoggedIn = true
            return true
        }
        return false
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////// APPLICATION WILL X ///////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    func applicationWillEnterForeground(_ application: UIApplication) {
        print("applicationWillEnterForeground")
        // Called as part of the transition from the background to the inactive (Eli does not know who wrote "inactive") state.
        // here you can undo many of the changes made on entering the background.

        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications: [UNNotification]) in
            for notification in notifications {
                self.handleSurveyNotification(userInfo: notification.request.content.userInfo)
            }
        }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        if let timeEnteredBackground = timeEnteredBackground,
           let currentStudy = StudyManager.sharedInstance.currentStudy,
           let studySettings = currentStudy.studySettings,
           isLoggedIn == true {
            let loginExpires = timeEnteredBackground.addingTimeInterval(Double(studySettings.secondsBeforeAutoLogout))
            if loginExpires.compare(Date()) == ComparisonResult.orderedAscending {
                // expired.  Log 'em out
                self.isLoggedIn = false
                self.transitionToLoadedAppState()
            }
        } else {
            self.isLoggedIn = false
        }
    }

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        print("applicationWillFinishLaunchingWithOptions")
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        print("applicationWillTerminate")
        AppEventManager.sharedInstance.logAppEvent(event: "terminate", msg: "Application terminating")
        
        let dispatchGroup = DispatchGroup() // I don't know what this multithreading control tool is
        dispatchGroup.enter()
        // call stop on the study, then... leave the dispatch group, which I think means wait for everything to finish (or crash)
        StudyManager.sharedInstance.stop().done(on: DispatchQueue.global(qos: .default)) { (_: Bool) in
            dispatchGroup.leave()
        }.catch(on: DispatchQueue.global(qos: .default)) { (_: Error) in
            dispatchGroup.leave()
        }
        dispatchGroup.wait() // block until the dispatch group is... finished? until the promise is finished?
        print("applicationWillTerminate exiting")
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
        print("applicationWillResignActive")
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////// APPLICATION DID X ////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        print("applicationDidBecomeActive")
        AppEventManager.sharedInstance.logAppEvent(event: "foreground", msg: "Application entered foreground")

        // Send FCM Token everytime the app launches
        if ApiManager.sharedInstance.patientId != "" /* && FirebaseApp.app() != nil*/ {
            if let token = Messaging.messaging().fcmToken {
                self.sendFCMToken(fcmToken: token)
            }
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        print("applicationDidEnterBackground")
        self.timeEnteredBackground = Date()
        AppEventManager.sharedInstance.logAppEvent(event: "background", msg: "Application entered background")
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        print("applicationDidReceiveMemoryWarning")
        AppEventManager.sharedInstance.logAppEvent(event: "memory_warn", msg: "Application received memory warning")
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        print("applicationProtectedDataDidBecomeAvailable")
        self.lockEvent.emit(false)
        AppEventManager.sharedInstance.logAppEvent(event: "unlocked", msg: "Phone/keystore unlocked")
    }

    func applicationProtectedDataWillBecomeUnavailable(_ application: UIApplication) {
        print("applicationProtectedDataWillBecomeUnavailable")
        self.lockEvent.emit(true)
        AppEventManager.sharedInstance.logAppEvent(event: "locked", msg: "Phone/keystore locked")
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////// PERMISSIONS //////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// this function gets called when CLAuthorization status changes
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            // If status has not yet been determied, ask for authorization
            manager.requestAlwaysAuthorization()
            break
        case .authorizedWhenInUse:
            // If authorized when in use
            self.locationPermission = false
            break
        case .authorizedAlways:
            // If always authorized
            self.locationPermission = true
            break
        case .restricted:
            // If restricted by e.g. parental controls. User can't enable Location Services
            self.locationPermission = false
            break
        case .denied:
            // If user denied your app access to Location Services, but can grant access from Settings.app
            self.locationPermission = false
            break
        default:
            break
        }
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////// REAL NOTIFICATION CODE ///////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for notifications: \(error.localizedDescription)")
        AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Failed to register for notifications: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
        // If you are receiving a notification message while your app is in the background,
        // this callback will not be fired until the user taps on the notification launching the application.

        print("Background push notification received")
        AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Background push notification received")
        // Print message ID, full message.
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID: \(messageID)")
        }
        print(userInfo)

        // if the notification is for a survey
        if userInfo["survey_ids"] != nil {
            self.handleSurveyNotification(userInfo: userInfo)
        }
    }

    // called when receiving notification while app is in foreground
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // If you are receiving a notification message while your app is in the background,
        // this callback will not be fired till the user taps on the notification launching the application.

        print("Foreground push notification received")
        AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Foreground push notification received")
        // Print message ID, full message.
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID: \(messageID)")
        }
        print(userInfo)

        // if the notification is for a survey
        if userInfo["survey_ids"] != nil {
            self.handleSurveyNotification(userInfo: userInfo)
        }

        completionHandler(UIBackgroundFetchResult.newData)
    }
    
    /// code to run when receivinga push notification with surveys in it. Called from an AppDelegate extension.
    /// Checks for any new surveys on the server and pops any survey notifications indicated in the push notificattion
    func handleSurveyNotification(userInfo: Dictionary<AnyHashable, Any>) {
        // return if nothing found
        guard let surveyIdsString = userInfo["survey_ids"] else {
            print("no surveyIds found, checking for new surveys anyway.")
            self.downloadSurveys(surveyIds: [])
            return
        }
        
        // extract survey ids to force-display
        AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Received notification while app was killed")
        let surveyIds: [String] = self.jsonToSurveyIdArray(json: surveyIdsString as! String)
        
        // downloadSurveys calls setActiveSurveys, even if it errors/fails. We always want to download the most recent survey information.
        // (old versions of the backend don't supply the sent_time key)
        if let sentTimeString = userInfo["sent_time"] as! String? {
            self.downloadSurveys(surveyIds: surveyIds, sentTime: self.stringToTimeInterval(timeString: sentTimeString))
        } else {
            self.downloadSurveys(surveyIds: surveyIds)
        }
    }
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////// MISC BEIWE STUFF /////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // converting sent_time string into a TimeInterval
    func stringToTimeInterval(timeString: String) -> TimeInterval {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX") // set locale to reliable US_POSIX
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let sentTime = dateFormatter.date(from: timeString)!
        return sentTime.timeIntervalSince1970
    }

    // converts json string to an array of strings
    func jsonToSurveyIdArray(json: String) -> [String] {
        let surveyIds = try! JSONDecoder().decode([String].self, from: Data(json.utf8))
        for surveyId in surveyIds {
            if !(StudyManager.sharedInstance.currentStudy?.surveyExists(surveyId: surveyId) ?? false) {
                print("Received notification for new survey \(surveyId)")
                AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Received notification for new survey \(surveyId)")
            } else {
                print("Received notification for survey \(surveyId)")
                AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Received notification for survey \(surveyId)")
            }
        }
        return surveyIds
    }

    // downloads all of the surveys in the study
    func downloadSurveys(surveyIds: [String], sentTime: TimeInterval = 0) {
        guard let study = StudyManager.sharedInstance.currentStudy else {
            print("Could not find study")
            return
        }
        Recline.shared.save(study).then { (_: Study) -> Promise<([Survey], Int)> in
            let surveyRequest = GetSurveysRequest()
            print("Requesting surveys")
            return ApiManager.sharedInstance.arrayPostRequest(surveyRequest)
        }.then { (surveys: [Survey], _: Int) -> Promise<Void> in
            study.surveys = surveys
            return Recline.shared.save(study).asVoid()
        }.done { (_: Void) in
            self.setActiveSurveys(surveyIds: surveyIds, sentTime: sentTime)
        }.catch { (error: Error) in
            print("Error downloading surveys: \(error)")
            AppEventManager.sharedInstance.logAppEvent(event: "survey_download", msg: "Error downloading surveys: \(error)")
            // try setting the active surveys anyway, even if download failed, can still use previously downloaded surveys
            self.setActiveSurveys(surveyIds: surveyIds, sentTime: sentTime)
        }
    }

    /// sets the active survey on the main app page, force-enables any specified surveys.
    func setActiveSurveys(surveyIds: [String], sentTime: TimeInterval = 0) {
        guard let study = StudyManager.sharedInstance.currentStudy else {
            return
        }
        
        // force reload all always-available surveys and any passed in surveys
        for survey in study.surveys {
            let surveyId = survey.surveyId!
            let from_notification = surveyIds.contains(surveyId)
            if from_notification || survey.alwaysAvailable {
                let activeSurvey = ActiveSurvey(survey: survey)
                // when we receive a notification we need to record that, this is used to sort surveys on the main screen (I think)
                if from_notification {
                    activeSurvey.received = sentTime
                    if let surveyType = survey.surveyType {
                        // I don't know what study.receivedAudioSurveys and study.receivedTrackingSurveys are
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
        Recline.shared.save(study).catch { (_: Error) in
            print("Failed to save study after processing surveys")
        }

        // set badge number
        UIApplication.shared.applicationIconBadgeNumber = study.activeSurveys.count
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////// Firebase STUFF ///////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    func firebaseLoop() {
        print("firebaseLoop called")
        // Thue app cannot register with firebase until it gets a token, which only occurs at registration time, and it needs access to the appIelegate
        // This must be called after FirebaseApp.configure(), so we dispatch it and wait until the app is initialized from RegistrationViewController...
        DispatchQueue.global(qos: .background).async {
            while !StudyManager.real_study_loaded {
                // print("waiting for study to load")
                sleep(1)
            }
            while FirebaseApp.app() == nil { // FirebaseApp.app() emits the firebase spam log
                sleep(1)
            }
            Messaging.messaging().delegate = self
            UNUserNotificationCenter.current().delegate = self
            // App crashes if this isn't called on main thread
            DispatchQueue.main.async {
                // application.registerForRemoteNotifications()
                UIApplication.shared.registerForRemoteNotifications()
                if let token = Messaging.messaging().fcmToken {
                    self.sendFCMToken(fcmToken: token)
                }
            }
        }
    }

    func initializeFirebase() {
        // safely checks whether to start firebase.
        if ApiManager.sharedInstance.patientId != "" && FirebaseApp.app() == nil {
            self.checkFirebaseCredentials()
            let token = Messaging.messaging().fcmToken
            self.sendFCMToken(fcmToken: token ?? "")
        }
    }
    
    func configureFirebase(studySettings: StudySettings) {
        let options = FirebaseOptions(googleAppID: studySettings.googleAppID, gcmSenderID: studySettings.gcmSenderID)
        options.apiKey = studySettings.apiKey
        options.projectID = studySettings.projectID
        options.bundleID = studySettings.bundleID
        options.clientID = studySettings.clientID
        options.databaseURL = studySettings.databaseURL
        options.storageBucket = studySettings.storageBucket
        // firebase is pretty noisy, so we can squash the excess. (this does not squash the
        // "The default Firebase app has not yet been configured" error, wish it did.)
        FirebaseConfiguration.shared.setLoggerLevel(.min)

        // initialize Firebase on the main thread
        DispatchQueue.main.async {
            // this used to depend on what version of beiwe (with or without pre-filled server url)
            FirebaseApp.configure(options: options)
            print("Configured Firebase")
        }
    }

    func checkFirebaseCredentials() {
        // case: unregistered - return early
        guard let studySettings = StudyManager.sharedInstance.currentStudy?.studySettings else {
            print("Study not found")
            AppEventManager.sharedInstance.logAppEvent(
                event: "push_notification", msg: "Unable to configure Firebase App. No study found.")
            return
        }
        // case: the registered server did not have push notification credentials
        if studySettings.googleAppID == "" {
            return
        }
        // Configure firebase
        if FirebaseApp.app() == nil {
            self.configureFirebase(studySettings: studySettings)
            AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Registered for push notifications with Firebase")
        }
    }

    func sendFCMToken(fcmToken: String) {
        print("FCM Token: \(fcmToken)")
        if fcmToken != "" {
            let fcmTokenRequest = FCMTokenRequest(fcmToken: fcmToken)
            ApiManager.sharedInstance.makePostRequest(fcmTokenRequest).catch { (error: Error) in
                print("Error registering FCM token: \(error)")
                AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Error registering FCM token: \(error)")
            }
        }
    }
    
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////// UI STUFF ///////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    func initializeUI() {
        // some ui stuff
        let rkAppearance: UIView = UIView.appearance(whenContainedInInstancesOf: [ORKTaskViewController.self])
        rkAppearance.tintColor = AppColors.tintColor
        self.storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        self.window = UIWindow(frame: UIScreen.main.bounds)
        self.window?.rootViewController = UIStoryboard(
            name: "LaunchScreen", bundle: Bundle.main).instantiateViewController(withIdentifier: "launchScreen")
        self.window!.makeKeyAndVisible()
    }

    func changeRootViewControllerWithIdentifier(_ identifier: String!) {
        if identifier == self.currentRootView {
            return
        }
        let desiredViewController: UIViewController = (self.storyboard?.instantiateViewController(withIdentifier: identifier))!
        self.changeRootViewController(desiredViewController, identifier: identifier)
    }

    func changeRootViewController(_ desiredViewController: UIViewController, identifier: String? = nil) {
        self.currentRootView = identifier
        let snapshot: UIView = (self.window?.snapshotView(afterScreenUpdates: true))!
        desiredViewController.view.addSubview(snapshot)
        self.window?.rootViewController = desiredViewController
        UIView.animate(withDuration: 0.3, animations: { () in
            snapshot.layer.opacity = 0
            snapshot.layer.transform = CATransform3DMakeScale(1.5, 1.5, 1.5)
        }, completion: { (_: Bool) in
            snapshot.removeFromSuperview()
        })
    }

    func displayCurrentMainView() {
        var view: String
        if let _ = StudyManager.sharedInstance.currentStudy {
            view = "initialStudyView"
        } else {
            view = "registerView"
        }
        self.window = UIWindow(frame: UIScreen.main.bounds)
        self.window?.rootViewController = self.storyboard!.instantiateViewController(withIdentifier: view) as UIViewController?
        self.window!.makeKeyAndVisible()
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////// CRASHLYTICS STUFF ////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    // func setupCrashLytics() {
    //     Fabric.with([Crashlytics.self])
    //     let crashlyticsLogDestination = XCGCrashlyticsLogDestination(owner: log, identifier: "advancedlogger.crashlyticsDestination")
    //     crashlyticsLogDestination.outputLevel = .debug
    //     crashlyticsLogDestination.showLogIdentifier = true
    //     crashlyticsLogDestination.showFunctionName = true
    //     crashlyticsLogDestination.showThreadName = true
    //     crashlyticsLogDestination.showLevel = true
    //     crashlyticsLogDestination.showFileName = true
    //     crashlyticsLogDestination.showLineNumber = true
    //     crashlyticsLogDestination.showDate = true
    //
    //     // Add the destination to the logger
    //     log.add(destination: crashlyticsLogDestination)
    //     log.logAppDetails()
    // }
    //
    // // completely disabled, does nothing
    // func setDebuggingUser(_ username: String) {
    //     // TODO: Use the current user's information
    //     // You can call any combination of these three methods
    //     // Crashlytics.sharedInstance().setUserEmail("user@fabric.io")
    //     // Crashlytics.sharedInstance().setUserIdentifier(username)
    //     // Crashlytics.sharedInstance().setUserName("Test User")
    // }
    //
    // func crash() {
    //     Crashlytics.sharedInstance().crash()
    // }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////// SENTRY STUFF ////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    func setupSentry() {
        // loads sentry key, prints an error if it doesn't work.
        do {
            let dsn = Configuration.sharedInstance.settings["sentry-dsn"] as? String ?? "dev"
            if dsn == "release" {
                Client.shared = try Client(dsn: SentryKeys.release_dsn)
            } else if dsn == "dev" {
                Client.shared = try Client(dsn: SentryKeys.development_dsn)
            } else {
                throw "Invalid Sentry configuration"
            }
            try Client.shared?.startCrashHandler()
        } catch let error {
            print("\(error)")
        }
    }
}

// [START ios_10_message_handling]
@available(iOS 10, *)
extension AppDelegate: UNUserNotificationCenterDelegate {
    func printMessageInfo(_ notificationRequest: UNNotificationRequest) {
        let userInfoDict: [AnyHashable: Any] = notificationRequest.content.userInfo
        if let messageID = userInfoDict[gcmMessageIDKey] {
            print("Message ID: \(messageID)")
        }
        print(userInfoDict)
    }

    func handleAnySurveys(_ notificationRequest: UNNotificationRequest) {
        // grab the survey ids, call if the notification is for a survey
        let userInfoDict: [AnyHashable: Any] = notificationRequest.content.userInfo
        if userInfoDict["survey_ids"] != nil {
            self.handleSurveyNotification(userInfo: userInfoDict)
        }
    }

    // Receive displayed notifications for iOS 10 devices.
    // Is called when receiving a notification while app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("Foreground push notification received in extension")
        AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Foreground push notification received")
        self.printMessageInfo(notification.request)
        self.handleAnySurveys(notification.request)
        completionHandler([]) // Change to preferred presentation option
    }

    // Is called when tapping on notification when app is in background
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("Background push notification received in extension")
        AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Background push notification received")
        self.printMessageInfo(response.notification.request)
        self.handleAnySurveys(response.notification.request)
        completionHandler()
    }
}

// [END ios_10_message_handling]

extension AppDelegate: MessagingDelegate {
    // [START firebase refresh_token]
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String) {
        let dataDict: [String: String] = ["token": fcmToken]
        NotificationCenter.default.post(name: Notification.Name("FCMToken"), object: nil, userInfo: dataDict)
        // Note: This callback is fired at each app startup and whenever a new token is generated.

        // wait until user is registered to send FCM token, runs on background thread
        DispatchQueue.global(qos: .background).async {
            while ApiManager.sharedInstance.patientId == "" {
                sleep(1)
            }
            self.sendFCMToken(fcmToken: fcmToken)
        }
    }

    // [END refresh_token]

    // [START ios_10_data_message]
    // Receive data messages on iOS 10+ directly from FCM (bypassing APNs) when the app is in the foreground.
    // To enable direct data messages, you can set Messaging.messaging().shouldEstablishDirectChannel to true.
    func messaging(_ messaging: Messaging, didReceive remoteMessage: MessagingRemoteMessage) {
        print("Received data message: \(remoteMessage.appData)")
    }
    // [END ios_10_data_message]
}
