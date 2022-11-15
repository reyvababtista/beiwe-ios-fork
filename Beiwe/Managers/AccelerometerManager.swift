import CoreMotion
import Foundation
import PromiseKit

class AccelerometerManager: DataServiceProtocol {
    let motionManager = AppDelegate.sharedInstance().motionManager

    let headers = ["timestamp", "accuracy", "x", "y", "z"]
    let storeType = "accel"
    var store: DataStorage?
    var offset: Double = 0

    func initCollecting() -> Bool {
        guard motionManager.isAccelerometerAvailable else {
            log.info("Accel not available.  Not initializing collection")
            return false
        }
        // NSTimeInterval of uptime i.e. the delta: now - bootTime = boottime as unix timestamp
        offset = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        store = DataStorageManager.sharedInstance.createStore(storeType, headers: headers)
        let frequency_base = StudyManager.sharedInstance.currentStudy?.studySettings?.accelerometerFrequency ?? 10
        motionManager.accelerometerUpdateInterval = 1.0 / Double(frequency_base)
        // print("accelerometerUpdateInterval: \(motionManager.accelerometerUpdateInterval)")
        return true
    }

    func startCollecting() {
        log.info("Turning \(storeType) collection on")
        // print("accelerometerUpdateInterval: \(motionManager.accelerometerUpdateInterval)")
        let queue = OperationQueue()
        motionManager.startAccelerometerUpdates(to: queue) {
            accelData, error in
            if let accelData = accelData {
                var data: [String] = []
                data.append(String(Int64((accelData.timestamp + self.offset) * 1000)))
                data.append("unknown")
                data.append(String(accelData.acceleration.x))
                data.append(String(accelData.acceleration.y))
                data.append(String(accelData.acceleration.z))
                self.store?.store(data)
            }
        }
        AppEventManager.sharedInstance.logAppEvent(event: "accel_on", msg: "Accel collection on")
    }

    func pauseCollecting() {
        log.info("Pausing \(storeType) collection")
        motionManager.stopAccelerometerUpdates()
        store?.flush()
        AppEventManager.sharedInstance.logAppEvent(event: "accel_off", msg: "Accel collection off")
    }

    func finishCollecting() -> Promise<Void> {
        print("Finishing \(storeType) collecting")
        pauseCollecting()
        store = nil
        return DataStorageManager.sharedInstance.closeStore(storeType)
    }
}
