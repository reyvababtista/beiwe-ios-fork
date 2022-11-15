import CoreMotion
import Foundation
import PromiseKit

class GyroManager: DataServiceProtocol {
    let motionManager = AppDelegate.sharedInstance().motionManager

    let headers = ["timestamp", "x", "y", "z"]
    let storeType = "gyro"
    var store: DataStorage?  // TODO: make this non-optional (breaks protocol I think)
    var offset: Double = 0

    func initCollecting() -> Bool {
        guard motionManager.isGyroAvailable else {
            log.info("Gyro not available.  Not initializing collection")
            return false
        }
        // NSTimeInterval of uptime i.e. the delta: now - bootTime = boottime as unix timestamp
        self.offset = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        store = DataStorageManager.sharedInstance.createStore(storeType, headers: headers)
        
        // ug, currentstudy and study settings are optional so can't rely on the default gyroFrequency, have to hardcode it
        let frequency_base = StudyManager.sharedInstance.currentStudy?.studySettings?.gyroFrequency ?? 10
        motionManager.gyroUpdateInterval = 1.0 / Double(frequency_base)
        // print("gyroUpdateInterval: \(motionManager.gyroUpdateInterval)")
        return true
    }

    func startCollecting() {
        log.info("Turning \(storeType) collection on")
        // print("gyroUpdateInterval: \(motionManager.gyroUpdateInterval)")
        let queue = OperationQueue()
        motionManager.startGyroUpdates(to: queue) {
            gyroData, error in
            if let gyroData = gyroData {
                var data: [String] = []
                data.append(String(Int64((gyroData.timestamp + self.offset) * 1000)))
                data.append(String(gyroData.rotationRate.x))
                data.append(String(gyroData.rotationRate.y))
                data.append(String(gyroData.rotationRate.z))
                self.store?.store(data)
            }
        }
        AppEventManager.sharedInstance.logAppEvent(event: "gyro_on", msg: "Gyro collection on")
    }
    
    func pauseCollecting() {
        log.info("Pausing \(storeType) collection")
        motionManager.stopGyroUpdates()
        AppEventManager.sharedInstance.logAppEvent(event: "gyro_off", msg: "Gyro collection off")
    }

    func finishCollecting() -> Promise<Void> {
        print("Finishing \(storeType) collecting")
        pauseCollecting()
        store = nil
        return DataStorageManager.sharedInstance.closeStore(storeType)
    }
}
