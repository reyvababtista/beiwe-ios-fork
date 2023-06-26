import Foundation
import Hakuba

class SurveyCellModel: CellModel {
    let activeSurvey: ActiveSurvey

    init(activeSurvey: ActiveSurvey, selectionHandler: @escaping SelectionHandler) {
        self.activeSurvey = activeSurvey
        super.init(cell: SurveyCell.self, selectionHandler: selectionHandler)
    }
}

/// The survey button
class SurveyCell: Cell, CellType {
    typealias CellModel = SurveyCellModel

    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var newLabel: UILabel!

    override func configure() {
        guard let cellmodel = cellmodel else { // 99% sure this guard is impossible to trigger. subclasses?
            return
        }
        
        // set the type of survey, audio or tracking survey, and set the descriptive text
        var desc: String
        if let surveyType = cellmodel.activeSurvey.survey?.surveyType, surveyType == .AudioSurvey {
            desc = NSLocalizedString("survey_type_audio", comment: "")
        } else {
            desc = NSLocalizedString("survey_type_tracking", comment: "")
        }
        self.descriptionLabel.text = desc
        
        // always-available survey status
        if cellmodel.activeSurvey.survey?.alwaysAvailable ?? false {
            self.newLabel.text = NSLocalizedString("survey_status_available", comment: "")
        } else {
            self.newLabel.text = (cellmodel.activeSurvey.bwAnswers.count > 0) ? NSLocalizedString("survey_status_incomplete", comment: "") : NSLocalizedString("survey_status_new", comment: "")
        }
        
        // UI stuff.
        backgroundColor = UIColor.clear // allow the background color of the main screen to be visible (otherwise its white/black based on dark/light mode)
        // selectionStyle = UITableViewCell.SelectionStyle.none // wut?
        let bgColorView = UIView()
        bgColorView.backgroundColor = AppColors.highlightColor
        selectedBackgroundView = bgColorView
        isSelected = false
    }
}
