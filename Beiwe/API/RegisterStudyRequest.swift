import Foundation
import ObjectMapper

/// The register participant for study post request
struct RegisterStudyRequest: Mappable, ApiRequest {
    static let apiEndpoint = "/register_user/ios/"
    typealias ApiReturnType = StudySettings

    // default init
    var brand = "apple"
    var manufacturer = "apple"
    var appVersion: String?
    var osName: String?
    var osVersion: String?
    var product: String?
    var model: String?
    
    // custom init
    var patientId: String?
    var phoneNumber: String?
    var newPassword: String?

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
        // default init (always redundant? when is this functioon even called in the object lifecycle)
        self.brand <- map["brand"]
        self.manufacturer <- map["manufacturer"]
        self.appVersion <- map["beiwe_version"]
        self.osName <- map["device_os"]
        self.osVersion <- map["os_version"]
        self.product <- map["product"]
        self.model <- map["model"]
        // custom init
        self.patientId <- map["patient_id"]
        self.phoneNumber <- map["phone_number"]
        self.newPassword <- map["new_password"]
    }
}
