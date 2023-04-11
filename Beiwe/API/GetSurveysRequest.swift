import Foundation
import ObjectMapper

/// the download surveys endpoint
struct GetSurveysRequest: Mappable, ApiRequest {
    static let apiEndpoint = "/download_surveys/ios/"
    typealias ApiReturnType = Survey

    init() {}
    init?(map: Map) {}

    // Mappable
    mutating func mapping(map: Map) {}
}
