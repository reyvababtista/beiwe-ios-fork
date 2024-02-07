import CoreMotion
import Foundation


let headers = [
    "timestamp",
    "x",
    "y",
    "z",
]

class GyroManager: DataServiceProtocol {
    let motionManager = AppDelegate.sharedInstance().motionManager  // weird singleton instance attached to appdelegate - ah, shares with accelerometer

    // the basics
    let storeType = "gyro"
    var store: DataStorage? // TODO: make this non-optional (breaks protocol I think)
    
    // we need an offset for time calculations
    var offset_since_1970: Double = 0

    /// protocol instruction - sets up custom interval
    func initCollecting() -> Bool {
        guard self.motionManager.isGyroAvailable else {
            log.info("Gyro not available.  Not initializing collection")
            return false
        }
        // TimeInterval of uptime, boottime as unix timestamp
        self.offset_since_1970 = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        self.store = DataStorageManager.sharedInstance.createStore(self.storeType, headers: headers)

        // ug, currentstudy and study settings are optional so can't rely on the default gyroFrequency, have to hardcode it
        let frequency_base = StudyManager.sharedInstance.currentStudy?.studySettings?.gyroFrequency ?? 10
        self.motionManager.gyroUpdateInterval = 1.0 / Double(frequency_base)
        // print("gyroUpdateInterval: \(motionManager.gyroUpdateInterval)")
        return true
    }

    /// protocol instruction - sets the delegate(?) function
    func startCollecting() {
        log.info("Turning \(self.storeType) collection on")
        // print("gyroUpdateInterval: \(motionManager.gyroUpdateInterval)")
        let queue = OperationQueue()
        // set the closure as the delegate function
        self.motionManager.startGyroUpdates(to: queue) { (gyroData: CMGyroData?, _: Error?) in
            if let gyroData = gyroData {
                var data: [String] = []
                data.append(String(Int64((gyroData.timestamp + self.offset_since_1970) * 1000)))
                data.append(String(gyroData.rotationRate.x))
                data.append(String(gyroData.rotationRate.y))
                data.append(String(gyroData.rotationRate.z))
                self.store?.store(data)
            }
        }
        AppEventManager.sharedInstance.logAppEvent(event: "gyro_on", msg: "Gyro collection on")
    }

    /// protocol instruction
    func pauseCollecting() {
        log.info("Pausing \(self.storeType) collection")
        self.motionManager.stopGyroUpdates()
        AppEventManager.sharedInstance.logAppEvent(event: "gyro_off", msg: "Gyro collection off")
    }

    /// protocol instruction
    func finishCollecting() {
        print("Stopping gyro collecting")
        self.pauseCollecting()
        self.store = nil
        DataStorageManager.sharedInstance.closeStore(self.storeType)
    }
}
