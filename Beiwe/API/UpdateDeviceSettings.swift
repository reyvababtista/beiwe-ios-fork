import Foundation
import ObjectMapper

/// update the device settings
struct UpdateDeviceSettingsRequest: Mappable, ApiRequest {
    static let apiEndpoint = "/get_latest_device_settings/ios/"
    typealias ApiReturnType = BodyResponse

    init?(map: Map) {}
    init() {}

    // Mappable
    mutating func mapping(map: Map) {}
}
