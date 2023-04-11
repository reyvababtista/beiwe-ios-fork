import Foundation
import ObjectMapper

enum SurveyTypes: String {
    case AudioSurvey = "audio_survey"
    case TrackingSurvey = "tracking_survey"
}

struct Survey: Mappable {
    var surveyId: String?
    var surveyType: SurveyTypes?
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
}
