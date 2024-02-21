import CoreMotion
import Foundation

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
    var dataStorage: DataStorage
    var datapoints = [[String]]()
    
    // magnetometer's callback has a non-optional queue, we want exactly one queue.
    let queue = OperationQueue()
    
    // the offset
    var offset_since_1970: Double = 0

    init() {
        self.dataStorage = DataStorageManager.sharedInstance.createStore(self.storeType, headers: magnetometer_headers)
    }
    
    /// protocol function
    func initCollecting() -> Bool {
        // give up early logic
        guard self.motionManager.isMagnetometerAvailable else {
            log.info("Magnetometer not available.  Not initializing collection")
            return false
        }

        // we need an offset for time calculations
        self.offset_since_1970 = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        self.motionManager.magnetometerUpdateInterval = 0.1
        return true
    }
    
    /// protocol function
    func startCollecting() {
        // print("Turning \(self.storeType) collection on")
        // this closure is the function that records data
        self.motionManager.startMagnetometerUpdates(to: self.queue) { (magData: CMMagnetometerData?, _: Error?) in
            if let magData = magData {
                var data: [String] = []
                let timestamp: Double = magData.timestamp + self.offset_since_1970
                data.append(String(Int64(timestamp * 1000)))
                // data.append(AppDelegate.sharedInstance().modelVersionId)  // random extra datapoint
                data.append(String(magData.magneticField.x))
                data.append(String(magData.magneticField.y))
                data.append(String(magData.magneticField.z))
                self.datapoints.append(data)
                if self.datapoints.count > MAGNETOMETER_CACHE_SIZE {
                    self.flush()
                }
            }
        }
        AppEventManager.sharedInstance.logAppEvent(event: "magnetometer_on", msg: "Magnetometer collection on")
    }

    /// protocol function
    func pauseCollecting() {
        // print("Pausing \(self.storeType) collection")
        self.motionManager.stopMagnetometerUpdates()
        AppEventManager.sharedInstance.logAppEvent(event: "magnetometer_off", msg: "Magnetometer collection off")
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
