import EmitterKit
import Foundation
import PromiseKit

class AppEventManager: DataServiceProtocol {
    static let sharedInstance = AppEventManager()
    var isCollecting: Bool = false
    var launchTimestamp: Date = Date()
    var launchOptions: String = ""
    var launchId: String {
        return String(Int64(self.launchTimestamp.timeIntervalSince1970 * 1000))
    }

    var seq = 0
    var didLogLaunch: Bool = false

    let storeType = "ios_log"
    let headers = ["timestamp", "launchId", "memory", "battery", "event", "msg", "d1", "d2", "d3", "d4"]
    var store: DataStorage?
    var listeners: [Listener] = []
    var isStoreOpen: Bool {
        return self.store != nil
    }

    func didLaunch(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        self.launchOptions = ""
        self.launchTimestamp = Date()
        if (launchOptions?.index(forKey: UIApplication.LaunchOptionsKey.location)) != nil {
            self.launchOptions = "location"
            /*
             let localNotif = UILocalNotification()
             //localNotif.fireDate = currentDate

             let body: String = "Beiwe was Launched in the background"

             localNotif.alertBody = body
             localNotif.soundName = UILocalNotificationDefaultSoundName
             UIApplication.shared.scheduleLocalNotification(localNotif)
              */
        }
        /*
         if let launchOptions = launchOptions {
             for (kind, _) in launchOptions {
                 if (self.launchOptions != "") {
                     self.launchOptions = self.launchOptions + ":"
                 }
                 self.launchOptions = self.launchOptions + String(describing: kind)
             }
         }
          */
        log.info("AppEvent didLaunch, launchId: \(self.launchId), options: \(self.launchOptions)")
    }

    /*
     func didLockUnlock(_ isLocked: Bool) {
         log.info("Lock state data changed: \(isLocked)")
         var data: [String] = [ ]
         data.append(String(Int64(Date().timeIntervalSince1970 * 1000)))
         let state: String = isLocked ? "Locked" : "Unlocked"
         data.append(state)
         data.append(String(UIDevice.current.batteryLevel))

         self.store?.store(data)
         self.store?.flush()

     }
      */

    func getMemory() -> String {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            let usedMegabytes = taskInfo.resident_size / 1000000
            // print("used megabytes: \(usedMegabytes)")
            return String(usedMegabytes)
        } else {
            print("Error with task_info(): " +
                (String(cString: mach_error_string(kerr), encoding: String.Encoding.ascii) ?? "unknown error"))
            return ""
        }
    }

    func logAppEvent(event: String, msg: String = "", d1: String = "", d2: String = "", d3: String = "", d4: String = "") {
        if self.store == nil {
            return
        }
        var data: [String] = []
        data.append(String(Int64(Date().timeIntervalSince1970 * 1000)))
        data.append(self.launchId)
        data.append(self.getMemory())
        data.append(String(UIDevice.current.batteryLevel))
        data.append(event)
        data.append(msg)
        data.append(d1)
        data.append(d2)
        data.append(d3)
        // data.append(d4)
        data.append(String(self.seq))
        self.seq = self.seq + 1

        self.store?.store(data)
        self.store?.flush()
    }

    func initCollecting() -> Bool {
        if self.store != nil {
            return true
        }
        self.store = DataStorageManager.sharedInstance.createStore(self.storeType, headers: self.headers)
        if !self.didLogLaunch {
            self.didLogLaunch = true
            var appVersion = ""
            if let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                appVersion = version
            }
            self.logAppEvent(event: "launch", msg: "Application launch", d1: self.launchOptions, d2: appVersion)
        }
        return true
    }

    func startCollecting() {
        log.info("Turning \(self.storeType) collection on")
        self.logAppEvent(event: "collecting", msg: "Collecting Data")
        self.isCollecting = true
    }

    func pauseCollecting() {
        self.isCollecting = false
        log.info("Pausing \(self.storeType) collection")
        self.listeners = []
        self.store!.flush()
    }

    func finishCollecting() -> Promise<Void> {
        log.info("Finish \(self.storeType) collection")
        self.logAppEvent(event: "stop_collecting", msg: "Stop Collecting Data")
        self.pauseCollecting()
        self.store = nil
        return DataStorageManager.sharedInstance.closeStore(self.storeType)
    }
}

// class DevLogManager: DataServiceProtocol {
//     static let sharedInstance = AppEventManager()
//     var isCollecting: Bool
//     let storeType = "dev_log"
//     let headers = ["timestamp", "ET"]
//     var store: DataStorage?
//     var listeners: [Listener] = []
//
//     var isStoreOpen: Bool {
//         return self.store != nil
//     }
//
//     func logAppEvent(_ statement: String) {
//         // literally the timestamp followed by the statement:
//         let date = Date()
//         self.store?.store(String(Int64(date.timeIntervalSince1970 * 1000)) + "," + date.ISO8601Format() + "," + statement)
//     }
//
//     func initCollecting() -> Bool {
//         if self.store != nil {
//             return true
//         }
//         self.store = DataStorageManager.sharedInstance.createStore(self.storeType, headers: self.headers)
//         return true
//     }
//
//     func startCollecting() {
//         log.info("Turning \(self.storeType) collection on")
//         self.logAppEvent("dev log start")
//         self.isCollecting = true
//     }
//
//     func pauseCollecting() {
//         self.isCollecting = false
//         log.info("Pausing \(self.storeType) collection")
//         self.logAppEvent("dev log pause")
//         self.listeners = []
//         self.store!.flush()
//     }
//
//     func finishCollecting() -> Promise<Void> {
//         log.info("Finish \(self.storeType) collection")
//         self.pauseCollecting()
//         self.logAppEvent("dev log end")
//         self.store = nil
//         return DataStorageManager.sharedInstance.closeStore(self.storeType)
//     }
// }
