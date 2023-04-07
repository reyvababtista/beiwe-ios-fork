import Foundation
import ObjectMapper

/// this is a debug endpoint, it forces a notification to be sent to the app, the contents of which is not well defined.
struct TestNotificationRequest: Mappable, ApiRequest {
    static let apiEndpoint = "/send_survey_notification"
    typealias ApiReturnType = Survey
    var surveyID: String?
    init() {}
    init?(map: Map) {}

    // Mappable
    mutating func mapping(map: Map) {}
}
