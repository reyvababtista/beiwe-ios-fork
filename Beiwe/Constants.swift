struct Constants {
    static let passwordRequirementRegex = "^.{6,}$"
    static let passwordRequirementDescription = NSLocalizedString("password_length_requirement", comment: "")
    static let defaultStudyId = "default"  // FIXME: purge
    
    static let DELIMITER = "," // csv separator character, named for legible code reasons
    static let KEYLENGTH = 128 // encryption key length for any given line of encrypted data.
    
    // settings for functions that have retry logic
    static let RECUR_SLEEP_DURATION = 0.05 // 50 milliseconds
    static let RECUR_DEPTH = 6
    
    static let DEFAULT_UNPOPULATED_APPINFO = "never_populated"
}

// dispatch queues
struct DispatchQueues {
    // Dispatch Queue qos options are: default, background, utility, userInitiated, userInteractive, and unspecified.
    // TODO: document the difference between these.
    // TODO: research, document the attributes parameter
    static let GLOBAL_DEFAULT_QUEUE = DispatchQueue.global(qos: .default)
    static let GLOBAL_BACKGROUND_QUEUE = DispatchQueue.global(qos: .background)
    static let BACKGROUND_DEVICE_INFO_QUEUE = DispatchQueue(label: "org.beiwe.background_device_info_queue", qos: .background, attributes: [])
    static let TIMER_QUEUE = DispatchQueue(label: "org.beiwe.timer_queue", attributes: [])
    static let RECLINE_QUEUE = DispatchQueue(label: "org.beiwe.recline_queue", qos: .userInteractive, attributes: [])  // setting high on this queue because it is the database.
    static let PRE_UPLOAD_QUEUE = DispatchQueue(label: "org.beiwe.preupload_queue", qos: .default, attributes: [])
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

func smartformat(_ d: Date) -> String {
    if Calendar.current.isDateInToday(d) {
        return timeFormat(d)
    } else {
        return dateFormat(d)
    }
}

func smartformat(_ unix_timestamp: TimeInterval) -> String {
    let d = Date(timeIntervalSince1970: unix_timestamp)
    if Calendar.current.isDateInToday(d) {
        return timeFormat(d)
    } else {
        return dateFormat(d)
    }
}

func timestampString() -> String {
    return dateFormat(Date())
}


/// converts the iso time string format to a TimeInterval (integer)
func isoStringToTimeInterval(timeString: String) -> TimeInterval {
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX") // set locale to reliable US_POSIX
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    let sentTime = dateFormatter.date(from: timeString)!
    return sentTime.timeIntervalSince1970
}

// if you want to hook into the print function uncomment this and go nuts. Don't Commit.
// public func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
//     // Swift.print("[Beiwe2] \(timeFormat(Date()))", terminator: ": ")
//     // Swift.print(items, separator: separator, terminator: terminator)
//     log.info(items)
// }
