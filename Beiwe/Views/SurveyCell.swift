//
//  SurveyCell.swift
//  Beiwe
//
//  Created by Keary Griffin on 4/21/16.
//  Copyright © 2016 Rocketfarm Studios. All rights reserved.
//

import Foundation
import Hakuba

class SurveyCellModel: CellModel {
    let activeSurvey: ActiveSurvey

    init(activeSurvey: ActiveSurvey, selectionHandler: @escaping SelectionHandler) {
        self.activeSurvey = activeSurvey
        super.init(cell: SurveyCell.self, selectionHandler: selectionHandler)
    }
}

class SurveyCell: Cell, CellType {
    typealias CellModel = SurveyCellModel

    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var newLabel: UILabel!

    override func configure() {
        guard let cellmodel = cellmodel else {
            return
        }

        var desc: String
        if let surveyType = cellmodel.activeSurvey.survey?.surveyType, surveyType == .AudioSurvey {
            desc = NSLocalizedString("survey_type_audio", comment: "")
        } else {
            desc = NSLocalizedString("survey_type_tracking", comment: "")
        }
        self.descriptionLabel.text = desc
        if cellmodel.activeSurvey.survey?.alwaysAvailable ?? false {
            self.newLabel.text = NSLocalizedString("survey_status_available", comment: "")
        } else {
            self.newLabel.text = (cellmodel.activeSurvey.bwAnswers.count > 0) ? NSLocalizedString("survey_status_incomplete", comment: "") : NSLocalizedString("survey_status_new", comment: "")
        }
        backgroundColor = UIColor.clear
        // selectionStyle = UITableViewCellSelectionStyle.None;
        let bgColorView = UIView()
        bgColorView.backgroundColor = AppColors.highlightColor
        selectedBackgroundView = bgColorView
        isSelected = false
    }
}
