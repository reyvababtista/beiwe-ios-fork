import EmitterKit
import Eureka
import UIKit

// Um. this isn't used

class TaskListViewController: FormViewController {
    let dateFormatter = DateFormatter()
    var listeners: [Listener] = []
    
    let pendingSection = Section(NSLocalizedString("pending_study_tasks_title", comment: ""))  // The class representing the sections in a Eureka form
    let surveySelected = Event<String>()

    override func viewDidLoad() {
        super.viewDidLoad()
        form +++ self.pendingSection
        // Do any additional setup after loading the view... ?
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    /// This is the code to populate the survey list on the main screen
    // this is not explicitly called anywhere in the codebase
    func loadSurveys() -> Int {
        self.dateFormatter.dateFormat = "MMM d h:mm a"  // this doesn't appear to have another appropriate place to get set
        var cnt = 0
        self.pendingSection.removeAll()
        
        if let  activeSurveys: [String : ActiveSurvey] = StudyManager.sharedInstance.currentStudy?.activeSurveys {
            let sortedSurveys: [Dictionary<String, ActiveSurvey>.Element] = activeSurveys.sorted { (s1: Dictionary<String, ActiveSurvey>.Element, s2:  Dictionary<String, ActiveSurvey>.Element) -> Bool in
                s1.1.received > s2.1.received
            }
                
            for (id, survey) in sortedSurveys {
                // id is a string, survey is an ActiveSurvey
                if let surveyType = survey.survey?.surveyType, !survey.isComplete {
                    cnt += 1
                    let dt = Date(timeIntervalSince1970: survey.received)
                    let sdt = self.dateFormatter.string(from: dt)
                    
                    // determine the title to place on the survey, its a localizeable string.
                    // surveyType is declared as an enum, the case-switch statement has correctness enforced for all possible cases.
                    var title: String
                    switch surveyType {
                    case .TrackingSurvey:
                        title = NSLocalizedString("tracking_survey_title", comment: "")
                    case .AudioSurvey:
                        title = NSLocalizedString("audio_survey_title", comment: "")
                    }
                    title = title + NSLocalizedString("received_abbreviation", comment: "") + sdt
                    
                    self.pendingSection <<< ButtonRow(id) {
                        $0.title = title
                    }
                    .onCellSelection {
                        [unowned self] (cell: ButtonCellOf<String>, row: ButtonRow) in
                        self.surveySelected.emit(id)  // emit emits an event...?
                    }
                }
            }
        }
        return cnt
    }
    
    /* MARK: - Navigation

     // In a storyboard-based application, you will often want to do a little preparation before navigation
     override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
         // Get the new view controller using segue.destinationViewController.
         // Pass the selected object to the new view controller.
     } */
}
