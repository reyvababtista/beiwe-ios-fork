import Foundation
import PromiseKit

class ProximityManager: DataServiceProtocol {
    let storeType = "proximity"
    let headers = ["timestamp", "event"]
    var store: DataStorage?

    @objc func proximityStateDidChange(_ notification: Notification) {
        // The stage did change: plugged, unplugged, full charge...
        var data: [String] = []
        data.append(String(Int64(Date().timeIntervalSince1970 * 1000)))
        data.append(UIDevice.current.proximityState ? "NearUser" : "NotNearUser")
        self.store?.store(data)
    }

    func initCollecting() -> Bool {
        self.store = DataStorageManager.sharedInstance.createStore(self.storeType, headers: self.headers)
        return true
    }

    func startCollecting() {
        log.info("Turning \(self.storeType) collection on")
        UIDevice.current.isProximityMonitoringEnabled = true
        NotificationCenter.default.addObserver(self, selector: #selector(self.proximityStateDidChange), name: UIDevice.proximityStateDidChangeNotification, object: nil)
        AppEventManager.sharedInstance.logAppEvent(event: "proximity_on", msg: "Proximity collection on")
    }

    func pauseCollecting() {
        log.info("Pausing \(self.storeType) collection")
        NotificationCenter.default.removeObserver(self, name: UIDevice.proximityStateDidChangeNotification, object: nil)
        AppEventManager.sharedInstance.logAppEvent(event: "proximity_off", msg: "Proximity collection off")
    }

    func finishCollecting() -> Promise<Void> {
        log.info("Finish collecting \(self.storeType) collection")
        self.pauseCollecting()
        self.store = nil
        return DataStorageManager.sharedInstance.closeStore(self.storeType)
    }
}
