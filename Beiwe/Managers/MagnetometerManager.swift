//
//  MagnetometerManager.swift
//  Beiwe
//
//  Created by Keary Griffin on 4/3/16.
//  Copyright © 2016 Rocketfarm Studios. All rights reserved.
//

import CoreMotion
import Foundation
import PromiseKit

class MagnetometerManager: DataServiceProtocol {
    let motionManager = AppDelegate.sharedInstance().motionManager

    let headers = ["timestamp", "x", "y", "z"]
    let storeType = "magnetometer"
    var store: DataStorage?
    var offset: Double = 0

    func initCollecting() -> Bool {
        guard self.motionManager.isMagnetometerAvailable else {
            log.info("Magnetometer not available.  Not initializing collection")
            return false
        }

        self.store = DataStorageManager.sharedInstance.createStore(self.storeType, headers: self.headers)
        // Get NSTimeInterval of uptime i.e. the delta: now - bootTime
        let uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
        // Now since 1970
        let nowTimeIntervalSince1970: TimeInterval = Date().timeIntervalSince1970
        // Voila our offset
        self.offset = nowTimeIntervalSince1970 - uptime
        self.motionManager.magnetometerUpdateInterval = 0.1

        return true
    }

    func startCollecting() {
        log.info("Turning \(self.storeType) collection on")
        let queue = OperationQueue()

        self.motionManager.startMagnetometerUpdates(to: queue) {
            magData, _ in

            if let magData = magData {
                var data: [String] = []
                let timestamp: Double = magData.timestamp + self.offset
                data.append(String(Int64(timestamp * 1000)))
                // data.append(AppDelegate.sharedInstance().modelVersionId);
                data.append(String(magData.magneticField.x))
                data.append(String(magData.magneticField.y))
                data.append(String(magData.magneticField.z))

                self.store?.store(data)
            }
        }
        AppEventManager.sharedInstance.logAppEvent(event: "magnetometer_on", msg: "Magnetometer collection on")
    }

    func pauseCollecting() {
        log.info("Pausing \(self.storeType) collection")
        self.motionManager.stopMagnetometerUpdates()
        AppEventManager.sharedInstance.logAppEvent(event: "magnetometer_off", msg: "Magnetometer collection off")
    }

    func finishCollecting() -> Promise<Void> {
        print("Finishing \(self.storeType) collecting")
        self.pauseCollecting()
        self.store = nil
        return DataStorageManager.sharedInstance.closeStore(self.storeType)
    }
}
