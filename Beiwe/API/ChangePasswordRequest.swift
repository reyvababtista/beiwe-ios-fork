import Foundation
import ObjectMapper

/// request to the set password endpoint on the beiwe backend
struct ChangePasswordRequest: Mappable, ApiRequest {
    static let apiEndpoint = "/set_password/ios/"
    typealias ApiReturnType = BodyResponse

    var newPassword: String?

    init(newPassword: String) {
        self.newPassword = newPassword
    }

    init?(map: Map) {}

    // Mappable
    mutating func mapping(map: Map) {
        self.newPassword <- map["new_password"]
    }
}
