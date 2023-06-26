import Foundation
import ObjectMapper

// used when ssetting up text questions, its a database backing
struct OneSelection: Mappable {
    var text: String = ""
    init?(map: Map) {}

    // Mappable
    mutating func mapping(map: Map) {
        self.text <- map["text"]
    }
}
