import Foundation
import ObjectMapper

/// The register participant for study post request
struct RegisterStudyRequest: Mappable, ApiRequest {
    static let apiEndpoint = "/register_user/ios/"
    typealias ApiReturnType = StudySettings

    var patientId: String?
    var phoneNumber: String?
    var newPassword: String?
    var appVersion: String?

    var osVersion: String?
    var osName: String?
    var product: String?
    var model: String?
    var brand = "apple"
    var manufacturer = "apple"

    init() {
        if let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            self.appVersion = version
        }
        let uiDevice = UIDevice.current
        self.osName = uiDevice.systemName
        self.osVersion = uiDevice.systemVersion
        self.product = uiDevice.model
        self.model = platform()
    }

    init?(map: Map) {}
    init(patientId: String, phoneNumber: String, newPassword: String) {
        self.init()
        self.patientId = patientId
        self.phoneNumber = phoneNumber
        self.newPassword = newPassword
    }

    // Mappable
    mutating func mapping(map: Map) {
        self.patientId <- map["patient_id"]
        self.phoneNumber <- map["phone_number"]
        self.newPassword <- map["new_password"]
        self.appVersion <- map["beiwe_version"]
        self.osVersion <- map["os_version"]
        self.osName <- map["device_os"]
        self.product <- map["product"]
        self.model <- map["model"]
        self.brand <- map["brand"]
        self.manufacturer <- map["manufacturer"]
    }
}
