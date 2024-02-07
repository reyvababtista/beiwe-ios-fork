import EmitterKit
import Foundation

let power_state_headers = [
    "timestamp",
    "event",
    "level",
]

/// uses a delegate pattern to register for power state changes, AND a listener... list.
class PowerStateManager: DataServiceProtocol {
    // the basics
    let storeType = "powerState"
    var store: DataStorage?
    
    // contains some "listeners" (EmmitterKit class) - this might be a required variable name, I don't know, don't rename it.
    var listeners: [Listener] = []

    /// the well-it-isn't-a-protocol function that is delegated for power state updates
    @objc func batteryStateDidChange(_ notification: Notification) {
        // The state change, currently known states are Charging, Full, Unplugged, PowerUnknown
        var data: [String] = []
        data.append(String(Int64(Date().timeIntervalSince1970 * 1000)))
        var state: String
        switch UIDevice.current.batteryState {
        case .charging:
            state = "Charging"
        case .full:
            state = "Full"
        case .unplugged:
            state = "Unplugged"
        case .unknown:
            state = "PowerUnknown"
        }
        data.append(state)
        data.append(String(UIDevice.current.batteryLevel))
        self.store?.store(data)
    }

    // used in the closure pattern effectively as a registered delegate function
    func didLockUnlock(_ isLocked: Bool) {
        // (omg someone actually factored this well by making a named function instead of completely undocumented closure without even typing information! Its amazing how low my bar for finding something reasonable in this codebase has gotten 🙄.)
        log.info("Lock state data changed: \(isLocked)")
        var data: [String] = []
        data.append(String(Int64(Date().timeIntervalSince1970 * 1000)))
        let state: String = isLocked ? "Locked" : "Unlocked"
        data.append(state)
        data.append(String(UIDevice.current.batteryLevel))
        self.store?.store(data)
    }

    /// protocol function
    func initCollecting() -> Bool {
        self.store = DataStorageManager.sharedInstance.createStore(self.storeType, headers: power_state_headers)
        return true
    }
    
    /// protocol function - populates listeners, registers delegate pattern
    func startCollecting() {
        log.info("Turning \(self.storeType) collection on")
        UIDevice.current.isBatteryMonitoringEnabled = true
        // TODO: document why there is a weak reference here?
        self.listeners += AppDelegate.sharedInstance().lockEvent.on { [weak self] locked in
            self?.didLockUnlock(locked)  // the weak reference to self means we have to optional unwrap uuuhg
        }
        NotificationCenter.default.addObserver(self, selector: #selector(self.batteryStateDidChange), name: UIDevice.batteryStateDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.batteryStateDidChange), name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        AppEventManager.sharedInstance.logAppEvent(event: "powerstate_on", msg: "PowerState collection on")
    }

    /// protocol function - clears listeners, unregisters delegate patters
    func pauseCollecting() {
        log.info("Pausing \(self.storeType) collection")
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryStateDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        self.listeners = []
        AppEventManager.sharedInstance.logAppEvent(event: "powerstate_off", msg: "PowerState collection off")
    }

    /// protocol function
    func finishCollecting() {
        log.info("Finish collecting \(self.storeType) collection")
        self.pauseCollecting()
        self.store = nil
        DataStorageManager.sharedInstance.closeStore(self.storeType)
    }
}
