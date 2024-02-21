import Foundation
import ReachabilitySwift

let reachability_headers = [
    "timestamp",
    "event",
]

/// Reachability - uses a delegate pattern
class ReachabilityManager: DataServiceProtocol {
    // tHe basics
    let storeType = "reachability"
    var dataStorage: DataStorage

    init () {
        self.dataStorage = DataStorageManager.sharedInstance.createStore(self.storeType, headers: reachability_headers)
    }
    
    @objc func reachabilityChanged(_ notification: Notification) {
        // give up early logic
        guard let reachability = AppDelegate.sharedInstance().reachability else {
            return
        }
        // the state
        var reachState: String
        if reachability.isReachable {
            if reachability.isReachableViaWiFi {
                reachState = "wifi"
            } else {
                reachState = "cellular"
            }
        } else {
            reachState = "unreachable"
        }
        
        // the data...
        var data: [String] = []
        data.append(String(Int64(Date().timeIntervalSince1970 * 1000)))
        data.append(reachState)
        self.dataStorage.store(data)
    }

    /// protocol function
    func initCollecting() -> Bool {
        return true
    }

    /// protocol function
    func startCollecting() {
        // print("Turning \(self.storeType) collection on")
        // register as the delegate
        NotificationCenter.default.addObserver(self, selector: #selector(self.reachabilityChanged), name: ReachabilityChangedNotification, object: nil)
        AppEventManager.sharedInstance.logAppEvent(event: "reachability_on", msg: "Reachability collection on")
    }

    /// protocol function
    func pauseCollecting() {
        // print("Pausing \(self.storeType) collection")
        // unregister the delegate
        NotificationCenter.default.removeObserver(self, name: ReachabilityChangedNotification, object: nil)
        AppEventManager.sharedInstance.logAppEvent(event: "reachability_off", msg: "Reachability collection off")
    }

    /// protocol function
    func finishCollecting() {
        // print("Finishing \(self.storeType) collection")
        self.pauseCollecting()
        self.dataStorage.reset()
    }
    
    func createNewFile() {
        self.dataStorage.reset()
    }
    
    func flush() {
        // ReachabilityManager does not have potentially intensive write operations, it
        // writes it's data immediately.
    }
}
