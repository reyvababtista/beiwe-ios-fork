struct Constants {
    static let passwordRequirementRegex = "^.{6,}$"
    static let passwordRequirementDescription = NSLocalizedString("password_length_requirement", comment: "")
    static let defaultStudyId = "default"  // FIXME: purge
    
    static let DELIMITER = "," // csv separator character, named for legible code reasons
    static let KEYLENGTH = 128 // encryption key length for any given line of encrypted data.

    // settings for functions that have retry logic
    static let RECUR_SLEEP_DURATION = 0.05 // 50 milliseconds
    static let RECUR_DEPTH = 3
    
    static let NOTIFICATION_STATUS_QUEUE = DispatchQueue(label: "org.beiwe.notification_status_queue", attributes: [])
}
