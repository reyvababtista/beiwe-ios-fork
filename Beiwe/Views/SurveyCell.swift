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
        
        // if we have a survey name append it to the cell text.
        if let name = cellmodel.activeSurvey.survey?.name {
            if !(name.isEmpty) {
                desc = desc + " - " + name
            }
        }
        self.descriptionLabel.text = desc
        
        // Originally this was 40, needed to make it larger to contain survey names.
        cellmodel.height = 90
        
        // descriptionLabel.showsExpansionTextWhenTruncated = true // nothing obvious
        // descriptionLabel.adjustsFontForContentSizeCategory = true // already true
        self.descriptionLabel.allowsDefaultTighteningForTruncation = true
        
        // some other explored ui properties
        // cellmodel.dynamicHeightEnabled = true - ok, uh, this causes a crash on the NSLocalizedString lookup? wtf?
        // descriptionLabel.numberOfLines = 10  // set to 4 in the main storyboard, does not automatically resiize
        // descriptionLabel.adjustsFontSizeToFitWidth = true  // this is too clunky, we've made it bigger.
        
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
