// import PromiseKit
// import Foundation
// import ObjectMapper
// 
// class AppInfo: ReclineObject {
//     static var instance: AppInfo?
//     static var data: AppInfo {
//         if let instance = AppInfo.instance {
//             return instance
//         }
//         
//         fatalError("AppInfo Accessed too early")
//     }
//     
//     var clientPublicKey: String?
//     
//     required init?(map: Map) {
//         super.init(map: map)
//     }
//     
//     init(clientPublicKey: String?) {
//         super.init()
//         self.clientPublicKey = clientPublicKey
//     }
//     
//     override func mapping(map: Map) {
//         self.clientPublicKey <- map["client_public_key"]
//     }
//     
//     func loadAppInfo() -> Promise<Bool> {
//         // get all the app infos? if there is more than one, error
//         return firstly { () -> Promise<[AppInfo]> in
//             Recline.shared.queryAll()
//         }.then { (appsInfo: [AppInfo]) -> Promise <Bool> in
//             // if there is more than one study, log a warning? this is pointless
//             if appsInfo.count > 1 {
//                 fatalError("Multiple Apps Info: \(appsInfo)")
//                 // log.warning("Multiple Apps Info: \(appsInfo)")
//             }
//             // grab the first study and the first study only, set the patient id (but not), real_study_loaded to true
//             if appsInfo.count > 0 {
//                 AppInfo.instance = appsInfo[0]
//                 // print("self.currentStudy.patientId: \(self.currentStudy?.patientId)")
//                 // AppDelegate.sharedInstance().setDebuggingUser(self.currentStudy?.patientId ?? "unknown") // this doesn't do anything...
//                 StudyManager.real_study_loaded = true
//             }
//             return .value(true)
//         }
//     }
// }
