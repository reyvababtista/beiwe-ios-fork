struct Constants {
    static let passwordRequirementRegex = "^.{6,}$"
    static let passwordRequirementDescription = NSLocalizedString("password_length_requirement", comment: "")
    static let defaultStudyId = "default"  // FIXME: purge
    
    static let DELIMITER = "," // csv separator character, named for legible code reasons
    static let KEYLENGTH = 128 // encryption key length for any given line of encrypted data.
    
    // settings for functions that have retry logic
    static let RECUR_SLEEP_DURATION = 0.05 // 50 milliseconds
    static let RECUR_DEPTH = 6
    
    static let BACKGROUND_DEVICE_INFO_QUEUE = DispatchQueue(label: "org.beiwe.background_device_info_queue", attributes: [])
    
    static let DEFAULT_UNPOPULATED_APPINFO = "never_populated"
}

struct Ephemerals {
    // device info statuses
    static var notification_permission = "not populated, this is an app bug"
    static var locationServicesEnabledDescription = "not populated, this is an app bug"
    static var significantLocationChangeMonitoringAvailable = "not populated, this is an app bug"
    static var backgroundRefreshStatus = "not populated, this is an app bug"
    static var transition_count = 0
}

func dateFormat(_ date: Date) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "y-MM-dd HH:mm:ss"
    return dateFormatter.string(from: date)
}

func timeFormat(_ date: Date) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "HH:mm:ss"
    return dateFormatter.string(from: date)
}

// Swift can't work out how to call the Date-typed version of the call from inside the TimeInterval-typed version of the call.
func _swift_sucks_explicit_function_type_dateFormat(_ date: Date) -> String {
    return dateFormat(date)
}
func _swift_sucks_explicit_function_type_timeFormat(_ date: Date) -> String {
    return timeFormat(date)
}

func dateformat(_ unix_timestamp: TimeInterval) -> String {
    return _swift_sucks_explicit_function_type_dateFormat(Date(timeIntervalSince1970: unix_timestamp))
}

func timeformat(_ unix_timestamp: TimeInterval) -> String {
    return _swift_sucks_explicit_function_type_timeFormat(Date(timeIntervalSince1970: unix_timestamp))
}


func timestampString() -> String {
    return dateFormat(Date())
}

