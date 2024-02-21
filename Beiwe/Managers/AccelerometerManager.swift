import CoreMotion
import Foundation

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
    let dataStorage: DataStorage
    var datapoints = [[String]]()
    
    // we need an offset for timestamp calculations, that's just how it works.
    var offset_since_1970: Double = 0
    
    // accelerometer's callback has a non-optional queue, we want exactly one queue.
    let queue = OperationQueue()
    
    init() {
        self.dataStorage = DataStorageManager.sharedInstance.createStore(self.storeType, headers: accelerometer_headers)
    }
    
    /// protocol function - sets up frequency
    func initCollecting() -> Bool {
        guard self.motionManager.isAccelerometerAvailable else {
            log.error("Accel not available.  Not initializing collection")
            return false
        }
        // TimeInterval of uptime, boottime as unix timestamp
        self.offset_since_1970 = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        let frequency_base = StudyManager.sharedInstance.currentStudy?.studySettings?.accelerometerFrequency ?? 10
        self.motionManager.accelerometerUpdateInterval = 1.0 / Double(frequency_base)
        // print("accelerometerUpdateInterval: \(motionManager.accelerometerUpdateInterval)")
        return true
    }

    /// protocol function
    func startCollecting() {
        // print("Turning \(self.storeType) collection on")
        // print("accelerometerUpdateInterval: \(motionManager.accelerometerUpdateInterval)")
        
        // set the closure function as the delegate for updates
        self.motionManager.startAccelerometerUpdates(to: self.queue) { (accelData: CMAccelerometerData?, _: Error?) in
            if let accelData = accelData {
                var data: [String] = []
                data.append(String(Int64((accelData.timestamp + self.offset_since_1970) * 1000.0)))
                data.append("unknown")
                data.append(String(accelData.acceleration.x))
                data.append(String(accelData.acceleration.y))
                data.append(String(accelData.acceleration.z))
                self.datapoints.append(data)
                if self.datapoints.count > ACCELEROMETER_CACHE_SIZE {
                    self.flush()
                }
            }
        }
        AppEventManager.sharedInstance.logAppEvent(event: "accel_on", msg: "Accel collection on")
    }

    /// protocol function
    func pauseCollecting() {
        // print("Pausing \(self.storeType) collection")
        self.motionManager.stopAccelerometerUpdates()
        AppEventManager.sharedInstance.logAppEvent(event: "accel_off", msg: "Accel collection off")
    }

    /// protocol function
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
