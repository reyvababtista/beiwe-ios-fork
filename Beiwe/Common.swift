/// Extend the DispatchQueue to have a function called Background
extension DispatchQueue {
    // more or less from https://stackoverflow.com/questions/24056205/how-to-use-background-thread-in-swift
    // the original names were not super descriptive
    func background(_ background_task: @escaping (() -> Void), completion_task: (() -> Void)? = nil, completeion_delay: Double = 0.0) {
        self.async {
            // run the background task
            background_task()
            
            // run completion task
            if let completion_task = completion_task {
                self.asyncAfter(deadline: .now() + completeion_delay, execute: {completion_task()})
            }
        }
    }
    
    // in simplifying background_completion above I eventually worked out that you dispatch on background thread with a delay like this:
    // queue.asyncAfter(deadline: .now() + delay, execute: { background_task() })
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
