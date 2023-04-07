import Foundation
import ObjectMapper

/// the upload data file post request
struct UploadRequest: Mappable, ApiRequest {
    static let apiEndpoint = "/upload/ios/"
    typealias ApiReturnType = BodyResponse

    var fileName: String?
    var fileData: String?

    init?(map: Map) {}
    init(fileName: String, filePath: String) {
        self.fileName = fileName
    }

    // Mappable
    mutating func mapping(map: Map) {
        self.fileName <- map["file_name"]
        self.fileData <- map["file"]
    }
}
