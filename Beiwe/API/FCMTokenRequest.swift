import Foundation
import ObjectMapper

/// post request that sends the firebase token to the beiwe backend
struct FCMTokenRequest: Mappable, ApiRequest {
    static let apiEndpoint = "/set_fcm_token"
    typealias ApiReturnType = BodyResponse

    var fcmToken: String?

    init(fcmToken: String) {
        self.fcmToken = fcmToken
    }

    init?(map: Map) {}

    // Mappable
    mutating func mapping(map: Map) {
        self.fcmToken <- map["fcm_token"]
    }
}
