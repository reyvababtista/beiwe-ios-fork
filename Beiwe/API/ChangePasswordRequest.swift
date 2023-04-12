import Foundation
import ObjectMapper

/// request to the set password endpoint on the beiwe backend
struct ChangePasswordRequest: Mappable, ApiRequest {
    static let apiEndpoint = "/set_password/ios/"
    typealias ApiReturnType = BodyResponse

    var newPassword: String?

    init?(map: Map) {}
    init(newPassword: String) {
        self.newPassword = newPassword
    }

    // Mappable
    mutating func mapping(map: Map) {
        self.newPassword <- map["new_password"]
    }
}
