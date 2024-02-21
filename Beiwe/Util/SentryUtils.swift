import Foundation

// I cannot even.
// This was originally named just "Configuration" in a file named "Configuration.swift".
// What the hell. It loads A File. That's it. It didn't Do Anything.
class SentryConfiguration {
    static let sharedInstance = SentryConfiguration();
    var settings: Dictionary<String, AnyObject> = [:];

    init() {
        if let path = Bundle.main.path(forResource: "Config-Default", ofType: "plist"), let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] {
            for (key,value) in dict {
                settings[key] = value;
            }
        }
        if let path = Bundle.main.path(forResource: "Config", ofType: "plist"), let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] {
            for (key,value) in dict {
                settings[key] = value;
            }
        }

    }
}
