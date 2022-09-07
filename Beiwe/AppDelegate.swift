//
//  AppDelegate.swift
//  Beiwe
//
//  Created by Keary Griffin on 3/10/16.
//  Copyright © 2016 Rocketfarm Studios. All rights reserved.
//

import Sentry
import UIKit
import Fabric
import Crashlytics
import PromiseKit
import CoreMotion;
import ReachabilitySwift
import ResearchKit
import XCGLogger
import EmitterKit
import Foundation
import Firebase

let log = XCGLogger(identifier: "advancedLogger", includeDefaultDestinations: false)

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, CLLocationManagerDelegate {
    
    var window: UIWindow?
    var storyboard: UIStoryboard?;
    var modelVersionId = "";
    let motionManager = CMMotionManager();
    var reachability: Reachability?;
    var currentRootView: String? = "launchScreen";
    var isLoggedIn: Bool = false;
    var timeEnteredBackground: Date?;
    var canOpenTel = false;
    let debugEnabled  = _isDebugAssertConfiguration();
    let lockEvent = EmitterKit.Event<Bool>();
    let gcmMessageIDKey = "gcm.message_id"
    
    var locationPermission: Bool = false;
    // manager needed to ask for location permissions
    let locManager: CLLocationManager = CLLocationManager()
    
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        Fabric.with([Crashlytics.self])
        
        // Create a destination for the system console log (via NSLog)
        let systemLogDestination = AppleSystemLogDestination(owner: log, identifier: "advancedLogger.systemLogDestination")
        
        // Optionally set some configuration options
        systemLogDestination.outputLevel = debugEnabled ? .debug : .warning
        systemLogDestination.showLogIdentifier = false
        systemLogDestination.showFunctionName = false // true
        systemLogDestination.showThreadName = true
        systemLogDestination.showLevel = false // true
        systemLogDestination.showFileName = false // true
        systemLogDestination.showLineNumber = false // true
        systemLogDestination.showDate = true
        
        // Add the destination to the logger
        log.add(destination: systemLogDestination)
        
        let crashlyticsLogDestination = XCGCrashlyticsLogDestination(owner: log, identifier: "advancedlogger.crashlyticsDestination")
        crashlyticsLogDestination.outputLevel = .debug
        crashlyticsLogDestination.showLogIdentifier = false
        crashlyticsLogDestination.showFunctionName = false // true
        crashlyticsLogDestination.showThreadName = true
        crashlyticsLogDestination.showLevel = false // true
        crashlyticsLogDestination.showFileName = false // true
        crashlyticsLogDestination.showLineNumber = false // true
        crashlyticsLogDestination.showDate = true
        
        // Add the destination to the logger
        log.add(destination: crashlyticsLogDestination)
        
        
        log.info("applicationDidFinishLaunching")
        log.logAppDetails()
        
        AppEventManager.sharedInstance.didLaunch(launchOptions: launchOptions);
        
        do {
            reachability = try Reachability()
            try reachability!.startNotifier()
        } catch {
            log.error("Unable to create or start Reachability")
        }
        log.info("AppUUID: \(PersistentAppUUID.sharedInstance.uuid)");
        let uiDevice = UIDevice.current;
        modelVersionId = UIDevice.current.model + "/" + UIDevice.current.systemVersion;
        log.info("name: \(uiDevice.name)");
        log.info("systemName: \(uiDevice.systemName)");
        log.info("systemVersion: \(uiDevice.systemVersion)");
        log.info("model: \(uiDevice.model)");
        log.info("platform: \(platform())");
        
        canOpenTel = UIApplication.shared.canOpenURL(URL(string: "tel:6175551212")!);
        
        
        let rkAppearance = UIView.appearance(whenContainedInInstancesOf: [ORKTaskViewController.self])
        rkAppearance.tintColor = AppColors.tintColor;
        
        storyboard = UIStoryboard(name: "Main", bundle: Bundle.main);
        
        self.window = UIWindow(frame: UIScreen.main.bounds);
        self.window?.rootViewController = UIStoryboard(name: "LaunchScreen", bundle: Bundle.main).instantiateViewController(withIdentifier: "launchScreen");
        
        self.window!.makeKeyAndVisible()
        
        Recline.shared.open().then { _ -> Promise<Bool> in
            print("Database opened");
            return StudyManager.sharedInstance.loadDefaultStudy();
        }.done { _ -> Void in
            // if notification was received while app was in killed state, there will be launch options
            if launchOptions != nil{
                let userInfo = launchOptions?[UIApplication.LaunchOptionsKey.remoteNotification] as? Dictionary<AnyHashable, Any>
                if userInfo != nil {
                    self.handleSurveyNotification(userInfo: userInfo!)
                }
            }
            UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
                for notification in notifications {
                    self.handleSurveyNotification(userInfo: notification.request.content.userInfo)
                }
            }
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            self.transitionToCurrentAppState();
        }.catch { err -> Void in
            print("Database open failed.");
        }
        
        // initialize Sentry
        do {
            let dsn = Configuration.sharedInstance.settings["sentry-dsn"] as? String ?? "dev"
            if dsn == "release" {
                Client.shared = try Client(dsn: SentryKeys.release_dsn)
            }
            else if dsn == "dev" {
                Client.shared = try Client(dsn: SentryKeys.development_dsn)
            } else {
                throw "Invalid Sentry configuration"
            }
            try Client.shared?.startCrashHandler()
        } catch let error {
            print("\(error)")
        }
        
        // initialize Firebase only if it hasn't been initialized before and is after registration
        if (ApiManager.sharedInstance.patientId != "" && FirebaseApp.app() == nil) {
            checkFirebaseCredentials()
            let token = Messaging.messaging().fcmToken
            AppDelegate.sharedInstance().sendFCMToken(fcmToken: token ?? "")
        }
        
        // these lines need to be called after FirebaseApp.configure(), so we wait
        // until the app is initialized from RegistrationViewController
        DispatchQueue.global(qos: .background).async {
            while FirebaseApp.app() == nil {
                sleep(1)
            }
            Messaging.messaging().delegate = self
            UNUserNotificationCenter.current().delegate = self
            // App crashes if this isn't called on main thread
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
                if let token = Messaging.messaging().fcmToken {
                    self.sendFCMToken(fcmToken: token)
                }
            }
        }
        return true
    }
    
    func changeRootViewControllerWithIdentifier(_ identifier:String!) {
        if (identifier == currentRootView) {
            return;
        }
        let desiredViewController:UIViewController = (self.storyboard?.instantiateViewController(withIdentifier: identifier))!
        
        changeRootViewController(desiredViewController, identifier: identifier);
    }
    
    func changeRootViewController(_ desiredViewController: UIViewController, identifier: String? = nil) {
        currentRootView = identifier;
        
        let snapshot:UIView = (self.window?.snapshotView(afterScreenUpdates: true))!
        desiredViewController.view.addSubview(snapshot);
        
        self.window?.rootViewController = desiredViewController;
        
        UIView.animate(withDuration: 0.3, animations: {() in
            snapshot.layer.opacity = 0;
            snapshot.layer.transform = CATransform3DMakeScale(1.5, 1.5, 1.5);
        }, completion: {
            (value: Bool) in
            snapshot.removeFromSuperview();
        });
    }
    
    func transitionToCurrentAppState() {
        
        
        if let currentStudy = StudyManager.sharedInstance.currentStudy {
            if (currentStudy.participantConsented) {
                StudyManager.sharedInstance.startStudyDataServices();
            }
            if (!isLoggedIn) {
                // Load up the log in view
                changeRootViewControllerWithIdentifier("login");
            } else {
                // We are logged in, so if we've completed onboarding load main interface
                // Otherwise continue onboarding.
                if (currentStudy.participantConsented) {
                    changeRootViewControllerWithIdentifier("mainView");
                } else {
                    changeRootViewController(ConsentManager().consentViewController);
                }
                
            }
            
        } else {
            // If there is no study loaded, then it's obvious.  We need the onboarding flow
            // from the beginning.
            changeRootViewController(OnboardingManager().onboardingViewController);
        }
    }
    
    static func sharedInstance() -> AppDelegate{
        return UIApplication.shared.delegate as! AppDelegate
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
        log.info("applicationWillResignActive")
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        log.info("applicationDidEnterBackground")
        timeEnteredBackground = Date();
        AppEventManager.sharedInstance.logAppEvent(event: "background", msg: "Application entered background")
        
    }
    
    func checkPasswordAndLogin(_ password: String) -> Bool {
        if let storedPassword = PersistentPasswordManager.sharedInstance.passwordForStudy(), storedPassword.count > 0 {
            if (password == storedPassword) {
                ApiManager.sharedInstance.password = storedPassword;
                isLoggedIn = true;
                return true;
            }
            
        }
        
        return false;
        
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        log.info("applicationWillEnterForeground")
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
        print("ApplicationWillEnterForeground");

        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            for notification in notifications {
                self.handleSurveyNotification(userInfo: notification.request.content.userInfo)
            }
        }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        if let timeEnteredBackground = timeEnteredBackground, let currentStudy = StudyManager.sharedInstance.currentStudy, let studySettings = currentStudy.studySettings, isLoggedIn == true {
            let loginExpires = timeEnteredBackground.addingTimeInterval(Double(studySettings.secondsBeforeAutoLogout));
            if (loginExpires.compare(Date()) == ComparisonResult.orderedAscending) {
                // expired.  Log 'em out
                isLoggedIn = false;
                transitionToCurrentAppState();
            }
        } else {
            isLoggedIn = false;
        }
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        log.info("applicationDidBecomeActive")
        AppEventManager.sharedInstance.logAppEvent(event: "foreground", msg: "Application entered foreground")
        
        // Send FCM Token everytime the app launches
        if (ApiManager.sharedInstance.patientId != ""/* && FirebaseApp.app() != nil*/) {
            let token = Messaging.messaging().fcmToken
            if (token != nil) {
                sendFCMToken(fcmToken: token ?? "")
            }
        }
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        log.info("applicationWillTerminate")
        AppEventManager.sharedInstance.logAppEvent(event: "terminate", msg: "Application terminating")
        
        let dispatchGroup = DispatchGroup();
        
        dispatchGroup.enter()
        StudyManager.sharedInstance.stop().done(on: DispatchQueue.global(qos: .default)) { _ in
            dispatchGroup.leave()
        }.catch(on: DispatchQueue.global(qos: .default)) {_ in
            dispatchGroup.leave()
        }
        
        dispatchGroup.wait();
        log.info("applicationWillTerminate exiting")
    }
    
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        log.info("applicationDidReceiveMemoryWarning")
        AppEventManager.sharedInstance.logAppEvent(event: "memory_warn", msg: "Application received memory warning")
    }
    
    func displayCurrentMainView() {
        //
        
        var view: String;
        if let _ = StudyManager.sharedInstance.currentStudy {
            view = "initialStudyView";
        } else {
            view = "registerView";
        }
        self.window = UIWindow(frame: UIScreen.main.bounds)
        
        self.window?.rootViewController = storyboard!.instantiateViewController(withIdentifier: view) as UIViewController?;
        
        self.window!.makeKeyAndVisible()
        
    }
    
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        log.info("applicationWillFinishLaunchingWithOptions")
        return true;
        
    }
    
    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        log.info("applicationProtectedDataDidBecomeAvailable");
        lockEvent.emit(false);
        AppEventManager.sharedInstance.logAppEvent(event: "unlocked", msg: "Phone/keystore unlocked")
    }
    
    func applicationProtectedDataWillBecomeUnavailable(_ application: UIApplication) {
        log.info("applicationProtectedDataWillBecomeUnavailable");
        lockEvent.emit(true);
        AppEventManager.sharedInstance.logAppEvent(event: "locked", msg: "Phone/keystore locked")
        
    }
    /* Crashlytics functions -- future */
    
    func setDebuggingUser(_ username: String) {
        // TODO: Use the current user's information
        // You can call any combination of these three methods
        //Crashlytics.sharedInstance().setUserEmail("user@fabric.io")
        Crashlytics.sharedInstance().setUserIdentifier(username);
        //Crashlytics.sharedInstance().setUserName("Test User")
    }
    
    func crash() {
        Crashlytics.sharedInstance().crash()
    }
    
    // this function gets called when CLAuthorization status changes
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            // If status has not yet been determied, ask for authorization
            manager.requestAlwaysAuthorization()
            break
        case .authorizedWhenInUse:
            // If authorized when in use
            locationPermission = false
            break
        case .authorizedAlways:
            // If always authorized
            locationPermission = true
            break
        case .restricted:
            // If restricted by e.g. parental controls. User can't enable Location Services
            locationPermission = false
            break
        case .denied:
            // If user denied your app access to Location Services, but can grant access from Settings.app
            locationPermission = false
            break
        default:
            break
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.error("Failed to register for notifications: \(error.localizedDescription)")
        AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Failed to register for notifications: \(error.localizedDescription)")
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
        // If you are receiving a notification message while your app is in the background,
        // this callback will not be fired till the user taps on the notification launching the application.
        
        log.info("Background push notification received")
        AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Background push notification received")
        // Print message ID.
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID: \(messageID)")
        }
        
        // Print full message.
        print(userInfo)
        
        // if the notification is for a survey
        if userInfo["survey_ids"] != nil {
            handleSurveyNotification(userInfo: userInfo)
        }
    }
    
    // called when receiving notification while app is in foreground
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // If you are receiving a notification message while your app is in the background,
        // this callback will not be fired till the user taps on the notification launching the application.
        
        log.info("Foreground push notification received")
        AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Foreground push notification received")
        // Print message ID.
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID: \(messageID)")
        }
        
        // Print full message.
        print(userInfo)
        
        // if the notification is for a survey
        if userInfo["survey_ids"] != nil {
            handleSurveyNotification(userInfo: userInfo)
        }
        
        completionHandler(UIBackgroundFetchResult.newData)
    }
    
    func checkFirebaseCredentials() {
        guard let studySettings = StudyManager.sharedInstance.currentStudy?.studySettings else {
            log.error("Study not found")
            AppEventManager.sharedInstance.logAppEvent(
                event: "push_notification", msg: "Unable to configure Firebase App. No study found.")
            return
        }
        
        if (studySettings.googleAppID == "") {
            guard let password = PersistentPasswordManager.sharedInstance.passwordForStudy() else {
                log.error("could not retrieve password")
                return
            }
            let registerStudyRequest = RegisterStudyRequest(
                patientId: ApiManager.sharedInstance.patientId, phoneNumber: "NOT_SUPPLIED", newPassword: password)
            
            ApiManager.sharedInstance.makePostRequest(registerStudyRequest).then {
                (studySettings, _) -> Promise<Void> in
                print(studySettings)
                // testing response body values to ensure we hit the correct server and not some random server
                // that happened to return a 200
                guard studySettings.clientPublicKey != nil else {
                    throw RegisterViewController.RegistrationError.incorrectServer
                }
                if (FirebaseApp.app() == nil && studySettings.googleAppID != "") {
                    self.configureFirebase(studySettings: studySettings)
                    AppEventManager.sharedInstance.logAppEvent(
                        event: "push_notification", msg: "Registered for push notifications with Firebase")
                }
                return Promise()
            }
        } else if (FirebaseApp.app() == nil) {
            self.configureFirebase(studySettings: studySettings)
            AppEventManager.sharedInstance.logAppEvent(
                event: "push_notification", msg: "Registered for push notifications with Firebase")
        }
    }

    func handleSurveyNotification(userInfo: Dictionary<AnyHashable, Any>) {
        guard let surveyIdsString = userInfo["survey_ids"] else {
            log.error("no surveyIds found")
            return
        }
        AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Received notification while app was killed")
        let surveyIds = jsonToSurveyIdArray(json: surveyIdsString as! String)
        if let sentTimeString = userInfo["sent_time"] as! String?{
            downloadSurveys(surveyIds: surveyIds, sentTime: stringToTimeInterval(timeString: sentTimeString))
        } else {
            downloadSurveys(surveyIds: surveyIds)
        }
    }

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
        let surveyIds = try! JSONDecoder().decode([String].self, from:Data(json.utf8))
        for surveyId in surveyIds {
            if !(StudyManager.sharedInstance.currentStudy?.surveyExists(surveyId: surveyId) ?? false) {
                log.info("Received notification for new survey \(surveyId)")
                AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Received notification for new survey \(surveyId)")
            } else {
                log.info("Received notification for survey \(surveyId)")
                AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Received notification for survey \(surveyId)")
            }
        }
        return surveyIds
    }
    
    func sendFCMToken(fcmToken: String) {
        print("FCM Token: \(fcmToken)")
        if (fcmToken != "") {
            let fcmTokenRequest = FCMTokenRequest(fcmToken: fcmToken)
            ApiManager.sharedInstance.makePostRequest(fcmTokenRequest).catch {
                (error) in
                log.error("Error registering FCM token: \(error)")
                AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Error registering FCM token: \(error)")
            }
        }
    }
    
    // downloads all of the surveys in the study
    func downloadSurveys(surveyIds: [String], sentTime: TimeInterval = 0) {
        guard let study = StudyManager.sharedInstance.currentStudy else {
            log.error("Could not find study")
            return
        }
        Recline.shared.save(study).then { _ -> Promise<([Survey], Int)> in
            let surveyRequest = GetSurveysRequest();
            log.info("Requesting surveys")
            return ApiManager.sharedInstance.arrayPostRequest(surveyRequest)
        }.then {
            (surveys, _) -> Promise<Void> in
            study.surveys = surveys
            return Recline.shared.save(study).asVoid();
        } .done { _ in
            self.setActiveSurveys(surveyIds: surveyIds, sentTime: sentTime)
        } .catch {
            (error) in
            log.error("Error downloading surveys: \(error)")
            AppEventManager.sharedInstance.logAppEvent(event: "survey_download", msg: "Error downloading surveys: \(error)")
            // try setting the active surveys anyway, even if download failed, can still use previously downloaded surveys
            self.setActiveSurveys(surveyIds: surveyIds, sentTime: sentTime)
        }
    }
    
    func setActiveSurveys(surveyIds: [String], sentTime: TimeInterval = 0) {
        if let study = StudyManager.sharedInstance.currentStudy {
            for surveyId in surveyIds {
                if let survey = study.getSurvey(surveyId: surveyId) {
                    let activeSurvey = ActiveSurvey(survey: survey)
                    activeSurvey.received = sentTime
                    if let surveyType = survey.surveyType {
                        switch (surveyType) {
                        case .AudioSurvey:
                            study.receivedAudioSurveys = (study.receivedAudioSurveys) + 1;
                        case .TrackingSurvey:
                            study.receivedTrackingSurveys = (study.receivedTrackingSurveys) + 1;
                        }
                    }
                    study.activeSurveys[surveyId] = activeSurvey
                } else {
                    log.error("Could not get survey")
                    AppEventManager.sharedInstance.logAppEvent(event: "survey_download", msg: "Could not get obtain survey for ActiveSurvey")
                }
            }
            // Emits a surveyUpdated event to the listener
            StudyManager.sharedInstance.surveysUpdatedEvent.emit(0);
             Recline.shared.save(study).catch { _ in
                 log.error("Failed to save study after processing surveys");
             }
            
            // set badge number
            UIApplication.shared.applicationIconBadgeNumber = study.activeSurveys.count
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
        // initialize Firebase on the main thread
        DispatchQueue.main.async {
            let isBeiwe2 = Configuration.sharedInstance.settings["config-server"] as? Bool ?? false;
            if (isBeiwe2) {
                FirebaseApp.configure(options: options)
            } else {
                FirebaseApp.configure()
            }
            log.info("Configured Firebase")
        }
    }
    
}

extension String: LocalizedError {
    public var errorDescription: String? { return self }
}

// [START ios_10_message_handling]
@available(iOS 10, *)
extension AppDelegate : UNUserNotificationCenterDelegate {
    
    // Receive displayed notifications for iOS 10 devices.
    // Is called when receiving a notification while app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        log.info("Foreground push notification received in extension")
        AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Foreground push notification received")
        let userInfo = notification.request.content.userInfo
        
        // Print message ID.
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID: \(messageID)")
        }
        
        // Print full message.
        print(userInfo)
        
        // if the notification is for a survey
        if userInfo["survey_ids"] != nil {
            handleSurveyNotification(userInfo: userInfo)
        }
        
        // Change this to your preferred presentation option
        completionHandler([])
    }
    
    // Is called when tapping on notification when app is in background
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        log.info("Background push notification received in extension")
        AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Background push notification received")
        let userInfo = response.notification.request.content.userInfo
        // Print message ID.
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID: \(messageID)")
        }
        
        // Print full message.
        print(userInfo)
        
        // if the notification is for a survey
        if userInfo["survey_ids"] != nil {
            handleSurveyNotification(userInfo: userInfo)
        }
        
        completionHandler()
    }
}
// [END ios_10_message_handling]

extension AppDelegate : MessagingDelegate {
    // [START refresh_token]
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String) {
        
        let dataDict:[String: String] = ["token": fcmToken]
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


