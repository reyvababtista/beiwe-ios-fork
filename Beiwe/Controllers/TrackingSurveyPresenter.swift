import Foundation
import ObjectMapper
import ResearchKit

// example json
// let contentJson = "{\"content\":[{\"answers\":[{\"text\":\"Never\"},{\"text\":\"Rarely\"},{\"text\":\"Occasionally\"},{\"text\":\"Frequently\"},{\"text\":\"Almost Constantly\"}],\"question_id\":\"6695d6c4-916b-4225-8688-89b6089a24d1\",\"question_text\":\"In the last 7 days, how OFTEN did you EAT BROCCOLI?\",\"question_type\":\"radio_button\"},{\"answers\":[{\"text\":\"None\"},{\"text\":\"Mild\"},{\"text\":\"Moderate\"},{\"text\":\"Severe\"},{\"text\":\"Very Severe\"}],\"display_if\":{\">\":[\"6695d6c4-916b-4225-8688-89b6089a24d1\",0]},\"question_id\":\"41d54793-dc4d-48d9-f370-4329a7bc6960\",\"question_text\":\"In the last 7 days, what was the SEVERITY of your CRAVING FOR BROCCOLI?\",\"question_type\":\"radio_button\"},{\"answers\":[{\"text\":\"Not at all\"},{\"text\":\"A little bit\"},{\"text\":\"Somewhat\"},{\"text\":\"Quite a bit\"},{\"text\":\"Very much\"}],\"display_if\":{\"and\":[{\">\":[\"6695d6c4-916b-4225-8688-89b6089a24d1\",0]},{\">\":[\"41d54793-dc4d-48d9-f370-4329a7bc6960\",0]}]},\"question_id\":\"5cfa06ad-d907-4ba7-a66a-d68ea3c89fba\",\"question_text\":\"In the last 7 days, how much did your CRAVING FOR BROCCOLI INTERFERE with your usual or daily activities, (e.g. eating cauliflower)?\",\"question_type\":\"radio_button\"},{\"display_if\":{\"or\":[{\"and\":[{\"<=\":[\"6695d6c4-916b-4225-8688-89b6089a24d1\",3]},{\"==\":[\"41d54793-dc4d-48d9-f370-4329a7bc6960\",2]},{\"<\":[\"5cfa06ad-d907-4ba7-a66a-d68ea3c89fba\",3]}]},{\"and\":[{\"<=\":[\"6695d6c4-916b-4225-8688-89b6089a24d1\",3]},{\"<\":[\"41d54793-dc4d-48d9-f370-4329a7bc6960\",3]},{\"==\":[\"5cfa06ad-d907-4ba7-a66a-d68ea3c89fba\",2]}]},{\"and\":[{\"==\":[\"6695d6c4-916b-4225-8688-89b6089a24d1\",4]},{\"<=\":[\"41d54793-dc4d-48d9-f370-4329a7bc6960\",1]},{\"<=\":[\"5cfa06ad-d907-4ba7-a66a-d68ea3c89fba\",1]}]}]},\"question_id\":\"9d7f737d-ef55-4231-e901-b3b68ca74190\",\"question_text\":\"While broccoli is a nutritious and healthful food, it's important to recognize that craving too much broccoli can have adverse consequences on your health.  If in a single day you find yourself eating broccoli steamed, stir-fried, and raw with a 'vegetable dip', you may be a broccoli addict.\\u000a\\u000aThis is an additional paragraph (following a double newline) warning you about the dangers of broccoli consumption.\",\"question_type\":\"info_text_box\"},{\"display_if\":{\"or\":[{\"and\":[{\"==\":[\"6695d6c4-916b-4225-8688-89b6089a24d1\",4]},{\"or\":[{\">=\":[\"41d54793-dc4d-48d9-f370-4329a7bc6960\",2]},{\">=\":[\"5cfa06ad-d907-4ba7-a66a-d68ea3c89fba\",2]}]}]},{\"or\":[{\">=\":[\"41d54793-dc4d-48d9-f370-4329a7bc6960\",3]},{\">=\":[\"5cfa06ad-d907-4ba7-a66a-d68ea3c89fba\",3]}]}]},\"question_id\":\"59f05c45-df67-40ed-a299-8796118ad173\",\"question_text\":\"OK, it sounds like your broccoli habit is getting out of hand.  Please call your clinician immediately.\",\"question_type\":\"info_text_box\"},{\"question_id\":\"9745551b-a0f8-4eec-9205-9e0154637513\",\"question_text\":\"How many pounds of broccoli per day could a woodchuck chuck if a woodchuck could chuck broccoli?\",\"question_type\":\"free_response\",\"text_field_type\":\"NUMERIC\"},{\"display_if\":{\"<\":[\"9745551b-a0f8-4eec-9205-9e0154637513\",10]},\"question_id\":\"cedef218-e1ec-46d3-d8be-e30cb0b2d3aa\",\"question_text\":\"That seems a little low.\",\"question_type\":\"info_text_box\"},{\"display_if\":{\"==\":[\"9745551b-a0f8-4eec-9205-9e0154637513\",10]},\"question_id\":\"64a2a19b-c3d0-4d6e-9c0d-06089fd00424\",\"question_text\":\"That sounds about right.\",\"question_type\":\"info_text_box\"},{\"display_if\":{\">\":[\"9745551b-a0f8-4eec-9205-9e0154637513\",10]},\"question_id\":\"166d74ea-af32-487c-96d6-da8d63cfd368\",\"question_text\":\"What?! No way- that's way too high!\",\"question_type\":\"info_text_box\"},{\"max\":\"5\",\"min\":\"1\",\"question_id\":\"059e2f4a-562a-498e-d5f3-f59a2b2a5a5b\",\"question_text\":\"On a scale of 1 (awful) to 5 (delicious) stars, how would you rate your dinner at Chez Broccoli Restaurant?\",\"question_type\":\"slider\"},{\"display_if\":{\">=\":[\"059e2f4a-562a-498e-d5f3-f59a2b2a5a5b\",4]},\"question_id\":\"6dd9b20b-9dfc-4ec9-cd29-1b82b330b463\",\"question_text\":\"Wow, you are a true broccoli fan.\",\"question_type\":\"info_text_box\"},{\"question_id\":\"ec0173c9-ac8d-449d-d11d-1d8e596b4ec9\",\"question_text\":\"THE END. This survey is over.\",\"question_type\":\"info_text_box\"}],\"settings\":{\"number_of_random_questions\":null,\"randomize\":false,\"randomize_with_memory\":false,\"trigger_on_first_download\":false},\"survey_type\":\"tracking_survey\",\"timings\":[[],[67500],[],[],[],[],[]]}"

class TrackingSurveyPresenter: NSObject, ORKTaskViewControllerDelegate {
    // generates 2 csv files, the survey answers, and the survey timings. Answers is obvious, timings is human interaction with the buttons of the app.
    static let headers = ["question id", "question type", "question text", "question answer options", "answer"]
    static let timingsHeaders = ["timestamp", "question id", "question type", "question text", "question answer options", "answer", "event"]
    static let surveyDataType = "surveyAnswers"
    static let timingDataType = "surveyTimings"

    // no clue
    var retainSelf: AnyObject?
    
    // info
    var surveyId: String?
    
    // survey pointers?
    var activeSurvey: ActiveSurvey? // live information for this survey
    var survey: Survey? // points to the json information for the survey
    
    // UI studd
    var parent: UIViewController?
    var surveyViewController: BWORKTaskViewController?
    
    // state
    var isComplete = false
    var questionIdToQuestion: [String: GenericSurveyQuestion] = [:] // questions have IDs, map of IDs to question objects
    var lastQuestion: [String: Bool] = [:] // I think this is the final question to be displayed, used to go to done-with-survey card. (poorly named, ambiguous with previous or prior question)
    /// uh what are these 2?
    var task: ORKTask? // well its the researchkit task...
    var valueChangeHandler: Debouncer<String>? // its a user input slow-downer, only functionally necessary for slider questions.
    
    // survey timings information
    let timingsName: String
    var timingsStore: DataStorage?
    
    // the current question (do display?)
    var currentQuestion: GenericSurveyQuestion?

    init(surveyId: String, activeSurvey: ActiveSurvey, survey: Survey) {
        self.timingsName = TrackingSurveyPresenter.timingDataType + "_" + surveyId // any reason we are setting this up early?
        
        // let tempSurvey = Mapper<Survey>().map(contentJson)
        // let questions = tempSurvey!.questions
        let questions = survey.questions

        super.init()
        self.surveyId = surveyId
        self.activeSurvey = activeSurvey
        self.survey = survey
        
        // timings file setup begins immediately
        self.timingsStore = DataStorageManager.sharedInstance.createStore(self.timingsName, headers: TrackingSurveyPresenter.timingsHeaders)
        self.timingsStore!.sanitize = true // ok, dumb factoring but here's where we set the sanitize flag
        
        // this TODO is ancient, its from Keary
        // TODO: handle if stepOrder is null, throw error if it is not valid if it is valid, figure out why and under what conditions
        guard let stepOrder = activeSurvey.stepOrder /* where questions.count > 0 */ else {
            log.error("Active survey has no stepOrder")
            return
        }
        
        // determine question count
        let numQuestions = survey.randomize ? min(questions.count, survey.numberOfRandomQuestions ?? 999) : questions.count

        var hasOptionalSteps: Bool = false
        var steps = [ORKStep]()
        
        for i in 0 ..< numQuestions {
            // iterate over questions in step order
            let question: GenericSurveyQuestion = questions[stepOrder[i]]
            if let _ = question.displayIf {
                hasOptionalSteps = true // flag for whether there is logic to display this question
            }
            
            // different logic for every question type (for some reason question type is optional)
            if let questionType = question.questionType {
                var step: ORKStep?
                
                switch questionType {
                case .Checkbox, .RadioButton:
                    // swift weirdness, you cannot do step = ORKQuestionStep(identifier: question.questionId)
                    let questionStep = ORKQuestionStep(identifier: question.questionId)
                    step = questionStep
                    // set up the question and its answers
                    questionStep.answerFormat = ORKTextAnswerFormat.choiceAnswerFormat(
                        with: questionType == .RadioButton ? .singleChoice : .multipleChoice,
                        // create a textChoice for every question answer
                        textChoices: question.selectionValues.enumerated().map { (index: Int, el: OneSelection) in
                            ORKTextChoice(text: el.text, value: index as NSNumber)
                        }
                    )
                
                case .FreeResponse:
                    let questionStep = ORKQuestionStep(identifier: question.questionId)
                    step = questionStep
                    // the 3 types of text entry options - numeric is a text type.
                    if let textFieldType = question.textFieldType {
                        switch textFieldType {
                        case .SingleLine:
                            let textFormat = ORKTextAnswerFormat.textAnswerFormat()
                            textFormat.multipleLines = false
                            questionStep.answerFormat = textFormat
                        case .MultiLine:
                            let textFormat = ORKTextAnswerFormat.textAnswerFormat()
                            textFormat.multipleLines = true
                            questionStep.answerFormat = textFormat
                        case .Numeric:
                            questionStep.answerFormat = ORKNumericAnswerFormat(
                                // numeric answers have min and max ranges, "unit" is ua localizeable field for like miles vs kilometers.
                                style: .decimal, unit: nil, minimum: question.minValue as NSNumber?, maximum: question.maxValue as NSNumber?
                            )
                        }
                    }
                    
                case .InformationText:
                    step = ORKInstructionStep(identifier: question.questionId)
                    break // uhhh, this SHOULD break the switch statement, which means it does nothing, but I'm not changeing it or testing this assertion.
                
                case .Slider:
                    if let minValue = question.minValue, let maxValue = question.maxValue {
                        let questionStep = ORKQuestionStep(identifier: question.questionId)
                        step = questionStep
                        questionStep.answerFormat = BWORKScaleAnswerFormat(
                            // setting default value to minValue - 1 should result in a default value that is not visible
                            maximumValue: maxValue, minimumValue: minValue, defaultValue: minValue - 1, step: 1
                        )
                    }
                }
                
                if let step = step {
                    // set to true if this question is the last item, based on numQuestions - which is the number of questions to display.
                    // (which is rarely the last item in the list when randomizing)
                    self.lastQuestion[question.questionId] = (i == numQuestions - 1)
                    step.text = question.prompt
                    steps += [step] // append to steps list
                    self.questionIdToQuestion[question.questionId] = question // update the question lookup dict
                }
            }
        }
        
        // set up the finish-survey step
        let finishStep = ORKInstructionStep(identifier: "finished")
        finishStep.title = NSLocalizedString("survey_completed", comment: "")
        finishStep.text = StudyManager.sharedInstance.currentStudy?.studySettings?.submitSurveySuccessText
        steps += [finishStep]
        
        // Set Up quostion skip logic
        // (only if its not randomized and if there are no optional steps, e.g. you cannot randomize surveys with logic)
        // create a BWNavigatableTask, hand it the steps (ORKSteps), and attach a skip rule if the the question has skip logic.
        if !survey.randomize && hasOptionalSteps {
            let navTask = BWNavigatableTask(identifier: "SurveyTask", steps: steps)
            for step in steps {
                let question = self.questionIdToQuestion[step.identifier]
                if let displayIf = question?.displayIf {
                    let navRule = BWSkipStepNavigationRule(displayIf: displayIf)
                    navTask.setSkip(navRule, forStepIdentifier: step.identifier)
                }
            }
            self.task = navTask
        } else {
            // case: no skip logic setup, just pass it in (can be factored out but whatever)
            self.task = BWOrderedTask(identifier: "SurveyTask", steps: steps)
        }
    }

    /// function is called when the survey card is initially brought up.
    func present(_ parent: UIViewController) {
        // restore data for the active survey or start a new one.
        if let activeSurvey = activeSurvey, let restorationData = activeSurvey.rkAnswers {
            self.surveyViewController = BWORKTaskViewController(
                task: self.task!, restorationData: restorationData, delegate: self, error: nil
            )
        } else {
            self.surveyViewController = BWORKTaskViewController(task: self.task, taskRun: nil)
            self.surveyViewController!.delegate = self
        }
        
        self.parent = parent
                
        self.retainSelf = self
        self.surveyViewController!.displayDiscard = false
        parent.present(self.surveyViewController!, animated: true, completion: nil)
        
        /// It was not clear where the logic to modify interface stuff even is, here's some hopefully-useful-to-future-us info
        // surveyViewController - BWORKTaskViewController
        // surveyViewController?.navigationController? - nil
        // parent.navigationController - exists, UINavigationController
        // parent.navigationController?.toolbar - exists, UIToolbar
        // parent.navigationController?.toolbarItems - nil
        // parent.navigationController?.topViewController - Beiwe2.MainViewController
        // parent.navigationController?.visibleViewController - Beiwe2.MainViewController
        // parent.navigationController?.isNavigationBarHidden - false
        // parent.navigationController?.isToolbarHidden - true
        // parent.navigationController?.topViewController?.popoverPresentationController - nil
        // parent.navigationController?.topViewController?.presentedViewController - nil
        // parent.navigationController?.topViewController?.navigationController - reference to same object as parent.navigationController
        // parent.navigationController?.topViewController?.modalPresentationStyle - UIModalPresentationStyle
        
        /// And then these are changes that didn't do anything even though they look like they might
        // self.surveyViewController?.showsProgressInNavigationBar = false // don't do anything
        // parent.navigationController?.navigationBar.barStyle = UIBarStyle.blackOpaque  // doesn't do anything
        // parent.navigationController?.topViewController?.modalPresentationStyle = UIModalPresentationStyle.pageSheet // doesn't do anything
    }

    func arrayAnswer(_ array: [String]) -> String {
        return "[" + array.joined(separator: ";") + "]"
    }

    func storeAnswer(_ identifier: String, result: ORKTaskResult) {
        guard let question = questionIdToQuestion[identifier], let stepResult = result.stepResult(forStepIdentifier: identifier) else {
            return
        }

        var answersString = ""

        if let questionType = question.questionType {
            switch questionType {
            case .Checkbox, .RadioButton:
                if let results = stepResult.results {
                    if let choiceResults = results as? [ORKChoiceQuestionResult] {
                        if choiceResults.count > 0 {
                            if let choiceAnswers = choiceResults[0].choiceAnswers {
                                var arr: [String] = []
                                for a in choiceAnswers {
                                    if let num: NSNumber = a as? NSNumber {
                                        let numValue: Int = num.intValue
                                        if numValue >= 0 && numValue < question.selectionValues.count {
                                            arr.append(question.selectionValues[numValue].text)
                                        } else {
                                            arr.append("")
                                        }
                                    } else {
                                        arr.append("")
                                    }
                                }
                                if questionType == .Checkbox {
                                    answersString = self.arrayAnswer(arr)
                                } else {
                                    answersString = arr.count > 0 ? arr[0] : ""
                                }
                            }
                        }
                    }
                }
            case .FreeResponse:
                if let results = stepResult.results {
                    if let freeResponses = results as? [ORKQuestionResult] {
                        if freeResponses.count > 0 {
                            if let answer = freeResponses[0].answer {
                                answersString = String(describing: answer)
                            }
                        }
                    }
                }
            case .InformationText:
                break
            case .Slider:
                if let results = stepResult.results {
                    if let sliderResults = results as? [ORKScaleQuestionResult] {
                        if sliderResults.count > 0 {
                            if let answer = sliderResults[0].scaleAnswer {
                                answersString = String(describing: answer)
                            }
                        }
                    }
                }
            }
        }
        if answersString == "" || answersString == "[]" {
            answersString = "NO_ANSWER_SELECTED"
        }
        self.activeSurvey?.bwAnswers[identifier] = answersString
    }

    func questionResponse(_ question: GenericSurveyQuestion) -> (String, String, String) {
        var typeString = ""
        var optionsString = ""
        var answersString = ""

        if let questionType = question.questionType {
            typeString = questionType.rawValue
            if let answer = activeSurvey?.bwAnswers[question.questionId] {
                answersString = answer
            } else {
                answersString = "NOT_PRESENTED"
            }
            switch questionType {
            case .Checkbox, .RadioButton:
                optionsString = self.arrayAnswer(question.selectionValues.map { $0.text })
            case .FreeResponse:
                optionsString = "Text-field input type = " + (question.textFieldType?.rawValue ?? "")
            case .InformationText:
                answersString = ""
                break
            case .Slider:
                if let minValue = question.minValue, let maxValue = question.maxValue {
                    optionsString = "min = " + String(minValue) + "; max = " + String(maxValue)
                }
            }
        }
        return (typeString, optionsString, answersString)
    }

    // stores survey answers on the DataStorage
    func finalizeSurveyAnswers() {
        guard let activeSurvey = activeSurvey, let survey = activeSurvey.survey, let surveyId = surveyId, let patientId = StudyManager.sharedInstance.currentStudy?.patientId, let publicKey = StudyManager.sharedInstance.currentStudy?.studySettings?.clientPublicKey else {
            return
        }
        guard let stepOrder = activeSurvey.stepOrder, survey.questions.count > 0 else {
            return
        }

        guard activeSurvey.bwAnswers.count > 0 else {
            print("No questions answered, not submitting.")
            return
        }

        // set up data file
        let name = TrackingSurveyPresenter.surveyDataType + "_" + surveyId
        let dataFile = DataStorage(type: name, headers: TrackingSurveyPresenter.headers, patientId: patientId, publicKey: publicKey, moveOnClose: true, keyRef: DataStorageManager.sharedInstance.secKeyRef)
        dataFile.sanitize = true
        
        // no questions
        let numQuestions = survey.randomize ? min(survey.questions.count, survey.numberOfRandomQuestions ?? 999) : survey.questions.count
        if numQuestions == 0 {
            return
        }
        
        // store the questions line by line
        for i in 0 ..< numQuestions {
            let question = survey.questions[stepOrder[i]]
            var data = [question.questionId]
            let (questionType, optionsString, answersString) = self.questionResponse(question)
            data.append(questionType)
            data.append(question.prompt ?? "")
            data.append(optionsString)
            data.append(answersString)
            dataFile.store(data)
        }
        dataFile.reset() // clear out the file
    }

    static func addTimingsEvent(_ surveyId: String, event: String) {
        var timingsStore: DataStorage?
        let timingsName: String = TrackingSurveyPresenter.timingDataType + "_" + surveyId

        timingsStore = DataStorageManager.sharedInstance.createStore(timingsName, headers: TrackingSurveyPresenter.timingsHeaders)
        timingsStore!.sanitize = true
        var data: [String] = [String(Int64(Date().timeIntervalSince1970 * 1000))]
        data.append("")
        data.append("")
        data.append("")
        data.append("")
        data.append("")
        data.append(event)
        // print("TimingsEvent: \(data.joined(separator: ","))")  // don't need to know
        timingsStore?.store(data)
    }

    func addTimingsEvent(_ event: String, question: GenericSurveyQuestion?, forcedValue: String? = nil) {
        var data: [String] = [String(Int64(Date().timeIntervalSince1970 * 1000))]
        if let question = question {
            data.append(question.questionId)
            let (questionType, optionsString, answersString) = self.questionResponse(question)
            data.append(questionType)
            data.append(question.prompt ?? "")
            data.append(optionsString)
            data.append(forcedValue != nil ? forcedValue! : answersString)
        } else {
            data.append("")
            data.append("")
            data.append("")
            data.append("")
            data.append(forcedValue != nil ? forcedValue! : "")
        }
        data.append(event)
        // print("TimingsEvent: \(data.joined(separator: ","))")  // we don't need to see every timings event
        self.timingsStore?.store(data)
    }

    func possiblyAddUnpresent() {
        self.valueChangeHandler?.flush()
        self.valueChangeHandler = nil
        if let currentQuestion = currentQuestion {
            self.addTimingsEvent("unpresent", question: currentQuestion)
            self.currentQuestion = nil
        }
    }

    func closeSurvey() {
        self.retainSelf = nil
        StudyManager.sharedInstance.surveysUpdatedEvent.emit(0)
        self.parent?.dismiss(animated: true, completion: nil)
    }

    func displaySurveyQuestion(_ identifier: String) -> Bool {
        guard let question = questionIdToQuestion[identifier], let survey = survey, let displayIf = question.displayIf else {
            return true
        }
        return false
    }

    ////////////////////////////////////////////////////////////////////////// ORK Delegates ////////////////////////////////////////////////////////////////////////////////
    
    // called when the card is dismissed (including cancel button - end task menu item)
    // called when survey done button is pressed
    func taskViewController(_ taskViewController: ORKTaskViewController, didFinishWith reason: ORKTaskViewControllerFinishReason, error: Error?) {
        // print("\ntaskViewController 1 \(taskViewController.currentStepViewController?.step?.identifier)\n")
        self.possiblyAddUnpresent()
        if !self.isComplete {
            self.activeSurvey?.rkAnswers = taskViewController.restorationData
            if let study = StudyManager.sharedInstance.currentStudy {
                Recline.shared.save(study).done { _ in
                    log.info("Tracking survey Saved.")
                }.catch { _ in
                    log.error("Error saving updated answers.")
                }
            }
        }
        self.closeSurvey()
    }

    // called when done button is pressed
    // called when back button is pressed
    // called when next button is pressed
    // called when input occurs
    // NOT called when skip is pressed
    func taskViewController(_ taskViewController: ORKTaskViewController, didChange result: ORKTaskResult) {
        // print("\ntaskViewController 2 \(taskViewController.currentStepViewController?.step?.identifier)\n")
        // update the answer data for this question
        if let identifier = taskViewController.currentStepViewController!.step?.identifier {
            self.storeAnswer(identifier, result: result)
            let currentValue = self.activeSurvey!.bwAnswers[identifier]
            self.valueChangeHandler?.call(currentValue)
        }
    }
    
    // called once when any survey card is displayed - actually I think it is when it is closed/left
    // called when back button is pressed
    func taskViewController(_ taskViewController: ORKTaskViewController, shouldPresent step: ORKStep) -> Bool {
        // print("\ntaskViewController 3 \(taskViewController.currentStepViewController?.step?.identifier)\n")
        self.possiblyAddUnpresent()
        return true
    }
    
    // never called? I guess this is junk. 🙄
    func taskViewController(_ taskViewController: ORKTaskViewController, learnMoreForStep stepViewController: ORKStepViewController) {
        // print("\ntaskViewController 4 \(taskViewController.currentStepViewController?.step?.identifier)\n")
        // Present modal...
        let refreshAlert = UIAlertController(title: "Learning more!", message: "You're smart now", preferredStyle: UIAlertController.Style.alert)
        refreshAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { (_: UIAlertAction!) in }))
        taskViewController.present(refreshAlert, animated: true, completion: nil)
    }
    
    // (called when any survey card is displayed)
    // called when back button is pressed, once with the 'current' question, once with the previous question
    // called when next/skip button is pressed, once with the 'current' question, once with the next question
    // called when survey is initially opened, once with nil and once with a question id (possibly differs if you don't have an informational text box question)
    func taskViewController(_ taskViewController: ORKTaskViewController, hasLearnMoreFor step: ORKStep) -> Bool {
        // print("\ntaskViewController 5 \(taskViewController.currentStepViewController?.step?.identifier)\n")
        switch step.identifier {
        default: return false
        }
    }

    // (called when any survey card is displayed - twice. 🙃)
    // called when back button is pressed, once with the 'current' question, BUT TWICE with the previous question
    // called when next/skip button is pressed, once with the 'current' question, BUT TWICE with the next question
    func taskViewController(_ taskViewController: ORKTaskViewController, viewControllerFor step: ORKStep) -> ORKStepViewController? {
        // print("\ntaskViewController 6 \(taskViewController.currentStepViewController?.step?.identifier)\n")
        return nil
    }
    
    // (called when any survey card is displayed)
    // called when back button is pressed, once with the 'current' question, once with the previous question
    // called when next/skip button is pressed, once with the 'current' question, once with the next question
    // called when you hit the cancel button
    func taskViewControllerSupportsSaveAndRestore(_ taskViewController: ORKTaskViewController) -> Bool {
        // print("\ntaskViewController 7 \(taskViewController.currentStepViewController?.step?.identifier)\n")
        return false
    }

    // (called when any survey card is displayed)
    // called when back button is pressed, once with the 'current' question, once with the previous question
    // called when next/skip button is pressed, once with the 'current' question, once with the next question
    func taskViewController(_ taskViewController: ORKTaskViewController, stepViewControllerWillAppear stepViewController: ORKStepViewController) {
        // print("\ntaskViewController 8 \(taskViewController.currentStepViewController?.step?.identifier)\n")
        
        // stepViewController.navigationController // exists UINavigationController
        // stepViewController.navigationController?.navigationBar // exists, UINavigationBar
        
        // set up the card's UI properties
        // stepViewController.navigationController?.navigationBar.barStyle = UIBarStyle.black  // pretty confident this does nothing
        stepViewController.navigationController?.presentTransparentNavigationBar() // fixes the invisible cancel and back buttons background color
        // stepViewController.navigationController?.hideTransparentNavigationBar()  // makes the buttons actually go away (not desireable)
        // stepViewController.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black] // sets the title text ("1 of 6") color - undesireable, we want the dark-mode-aware version
        // stepViewController.view.backgroundColor = UIColor.clear // makes the entire thing transparent - obviously wrong

        // set up start screen
        self.currentQuestion = nil
        if stepViewController.continueButtonTitle == NSLocalizedString("get_started", comment: "") {
            stepViewController.continueButtonTitle = NSLocalizedString("continue_button_title", comment: "")
        }

        // get the step (the question), get its id
        if let identifier = stepViewController.step?.identifier {
            switch identifier {
            case "finished":
                // executed when the card with the finished survey button is _loaded_ - not when the done button is pressed
                // ... but this code does not actually clear the survey, even though it submits it.
                self.addTimingsEvent("submitted", question: nil)
                StudyManager.sharedInstance.submitSurvey(self.activeSurvey!, surveyPresenter: self)
                self.activeSurvey?.rkAnswers = taskViewController.restorationData
                self.activeSurvey?.isComplete = true
                self.isComplete = true
                _ = StudyManager.sharedInstance.updateActiveSurveys(true)
                stepViewController.cancelButtonItem = nil
                // stepViewController.backButtonItem = nil // this doesn't do anything
            default:
                // load the question
                if let question = questionIdToQuestion[identifier] {
                    self.currentQuestion = question
                    if self.activeSurvey?.bwAnswers[identifier] == nil {
                        self.activeSurvey?.bwAnswers[identifier] = ""
                    }
                    var currentValue = self.activeSurvey!.bwAnswers[identifier]
                    self.addTimingsEvent("present", question: question)
                    var delay = 0.0
                    if question.questionType == SurveyQuestionType.Slider {
                        // for untested reasons we have to provide some delay for slider type questions, probably because
                        // it otherwise causes thousands of sliding style input events
                        delay = 0.25
                    }
                    self.valueChangeHandler = Debouncer<String>(delay: delay) { [weak self] (val: String?) in
                        if let strongSelf = self {
                            if currentValue != val {
                                currentValue = val
                                strongSelf.addTimingsEvent("changed", question: question, forcedValue: val)
                            }
                        }
                    }
                }
                if self.lastQuestion[identifier] ?? false {
                    stepViewController.continueButtonTitle = NSLocalizedString("submit_survey_title", comment: "")
                }
            }
        }
    }

    deinit {
        _ = DataStorageManager.sharedInstance.closeStore(timingsName)
    }
}
