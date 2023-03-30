import Foundation
import PromiseKit
import ReachabilitySwift

let reachability_headers = [
    "timestamp",
    "event",
]

/// Reachability - uses a delegate pattern
class ReachabilityManager: DataServiceProtocol {
    // tHe basics
    let storeType = "reachability"
    var store: DataStorage?

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
        self.store?.store(data)
    }

    /// protocol function
    func initCollecting() -> Bool {
        self.store = DataStorageManager.sharedInstance.createStore(self.storeType, headers: reachability_headers)
        return true
    }

    /// protocol function
    func startCollecting() {
        log.info("Turning \(self.storeType) collection on")
        // register as the delegate
        NotificationCenter.default.addObserver(self, selector: #selector(self.reachabilityChanged), name: ReachabilityChangedNotification, object: nil)
        AppEventManager.sharedInstance.logAppEvent(event: "reachability_on", msg: "Reachability collection on")
    }

    /// protocol function
    func pauseCollecting() {
        log.info("Pausing \(self.storeType) collection")
        // unregister the delegate
        NotificationCenter.default.removeObserver(self, name: ReachabilityChangedNotification, object: nil)
        AppEventManager.sharedInstance.logAppEvent(event: "reachability_off", msg: "Reachability collection off")
    }

    /// protocol function
    func finishCollecting() -> Promise<Void> {
        log.info("Finish collecting \(self.storeType) collection")
        self.pauseCollecting()
        self.store = nil
        return DataStorageManager.sharedInstance.closeStore(self.storeType)
    }
}
