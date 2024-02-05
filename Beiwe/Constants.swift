struct Constants {
    static let passwordRequirementRegex = "^.{6,}$"
    static let passwordRequirementDescription = NSLocalizedString("password_length_requirement", comment: "")
    static let defaultStudyId = "default" // FIXME: purge
    
    static let DELIMITER = "," // csv separator character, named for legible code reasons
    static let KEYLENGTH = 128 // encryption key length for any given line of encrypted data.
    
    // settings for functions that have retry logic
    static let RECUR_SLEEP_DURATION = 0.05 // 50 milliseconds
    static let RECUR_DEPTH = 6
    
    static let DEFAULT_UNPOPULATED_APPINFO = "never_populated"
    
    static let HEARTBEAT_INTERVAL = 300.0 // 5 minutes
}

let DEV_TIMEZONE = "America/New_York"

let BACKGROUND_TASK_NAME_HEARTBEAT_BGREFRESH = "org.beiwe.heartbeat_bgrefresh"
let BACKGROUND_TASK_NAME_HEARTBEAT_BGPROCESSING = "org.beiwe.heartbeat_bgprocessing"
let BACKGROUND_TASK_NAME_HEARTBEAT_BGHEALTH = "org.beiwe.heartbeat_bghealth"

// Dispatch Queue qos options are: default, background, utility, userInitiated, userInteractive, and unspecified.
// TODO: document the difference between these.
// TODO: research, document the attributes parameter
let GLOBAL_DEFAULT_QUEUE = DispatchQueue.global(qos: .default)
let GLOBAL_BACKGROUND_QUEUE = DispatchQueue.global(qos: .background)
let GLOBAL_UTILITY_QUEUE = DispatchQueue.global(qos: .utility)
let HEARTBEAT_QUEUE = DispatchQueue(label: "org.beiwe.heartbeat_queue", qos: .userInitiated, attributes: [])
let BACKGROUND_DEVICE_INFO_QUEUE = DispatchQueue(label: "org.beiwe.background_device_info_queue", qos: .background, attributes: [])
let TIMER_QUEUE = DispatchQueue(label: "org.beiwe.timer_queue", attributes: [])
let RECLINE_QUEUE = DispatchQueue(label: "org.beiwe.recline_queue", qos: .userInteractive, attributes: []) // setting high on this queue because it is the database.
let PRE_UPLOAD_QUEUE = DispatchQueue(label: "org.beiwe.preupload_queue", qos: .default, attributes: [])

struct Ephemerals {
    // device info statuses
    static var notification_permission = "not populated, this is an app bug"
    static var locationServicesEnabledDescription = "not populated, this is an app bug"
    static var significantLocationChangeMonitoringAvailable = "not populated, this is an app bug"
    static var backgroundRefreshStatus = "not populated, this is an app bug"
    static var transition_count = 0
}
