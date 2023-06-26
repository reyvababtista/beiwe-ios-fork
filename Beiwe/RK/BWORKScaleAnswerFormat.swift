import Foundation
import ResearchKit

// our slightly customized question slider
class BWORKScaleAnswerFormat: ORKScaleAnswerFormat {
    override func validateParameters() {
        // We want more maximum steps, and validate our own params
    }
}
