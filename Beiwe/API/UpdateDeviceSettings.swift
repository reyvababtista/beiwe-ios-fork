// import Foundation
// import ObjectMapper
// 
// /// update the device settings
// struct ChangePasswordRequest: Mappable, ApiRequest {
//     static let apiEndpoint = "get_latest_device_settings/ios/"
//     typealias ApiReturnType = BodyResponse
// 
//     var newPassword: String?
// 
//     init(newPassword: String) {
//         self.newPassword = newPassword
//     }
// 
//     init?(map: Map) {}
// 
//     // Mappable
//     mutating func mapping(map: Map) {
//         self.newPassword <- map["new_password"]
//     }
// }
