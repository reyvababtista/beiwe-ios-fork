import PromiseKit
import Foundation
import ObjectMapper

// this is so stupid. The way this works and What On Earth Recline is and how this mapping function I define could even possibly
// magically be a 2-way binding for data simply isn't documented anywhere.  It just magically exists and is saved without explanaition.

fileprivate let DEFAULT_STRING = Constants.DEFAULT_UNPOPULATED_APPINFO

/// An object that stores timestamp strings of when an event occurred
struct AppInfo: Mappable {
    init(map: Map) {}
    
    var lastApplicationWillEnterForeground = DEFAULT_STRING
    var lastApplicationWillFinishLaunchingWithOptions = DEFAULT_STRING
    var lastApplicationWillTerminate = DEFAULT_STRING
    var lastApplicationWillResignActive = DEFAULT_STRING
    var lastApplicationDidBecomeActive = DEFAULT_STRING
    var lastApplicationDidEnterBackground = DEFAULT_STRING
    var lastApplicationDidReceiveMemoryWarning = DEFAULT_STRING
    var lastApplicationProtectedDataDidBecomeAvailable = DEFAULT_STRING
    var lastApplicationProtectedDataWillBecomeUnavailable = DEFAULT_STRING
    
    var lastAppStart = DEFAULT_STRING
    var lastSuccessfulLogin = DEFAULT_STRING
    var lastFailedToRegisterForNotification = DEFAULT_STRING
    var lastBackgroundPushNotificationReceived = DEFAULT_STRING
    var lastForegroundPushNotificationReceived = DEFAULT_STRING
    
    mutating func mapping(map: Map) {
        self.lastApplicationWillEnterForeground <- map["last_application_will_enter_foreground"]
        self.lastApplicationWillFinishLaunchingWithOptions <- map["last_application_will_finish_launching_with_options"]
        self.lastApplicationWillTerminate <- map["last_application_will_terminate"]
        self.lastApplicationWillResignActive <- map["last_application_will_resign_active"]
        self.lastApplicationDidBecomeActive <- map["last_application_did_become_active"]
        self.lastApplicationDidEnterBackground <- map["last_application_did_enter_background"]
        self.lastApplicationDidReceiveMemoryWarning <- map["last_application_did_receive_memory_warning"]
        self.lastApplicationProtectedDataDidBecomeAvailable <- map["last_application_protected_data_did_become_available"]
        self.lastApplicationProtectedDataWillBecomeUnavailable <- map["last_application_protected_data_will_become_unavailable"]
        
        self.lastAppStart <- map["last_app_start"]
        self.lastSuccessfulLogin <- map["last_successful_login"]
        self.lastFailedToRegisterForNotification <- map["last_failed_to_register_for_notification"]
        self.lastBackgroundPushNotificationReceived <- map["last_background_push_notification_received"]
        self.lastForegroundPushNotificationReceived <- map["last_foreground_push_notification_received"]
    }
}
