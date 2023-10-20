import CoreMotion
import Foundation
import PromiseKit

let accelerometer_headers = [
    "timestamp",
    "accuracy",
    "x",
    "y",
    "z",
]

class AccelerometerManager: DataServiceProtocol {
    let motionManager = AppDelegate.sharedInstance().motionManager // weird singleton instance attached to appdelegate - ah, shares with gyro

    // the base
    let storeType = "accel"
    var store: DataStorage?

    // we need an offset for timestamp calculations
    var offset_since_1970: Double = 0

    /// protocol function - sets up frequency
    func initCollecting() -> Bool {
        guard self.motionManager.isAccelerometerAvailable else {
            log.info("Accel not available.  Not initializing collection")
            return false
        }
        // TimeInterval of uptime, boottime as unix timestamp
        self.offset_since_1970 = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        self.store = DataStorageManager.sharedInstance.createStore(self.storeType, headers: accelerometer_headers)
        let frequency_base = StudyManager.sharedInstance.currentStudy?.studySettings?.accelerometerFrequency ?? 10
        self.motionManager.accelerometerUpdateInterval = 1.0 / Double(frequency_base)
        // print("accelerometerUpdateInterval: \(motionManager.accelerometerUpdateInterval)")
        return true
    }

    /// protocol function
    func startCollecting() {
        log.info("Turning \(self.storeType) collection on")
        // print("accelerometerUpdateInterval: \(motionManager.accelerometerUpdateInterval)")
        let queue = OperationQueue()
        // set the closure function as the delegate for updates
        self.motionManager.startAccelerometerUpdates(to: queue) { (accelData: CMAccelerometerData?, _: Error?) in
            if let accelData = accelData {
                var data: [String] = []
                data.append(String(Int64((accelData.timestamp + self.offset_since_1970) * 1000)))
                data.append("unknown")
                data.append(String(accelData.acceleration.x))
                data.append(String(accelData.acceleration.y))
                data.append(String(accelData.acceleration.z))
                self.store?.store(data)
            }
        }
        AppEventManager.sharedInstance.logAppEvent(event: "accel_on", msg: "Accel collection on")
    }

    /// protocol function
    func pauseCollecting() {
        log.info("Pausing \(self.storeType) collection")
        self.motionManager.stopAccelerometerUpdates()
        AppEventManager.sharedInstance.logAppEvent(event: "accel_off", msg: "Accel collection off")
    }

    /// protocol function
    func finishCollecting() -> Promise<Void> {
        print("Stopping Accelerometer collecting")
        self.pauseCollecting()
        self.store = nil
        return DataStorageManager.sharedInstance.closeStore(self.storeType)
    }
}
