import ObjectMapper

// all the question types for a survey
enum SurveyQuestionType: String {
    case InformationText = "info_text_box"
    case Slider = "slider"
    case RadioButton = "radio_button"
    case Checkbox = "checkbox"
    case FreeResponse = "free_response"
    case Date = "date"
    case Time = "time"
    case DateTime = "date_time"
}

// all the entry field types for a survey
enum TextFieldType: String {
    case SingleLine = "SINGLE_LINE_TEXT"
    case MultiLine = "MULTI_LINE_TEXT"
    case Numeric = "NUMERIC"
}

// mappable (json-backed database object) of a question
struct GenericSurveyQuestion: Mappable {
    var questionId = ""
    var prompt: String?
    var questionType: SurveyQuestionType? // unclear why this is optional...
    var maxValue: Int?
    var minValue: Int?
    var selectionValues: [OneSelection] = []
    var textFieldType: TextFieldType?
    var displayIf: [String: AnyObject]?
    var required = false
    
    init?(map: Map) {}

    // Mappable
    mutating func mapping(map: Map) {
        self.questionId <- map["question_id"]
        self.prompt <- map["prompt"]
        self.prompt <- map["question_text"]
        self.questionType <- map["question_type"]
        self.maxValue <- (map["max"], transformJsonStringInt)
        self.minValue <- (map["min"], transformJsonStringInt)
        self.textFieldType <- map["text_field_type"]
        self.selectionValues <- map["answers"]
        self.displayIf <- map["display_if"]
        self.required <- map["required"] // well that's interesting, when a key is missing it Doesn't Crash AND the default value is respected
    }
}
