import Foundation

let proximity_headers = [
    "timestamp",
    "event",
]

/// proximity manager, uses some delegate pattern
class ProximityManager: DataServiceProtocol {
    // for once all we need are the basics!
    let storeType = "proximity"
    var store: DataStorage?

    /// This function is the well-its-not-a-protocol function that is required to delegate to get proximity updates
    @objc func proximityStateDidChange(_ notification: Notification) {
        // The stage did change: plugged, unplugged, full charge...
        var data: [String] = []
        data.append(String(Int64(Date().timeIntervalSince1970 * 1000)))
        data.append(UIDevice.current.proximityState ? "NearUser" : "NotNearUser")
        self.store?.store(data)
    }

    /// protocol function
    func initCollecting() -> Bool {
        self.store = DataStorageManager.sharedInstance.createStore(self.storeType, headers: proximity_headers)
        return true
    }

    /// protocol function
    func startCollecting() {
        // print("Turning \(self.storeType) collection on")
        UIDevice.current.isProximityMonitoringEnabled = true
        // register the observer
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.proximityStateDidChange), name: UIDevice.proximityStateDidChangeNotification, object: nil
        )
        AppEventManager.sharedInstance.logAppEvent(event: "proximity_on", msg: "Proximity collection on")
    }
    
    /// protocol function
    func pauseCollecting() {
        // print("Pausing \(self.storeType) collection")
        // unregister the observer
        NotificationCenter.default.removeObserver(self, name: UIDevice.proximityStateDidChangeNotification, object: nil)
        AppEventManager.sharedInstance.logAppEvent(event: "proximity_off", msg: "Proximity collection off")
    }
    
    /// protocol function
    func finishCollecting() {
        // print("Finishing \(self.storeType) collection")
        self.pauseCollecting()
        self.store = nil
        DataStorageManager.sharedInstance.closeStore(self.storeType)
    }
}
