import Alamofire
import Foundation
import ObjectMapper
import PromiseKit

/// a type used in the api endpoint classes
protocol ApiRequest {
    associatedtype ApiReturnType: Mappable
    static var apiEndpoint: String { get }
}

/// error types for api requests
enum ApiErrors: Error {
    case failedStatus(code: Int)
    case fileNotFound
}

/// One(?) of the request types... no clue how this works yet, but mappables magically convert json
struct BodyResponse: Mappable {
    var body: String?

    init?(map: Map) {}
    init(body: String?) {
        self.body = body
    }

    // I don't know what this function does, it clearly sets body too the contents of the map at key "body"
    mutating func mapping(map: Map) {
        self.body <- map["body"]
    }
}

/// Our general purpose api endpoint hitting code.
class ApiManager {
    static let sharedInstance = ApiManager()
    fileprivate let defaultBaseApiUrl = Configuration.sharedInstance.settings["server-url"] as! String
    fileprivate var deviceId = PersistentAppUUID.sharedInstance.uuid

    fileprivate var hashedPassword = ""

    // setter hashes the password
    var password: String {
        set {
            self.hashedPassword = Crypto.sharedInstance.sha256Base64URL(newValue)
        }
        get {
            return ""
        }
    }

    // some dumb default values
    var fcmToken: String?
    var patientId: String = ""
    var customApiUrl: String?
    
    // get the url
    var baseApiUrl: String {
        return self.customApiUrl ?? self.defaultBaseApiUrl
    }
    
    func setDefaultParameters(_ parameters: inout [String: Any], skip_password: Bool = false) {
        // credential parameters
        if !skip_password {
            parameters["password"] = self.hashedPassword
        }
        parameters["patient_id"] = self.patientId
        
        parameters["device_id"] = PersistentAppUUID.sharedInstance.uuid  // deprecated?
        
        // basic device info, will be displayed on the participant page
        parameters["version_code"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        // parameters["version_name"] =  // There isn't really anything to stick into this one for ios
        parameters["os_version"] = UIDevice.current.systemVersion
        parameters["timezone"] = TimeZone.current.identifier
        
        // various device metrics to be improved on over time, meant for developer use to debug issues.
        var device_status_report = [String: String]()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm E, d MMM y"
        device_status_report["timestamp"] = formatter.string(from: Date()) + " " + TimeZone.current.identifier
        
        // UIDevice... Stuff?
        device_status_report["battery_level"] = String(UIDevice.current.batteryLevel)
        device_status_report["battery_state"] = String(UIDevice.current.batteryState.rawValue)
        device_status_report["device_model"] = UIDevice.current.model
        device_status_report["proximity_monitoring_enabled"] = UIDevice.current.isProximityMonitoringEnabled.description
        
        // Location services configuration
        device_status_report["location_services_enabled"] = Ephemerals.locationServicesEnabledDescription
        device_status_report["location_significant_change_monitoring_enabled"] = Ephemerals.significantLocationChangeMonitoringAvailable
        device_status_report["location_permission"] = switch CLLocationManager.authorizationStatus() {
        case .notDetermined: "not_determined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorizedAlways: "authorized_always"
        case .authorizedWhenInUse: "authorized_when_in_use"
        @unknown default: "unknown: '\(CLLocationManager.authorizationStatus().rawValue)'"
        }
        
        // notification permissions, can be one of not_determined, denied, authorized, provisional, or ephemeral.
        device_status_report["notification_permission"] = Ephemerals.notification_permission
        
        // background refresh
        device_status_report["background_refresh_status"] = Ephemerals.backgroundRefreshStatus
        
        // object cannot fail to be serialized, data types are valid.
        // stupid. We need to convert a [String:String] to a json object, which is a Data (bytes) and then we need to convert THAT to a string.
        let statusAsJsonDictData = try! JSONSerialization.data(withJSONObject: device_status_report, options: [])
        parameters["device_status_report"] = String(data: statusAsJsonDictData, encoding: .utf8)!
    }

    /// This looks like it does literally nothing?
    static func serialErr() -> NSError {
        return NSError(domain: "com.rf.beiwe.studies", code: 2, userInfo: nil)
    }

    /// This function is used to Register for a study, it contains special logic for that scenario - WHY IS IT LIKE THAT THAT IS TERRIBLE THIS IS THE WRONG PLACE FOR THAT CODE.
    func makePostRequest<T: ApiRequest>(_ requestObject: T, password: String? = nil) -> Promise<(T.ApiReturnType, Int)> where T: Mappable {
        var parameters = requestObject.toJSON()
        parameters["password"] = (password == nil) ? self.hashedPassword : Crypto.sharedInstance.sha256Base64URL(password!) // I don't know what this line does
        self.setDefaultParameters(&parameters, skip_password: true)

        return Promise { (resolver: Resolver<(T.ApiReturnType, Int)>) in
            let request = Alamofire.request(baseApiUrl + T.apiEndpoint, method: .post, parameters: parameters)

            request.responseString { (response: DataResponse<String>) in
                switch response.result {
                // the code errored, I think
                case let .failure(error):
                    return resolver.reject(error)

                // the request received a response
                case .success:
                    let statusCode = response.response?.statusCode

                    // 400, and invalid error codes
                    if let statusCode = statusCode, statusCode < 200 || statusCode >= 400 {
                        return resolver.reject(ApiErrors.failedStatus(code: statusCode))
                    }

                    // casing for return type
                    var returnObject: T.ApiReturnType? // its a mappable?
                    
                    if T.ApiReturnType.self == BodyResponse.self {
                        // BodyResponse case
                        returnObject = BodyResponse(body: response.result.value) as? T.ApiReturnType
                    } else if T.ApiReturnType.self == StudySettings.self {
                        // StudySettings - this case is for registration, which is STUPID it SHOULD NOT BE HERE.
                        do {
                            // deserialize everything
                            var json = try JSONSerialization.jsonObject(with: Data(response.result.value?.utf8 ?? "".utf8)) as? [String: Any]
                            // if there is no ios plist content insert this manual copy - gross, this is just Bad.
                            if json?["ios_plist"] is NSNull || json?["ios_plist"] == nil {
                                json?["ios_plist"] = [
                                    "CLIENT_ID": "",
                                    "REVERSED_CLIENT_ID": "",
                                    "API_KEY": "",
                                    "GCM_SENDER_ID": "",
                                    "PLIST_VERSION": "1",
                                    "BUNDLE_ID": "",
                                    "PROJECT_ID": "",
                                    "STORAGE_BUCKET": "",
                                    "IS_ADS_ENABLED": false,
                                    "IS_ANALYTICS_ENABLED": false,
                                    "IS_APPINVITE_ENABLED": true,
                                    "IS_GCM_ENABLED": true,
                                    "IS_SIGNIN_ENABLED": true,
                                    "GOOGLE_APP_ID": "",
                                    "DATABASE_URL": "",
                                ]
                            }
                            // the json variable passed in here to an Any type, this seems to be safe after years of use, ignore warning.
                            let jsonObject: Data? = try? JSONSerialization.data(withJSONObject: json, options: [])
                            // stringify the json object (eg this does _json_ validation)
                            if let jsonString = String(data: jsonObject!, encoding: .utf8) {
                                // and then this case is always a (the?) StudySettings object, but for obscure reasons we cannot reference it directly, apparently
                                // returnObject = Mapper<StudySettings>().map(JSONString: jsonString)
                                returnObject = Mapper<T.ApiReturnType>().map(JSONString: jsonString)
                            }
                        } catch {
                            log.error("Unable to create default firebase credentials plist")
                            AppEventManager.sharedInstance.logAppEvent(event: "push_notification", msg: "Unable to create default firebase credentials plist")
                        }

                    } else { // all other type cases
                        returnObject = Mapper<T.ApiReturnType>().map(JSONString: response.result.value ?? "")
                    }

                    // return
                    if let returnObject = returnObject { // returnObject exists, return
                        // this returnobject is one of two(?) types, either a bodyresponse or a StudySettings object
                        return resolver.fulfill((returnObject, statusCode ?? 0))
                    } else { // returnObject failed?
                        return resolver.reject(ApiManager.serialErr())
                    }
                }
            }
        }
    }

    func arrayPostRequest<T: ApiRequest>(_ requestObject: T) -> Promise<([T.ApiReturnType], Int)> where T: Mappable {
        var parameters = requestObject.toJSON()
        self.setDefaultParameters(&parameters)

        return Promise { (resolver: Resolver<([T.ApiReturnType], Int)>) in
            let request = Alamofire.request(baseApiUrl + T.apiEndpoint, method: .post, parameters: parameters)

            request.responseString { (response: DataResponse<String>) in
                switch response.result {
                case let .failure(error): // code error I think
                    resolver.reject(error)

                case .success:
                    let statusCode = response.response?.statusCode
                    // bad status codes
                    if let statusCode = statusCode, statusCode < 200 || statusCode >= 400 {
                        resolver.reject(ApiErrors.failedStatus(code: statusCode))
                    } else {
                        // FIXME: I may have screwed up this else clause, compare to original
                    
                        // get the return type, make an array of it, consume the json and set up to return it
                        var returnObject: [T.ApiReturnType]?
                        returnObject = Mapper<T.ApiReturnType>().mapArray(JSONString: response.result.value ?? "")
                        if let returnObject = returnObject {
                            resolver.fulfill((returnObject, statusCode ?? 0))
                        } else {
                            resolver.reject(ApiManager.serialErr())
                        }
                    }
                }
            }
        }
    }

    // /// this is going to replace the first chunk of that multipartFormData upload code below
    // func thingy(_ multipartFormData: MultipartFormData, parameters: [String: Any], file: URL) {
    //     // add the parameters part by part...
    //     for (k, v) in parameters {
    //         multipartFormData.append(String(describing: v).data(using: .utf8)!, withName: k)
    //     }
    //     // add the file...
    //     multipartFormData.append(file, withName: "file")
    // }

    func makeMultipartUploadRequest<T: ApiRequest>(_ requestObject: T, file: URL) -> Promise<(T.ApiReturnType, Int)> where T: Mappable {
        var parameters: [String: Any] = requestObject.toJSON()
        self.setDefaultParameters(&parameters)
        let url = self.baseApiUrl + T.apiEndpoint

        return Promise { (resolver: Resolver<(T.ApiReturnType, Int)>) in
            // this syntax is insane, what?
            Alamofire.upload(
                // this closure is absolutely gross, how to I refactor it out.
                multipartFormData: { (multipartFormData: MultipartFormData) in // add the parameters part by part...
                    for (k, v) in parameters {
                        multipartFormData.append(String(describing: v).data(using: .utf8)!, withName: k)
                    }
                    // add the file...
                    multipartFormData.append(file, withName: "file")
                },

                // these are actually more parameters, ignore header
                to: url, method: .post, // headers: header

                // oookay, I don't know what this is exaaactly, but it is a closure with some data - a string in some encoding that needs to be json transformed
                encodingCompletion: { (encodingResult: SessionManager.MultipartFormDataEncodingResult) in
                    switch encodingResult {
                    case let .success(upload, _, _): // upload is an UploadRequest
                        upload.responseString { (response: DataResponse<String>) in
                            switch response.result {
                            case let .failure(error): // hit a code error I think
                                resolver.reject(error)

                            case .success:
                                let statusCode = response.response?.statusCode
                                // bad return codes
                                if let statusCode = statusCode, statusCode < 200 || statusCode >= 400 {
                                    resolver.reject(ApiErrors.failedStatus(code: statusCode))
                                } else {
                                    // return type logic - there's only the one use so this can be dropped...
                                    var returnObject: T.ApiReturnType?
                                    
                                    // If its a BodyResponse, attempt a cast of response.result.value, which is an optional String. (is T.ApiReturnType is usually a text encoding?)
                                    // If its not a BodyResponse, process response.result.value as a json string.
                                    if T.ApiReturnType.self == BodyResponse.self { // Type.self is the [compile-time] value of a class type.
                                        returnObject = BodyResponse(body: response.result.value) as? T.ApiReturnType
                                    } else {
                                        returnObject = Mapper<T.ApiReturnType>().map(JSONString: response.result.value ?? "")
                                    }

                                    // return the object or error
                                    if let returnObject = returnObject {
                                        resolver.fulfill((returnObject, statusCode ?? 0))
                                    } else {
                                        resolver.reject(ApiManager.serialErr())
                                    }
                                }
                            }
                        }
                    case let .failure(encodingError):
                        resolver.reject(encodingError)
                    }
                }
            )
        }
    }
}
