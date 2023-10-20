import CoreMotion
import Foundation
import PromiseKit

let magnetometer_headers = [
    "timestamp",
    "x",
    "y",
    "z",
]

class MagnetometerManager: DataServiceProtocol {
    let motionManager = AppDelegate.sharedInstance().motionManager // weird singleton reference attached to AppDelegate

    // the basics
    let storeType = "magnetometer"
    var store: DataStorage?

    // the offset
    var offset_since_1970: Double = 0

    /// protocol function
    func initCollecting() -> Bool {
        // give up early logic
        guard self.motionManager.isMagnetometerAvailable else {
            log.info("Magnetometer not available.  Not initializing collection")
            return false
        }

        self.store = DataStorageManager.sharedInstance.createStore(self.storeType, headers: magnetometer_headers)
        // we need an offset for time calculations
        self.offset_since_1970 = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        self.motionManager.magnetometerUpdateInterval = 0.1
        return true
    }
    
    /// protocol function
    func startCollecting() {
        log.info("Turning \(self.storeType) collection on")
        let queue = OperationQueue()
        // this closure is the function that records data
        self.motionManager.startMagnetometerUpdates(to: queue) { (magData: CMMagnetometerData?, _: Error?) in
            if let magData = magData {
                var data: [String] = []
                let timestamp: Double = magData.timestamp + self.offset_since_1970
                data.append(String(Int64(timestamp * 1000)))
                // data.append(AppDelegate.sharedInstance().modelVersionId)  // random extra datapoint
                data.append(String(magData.magneticField.x))
                data.append(String(magData.magneticField.y))
                data.append(String(magData.magneticField.z))
                self.store?.store(data)
            }
        }
        AppEventManager.sharedInstance.logAppEvent(event: "magnetometer_on", msg: "Magnetometer collection on")
    }

    /// protocol function
    func pauseCollecting() {
        log.info("Pausing \(self.storeType) collection")
        self.motionManager.stopMagnetometerUpdates()
        AppEventManager.sharedInstance.logAppEvent(event: "magnetometer_off", msg: "Magnetometer collection off")
    }

    /// protocol function
    func finishCollecting() -> Promise<Void> {
        print("Stopping Magnetometer collecting")
        self.pauseCollecting()
        self.store = nil
        return DataStorageManager.sharedInstance.closeStore(self.storeType)
    }
}
