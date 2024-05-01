import Foundation
import ObjectMapper

enum SurveyTypes: String {
    case AudioSurvey = "audio_survey"
    case TrackingSurvey = "tracking_survey"
}

struct Survey: Mappable, Equatable {
    var surveyId: String?
    var surveyType: SurveyTypes?
    var name = ""
    var timings: [[Int]] = []
    var triggerOnFirstDownload: Bool = false
    var randomize: Bool = false
    var numberOfRandomQuestions: Int?
    var randomizeWithMemory: Bool = false
    var questions: [GenericSurveyQuestion] = []
    var audioSurveyType: String = "compressed"
    var audioSampleRate = 44100
    var audioBitrate = 64000
    var alwaysAvailable = false

    init?(map: Map) {}

    // Mappable
    mutating func mapping(map: Map) {
        self.surveyId <- map["_id"]
        self.surveyType <- map["survey_type"]
        self.name <- map["name"]
        self.timings <- map["timings"]
        self.triggerOnFirstDownload <- map["settings.trigger_on_first_download"]
        self.randomize <- map["settings.randomize"]
        self.numberOfRandomQuestions <- map["settings.number_of_random_questions"]
        self.randomizeWithMemory <- map["settings.randomize_with_memory"]
        self.audioSurveyType <- map["settings.audio_survey_type"]
        self.audioSampleRate <- map["settings.sample_rate"]
        self.audioBitrate <- map["settings.bit_rate"]
        self.questions <- map["content"]
        self.alwaysAvailable <- map["settings.always_available"]
    }
    
    static func == (lhs: Survey, rhs: Survey) -> Bool {
        let surveyId = lhs.surveyId == rhs.surveyId
        let surveyType = lhs.surveyType == rhs.surveyType
        let name = lhs.name == rhs.name
        let timings = lhs.timings == rhs.timings
        let triggerOnFirstDownload = lhs.triggerOnFirstDownload == rhs.triggerOnFirstDownload
        let randomize = lhs.randomize == rhs.randomize
        let numberOfRandomQuestions = lhs.numberOfRandomQuestions == rhs.numberOfRandomQuestions
        let randomizeWithMemory = lhs.randomizeWithMemory == rhs.randomizeWithMemory
        let questions = lhs.questions == rhs.questions
        let audioSurveyType = lhs.audioSurveyType == rhs.audioSurveyType
        let audioSampleRate = lhs.audioSampleRate == rhs.audioSampleRate
        let audioBitrate = lhs.audioBitrate == rhs.audioBitrate
        let alwaysAvailable = lhs.alwaysAvailable == rhs.alwaysAvailable
        
        if !surveyId { print(lhs.surveyId, "!=", rhs.surveyId) }
        if !surveyType { print(lhs.surveyType, "!=", rhs.surveyType) }
        if !name { print(lhs.name, "!=", rhs.name) }
        if !timings { print(lhs.timings, "!=", rhs.timings) }
        if !triggerOnFirstDownload { print(lhs.triggerOnFirstDownload, "!=", rhs.triggerOnFirstDownload) }
        if !randomize { print(lhs.randomize, "!=", rhs.randomize) }
        if !numberOfRandomQuestions { print(lhs.numberOfRandomQuestions, "!=", rhs.numberOfRandomQuestions) }
        if !randomizeWithMemory { print(lhs.randomizeWithMemory, "!=", rhs.randomizeWithMemory) }
        if !questions { print(lhs.questions, "!=", rhs.questions) }
        if !audioSurveyType { print(lhs.audioSurveyType, "!=", rhs.audioSurveyType) }
        if !audioSampleRate { print(lhs.audioSampleRate, "!=", rhs.audioSampleRate) }
        if !audioBitrate { print(lhs.audioBitrate, "!=", rhs.audioBitrate) }
        if !alwaysAvailable { print(lhs.alwaysAvailable, "!=", rhs.alwaysAvailable) }
        
        return surveyId &&
            surveyType &&
            name &&
            timings &&
            triggerOnFirstDownload &&
            randomize &&
            numberOfRandomQuestions &&
            randomizeWithMemory &&
            questions &&
            audioSurveyType &&
            audioSampleRate &&
            audioBitrate &&
            alwaysAvailable
    }
}
