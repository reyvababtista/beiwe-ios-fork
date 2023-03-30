import CoreMotion
import Foundation
import PromiseKit

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
    var store: DataStorage?

    // we need an offset timestamp for timecode calculations
    var offset_since_1970: Double = 0

    /// protocol funciton
    func initCollecting() -> Bool {
        // give up early logic
        guard self.motionManager.isDeviceMotionAvailable else {
            log.info("DeviceMotion not available.  Not initializing collection")
            return false
        }

        self.store = DataStorageManager.sharedInstance.createStore(self.storeType, headers: device_motion_headers)
        // Get TimeInterval of uptime i.e. the delta: now - bootTime
        self.offset_since_1970 = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime // Now since 1970
        self.motionManager.deviceMotionUpdateInterval = 0.1
        return true
    }

    /// protocol function
    func startCollecting() {
        log.info("Turning \(self.storeType) collection on")

        let queue = OperationQueue()
        self.motionManager.startDeviceMotionUpdates(using: CMAttitudeReferenceFrame.xArbitraryZVertical, to: queue) {
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

                self.store?.store(data)
            }
        }
        AppEventManager.sharedInstance.logAppEvent(event: "devicemotion_on", msg: "DeviceMotion collection on")
    }

    func pauseCollecting() {
        log.info("Pausing \(self.storeType) collection")
        self.motionManager.stopDeviceMotionUpdates()
        AppEventManager.sharedInstance.logAppEvent(event: "devicemotion_off", msg: "DeviceMotion collection off")
    }

    func finishCollecting() -> Promise<Void> {
        print("Finishing \(self.storeType) collecting")
        self.pauseCollecting()
        self.store = nil
        return DataStorageManager.sharedInstance.closeStore(self.storeType)
    }
}
