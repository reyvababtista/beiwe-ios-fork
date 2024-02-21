import CoreMotion
import Foundation


let device_motion_headers = [
    "timestamp",
    "roll",
    "pitch",
    "yaw",
    "rotation_rate_x",
    "rotation_rate_y",
    "rotation_rate_z",
    "gravity_x",
    "gravity_y",
    "gravity_z",
    "user_accel_x",
    "user_accel_y",
    "user_accel_z",
    "magnetic_field_calibration_accuracy",
    "magnetic_field_x",
    "magnetic_field_y",
    "magnetic_field_z",
]

class DeviceMotionManager: DataServiceProtocol {
    let motionManager = AppDelegate.sharedInstance().motionManager  // weird singleton reference attached to AppDelegate

    // the basics
    let storeType = "devicemotion"
    let dataStorage: DataStorage
    var datapoints = [[String]]()
    let queue = OperationQueue()
    
    // we need an offset timestamp for timecode calculations
    var offset_since_1970: Double = 0
    
    init () {
        self.dataStorage = DataStorageManager.sharedInstance.createStore(self.storeType, headers: device_motion_headers)
    }
    
    /// protocol funciton
    func initCollecting() -> Bool {
        // give up early logic
        guard self.motionManager.isDeviceMotionAvailable else {
            log.info("DeviceMotion not available.  Not initializing collection")
            return false
        }
        // Get TimeInterval of uptime i.e. the delta: now - bootTime
        self.offset_since_1970 = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime // Now since 1970
        self.motionManager.deviceMotionUpdateInterval = 0.1
        return true
    }
    
    /// protocol function
    func startCollecting() {
        // print("Turning \(self.storeType) collection on")

        
        self.motionManager.startDeviceMotionUpdates(using: CMAttitudeReferenceFrame.xArbitraryZVertical, to: self.queue) {
            (motionData: CMDeviceMotion?, _: Error?) in
            
            if let motionData = motionData {
                var data: [String] = []
                let timestamp: Double = motionData.timestamp + self.offset_since_1970
                data.append(String(Int64(timestamp * 1000)))
                // data.append(AppDelegate.sharedInstance().modelVersionId)  // random abandoned datapoint
                data.append(String(motionData.attitude.roll))
                data.append(String(motionData.attitude.pitch))
                data.append(String(motionData.attitude.yaw))
                data.append(String(motionData.rotationRate.x))
                data.append(String(motionData.rotationRate.y))
                data.append(String(motionData.rotationRate.z))
                data.append(String(motionData.gravity.x))
                data.append(String(motionData.gravity.y))
                data.append(String(motionData.gravity.z))
                data.append(String(motionData.userAcceleration.x))
                data.append(String(motionData.userAcceleration.y))
                data.append(String(motionData.userAcceleration.z))
                // get a string for the accuracy
                var fieldAccuracy: String
                switch motionData.magneticField.accuracy {
                case .uncalibrated:
                    fieldAccuracy = "uncalibrated"
                case .low:
                    fieldAccuracy = "low"
                case .medium:
                    fieldAccuracy = "medium"
                case .high:
                    fieldAccuracy = "high"
                default:
                    fieldAccuracy = "unknown"
                }
                data.append(fieldAccuracy)
                data.append(String(motionData.magneticField.field.x))
                data.append(String(motionData.magneticField.field.y))
                data.append(String(motionData.magneticField.field.z))
                self.datapoints.append(data)
                if self.datapoints.count > DEVICE_MOTION_CACHE_SIZE {
                    self.flush()
                }
            }
        }
        AppEventManager.sharedInstance.logAppEvent(event: "devicemotion_on", msg: "DeviceMotion collection on")
    }

    func pauseCollecting() {
        // print("Pausing \(self.storeType) collection")
        self.motionManager.stopDeviceMotionUpdates()
        AppEventManager.sharedInstance.logAppEvent(event: "devicemotion_off", msg: "DeviceMotion collection off")
    }

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
