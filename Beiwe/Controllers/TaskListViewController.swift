//
//  TaskListViewController.swift
//  Beiwe
//
//  Created by Keary Griffin on 4/6/16.
//  Copyright © 2016 Rocketfarm Studios. All rights reserved.
//

import EmitterKit
import Eureka
import UIKit

class TaskListViewController: FormViewController {
    let surveySelected = Event<String>()
    let pendingSection = Section(NSLocalizedString("pending_study_tasks_title", comment: ""))
    let dateFormatter = DateFormatter()
    var listeners: [Listener] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        form +++ self.pendingSection

        // Do any additional setup after loading the view.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func loadSurveys() -> Int {
        self.dateFormatter.dateFormat = "MMM d h:mm a"
        var cnt = 0
        self.pendingSection.removeAll()

        if let activeSurveys = StudyManager.sharedInstance.currentStudy?.activeSurveys {
            let sortedSurveys = activeSurveys.sorted { s1, s2 -> Bool in
                s1.1.received > s2.1.received
            }

            for (id, survey) in sortedSurveys {
                if let surveyType = survey.survey?.surveyType, !survey.isComplete {
                    cnt = cnt + 1
                    var title: String
                    switch surveyType {
                    case .TrackingSurvey:
                        title = NSLocalizedString("tracking_survey_title", comment: "")
                    case .AudioSurvey:
                        title = NSLocalizedString("audio_survey_title", comment: "")
                    }
                    let dt = Date(timeIntervalSince1970: survey.received)
                    let sdt = self.dateFormatter.string(from: dt)
                    title = title + NSLocalizedString("received_abbreviation", comment: "") + sdt
                    self.pendingSection <<< ButtonRow(id) {
                        $0.title = title
                    }
                    .onCellSelection {
                        [unowned self] cell, row in
                        self.surveySelected.emit(id)
                    }
                }
            }
        }
        return cnt
    }
    
    /*
     // MARK: - Navigation

     // In a storyboard-based application, you will often want to do a little preparation before navigation
     override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
         // Get the new view controller using segue.destinationViewController.
         // Pass the selected object to the new view controller.
     }
     */
}
