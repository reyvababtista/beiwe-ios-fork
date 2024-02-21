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
    let dataStorage: DataStorage
    var datapoints = [[String]]()
    let queue = OperationQueue()
    
    // we need an offset for time calculations
    var offset_since_1970: Double = 0

    init () {
        self.dataStorage = DataStorageManager.sharedInstance.createStore(self.storeType, headers: headers)
    }
    
    /// protocol instruction - sets up custom interval
    func initCollecting() -> Bool {
        guard self.motionManager.isGyroAvailable else {
            log.info("Gyro not available.  Not initializing collection")
            return false
        }
        // TimeInterval of uptime, boottime as unix timestamp
        self.offset_since_1970 = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime

        // ug, currentstudy and study settings are optional so can't rely on the default gyroFrequency, have to hardcode it
        let frequency_base = StudyManager.sharedInstance.currentStudy?.studySettings?.gyroFrequency ?? 10
        self.motionManager.gyroUpdateInterval = 1.0 / Double(frequency_base)
        // print("gyroUpdateInterval: \(motionManager.gyroUpdateInterval)")
        return true
    }

    /// protocol instruction - sets the delegate(?) function
    func startCollecting() {
        // print("Turning \(self.storeType) collection on")
        // print("gyroUpdateInterval: \(motionManager.gyroUpdateInterval)")
        // set the closure as the delegate function
        self.motionManager.startGyroUpdates(to: self.queue) { (gyroData: CMGyroData?, _: Error?) in
            if let gyroData = gyroData {
                var data: [String] = []
                data.append(String(Int64((gyroData.timestamp + self.offset_since_1970) * 1000)))
                data.append(String(gyroData.rotationRate.x))
                data.append(String(gyroData.rotationRate.y))
                data.append(String(gyroData.rotationRate.z))
                
            }
        }
        AppEventManager.sharedInstance.logAppEvent(event: "gyro_on", msg: "Gyro collection on")
    }

    /// protocol instruction
    func pauseCollecting() {
        // print("Pausing \(self.storeType) collection")
        self.motionManager.stopGyroUpdates()
        AppEventManager.sharedInstance.logAppEvent(event: "gyro_off", msg: "Gyro collection off")
    }

    /// protocol instruction
    func finishCollecting() {
        // print("Finishing \(self.storeType) collection")
        self.pauseCollecting()
        self.createNewFile() // file creation is lazy
    }
    
    func createNewFile() {
        self.flush()
        self.dataStorage.reset()
    }
    
    func flush() {
        // todo - bulk write?
        let data_to_write = self.datapoints
        self.datapoints = []
        for data in data_to_write {
            self.dataStorage.store(data)
        }
    }

}
