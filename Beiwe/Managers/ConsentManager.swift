import CoreLocation
import Foundation
import ResearchKit

// the (ordered?) steps in the registration process after submitting registration information
enum StepIds: String {
    case Permission = "PermissionsStep"
    case LocationPermission
    case WaitForPermissions
    case WarningStep
    case VisualConsent = "VisualConsentStep"
    case ConsentReview = "ConsentReviewStep"
}


class WaitForPermissionsRule: ORKStepNavigationRule {
    let nextTask: (ORKTaskResult) -> String
    init(nextTask: @escaping ((_ taskResult: ORKTaskResult) -> String)) {
        self.nextTask = nextTask
        super.init(coder: NSCoder())
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func identifierForDestinationStep(with taskResult: ORKTaskResult) -> String {
        return self.nextTask(taskResult)
    }
}


/// the secondary step(s) of registration after the network calls are made. permissions, confirmation etc.
class ConsentManager: NSObject, ORKTaskViewControllerDelegate {
    var retainSelf: AnyObject?
    var consentViewController: ORKTaskViewController!
    var consentDocument: ORKConsentDocument!
    var notificationPermission: Bool = false
    
    
    var PermissionsStep: ORKStep {
        let instructionStep = ORKInstructionStep(identifier: StepIds.Permission.rawValue)
        instructionStep.title = NSLocalizedString("permission_alert_title", comment: "")
        instructionStep.text = NSLocalizedString("permission_location_and_notification_message_long", comment: "")
        return instructionStep
    }

    var LocationPermission: ORKStep {
        let instructionStep = ORKInstructionStep(identifier: StepIds.LocationPermission.rawValue)
        instructionStep.title = NSLocalizedString("location_permission_title", comment: "")
        instructionStep.text = NSLocalizedString("location_permission_text", comment: "")
        return instructionStep
    }

    var WarningStep: ORKStep {
        let instructionStep = ORKInstructionStep(identifier: StepIds.WarningStep.rawValue)
        instructionStep.title = NSLocalizedString("permission_warning_alert_title", comment: "")
        instructionStep.text = NSLocalizedString("permission_warning_alert_text", comment: "")
        return instructionStep
    }

    override init() {
        super.init()

        // Set up permissions

        var steps = [ORKStep]()

        if !self.hasRequiredPermissions() {
            steps += [self.PermissionsStep]
            steps += [self.LocationPermission]
            steps += [ORKWaitStep(identifier: StepIds.WaitForPermissions.rawValue)]
            steps += [self.WarningStep]
        }

        self.consentDocument = ORKConsentDocument()
        self.consentDocument.title = NSLocalizedString("consent_document_title", comment: "")

        let studyConsentSections = StudyManager.sharedInstance.currentStudy?.studySettings?.consentSections ?? [:]

        let overviewSection = ORKConsentSection(type: .overview)
        if let welcomeStudySection = studyConsentSections["welcome"], !welcomeStudySection.text.isEmpty {
            overviewSection.summary = welcomeStudySection.text
            if !welcomeStudySection.more.isEmpty {
                overviewSection.content = welcomeStudySection.more
            }
        } else {
            overviewSection.summary = NSLocalizedString("study_welcome_message", comment: "")
        }

        let consentSectionTypes: [(ORKConsentSectionType, String)] = [
            (.dataGathering, "data_gathering"),
            (.privacy, "privacy"),
            (.dataUse, "data_use"),
            (.timeCommitment, "time_commitment"),
            (.studySurvey, "study_survey"),
            (.studyTasks, "study_tasks"),
            (.withdrawing, "withdrawing"),
        ]
        
        // get the consent sections out of the study information
        var hasAdditionalConsent = false
        var consentSections: [ORKConsentSection] = [overviewSection]
        for (contentSectionType, bwType) in consentSectionTypes {
            if let bwSection = studyConsentSections[bwType], !bwSection.text.isEmpty {
                hasAdditionalConsent = true
                let consentSection = ORKConsentSection(type: contentSectionType)
                consentSection.summary = bwSection.text
                if !bwSection.more.isEmpty {
                    consentSection.content = bwSection.more
                }
                consentSections.append(consentSection)
            }
        }
        
        // looks like someone thought there would be areal signature step?
        self.consentDocument.addSignature(ORKConsentSignature(forPersonWithTitle: nil, dateFormatString: nil, identifier: "ConsentDocumentParticipantSignature"))
        self.consentDocument.sections = consentSections // TODO: signature

        let visualConsentStep = ORKVisualConsentStep(identifier: StepIds.VisualConsent.rawValue, document: self.consentDocument)
        steps += [visualConsentStep]

        // let signature = consentDocument.signatures!.first!
        if hasAdditionalConsent {
            let reviewConsentStep = ORKConsentReviewStep(identifier: StepIds.ConsentReview.rawValue, signature: nil, in: self.consentDocument)
            reviewConsentStep.text = NSLocalizedString("review_consent_text", comment: "")
            reviewConsentStep.reasonForConsent = NSLocalizedString("review_consent_reason", comment: "")
            steps += [reviewConsentStep]
        }

        let task = ORKNavigableOrderedTask(identifier: "ConsentTask", steps: steps)
        // let waitForPermissionRule = WaitForPermissionsRule(coder: NSCoder())
        // task.setNavigationRule(waitForPermissionRule!, forTriggerStepIdentifier: StepIds.WaitForPermissions.rawValue)
        task.setNavigationRule(WaitForPermissionsRule { [weak self] _ -> String in
            if self!.hasRequiredPermissions() {
                return StepIds.VisualConsent.rawValue
            } else {
                return StepIds.WarningStep.rawValue
            }
        }, forTriggerStepIdentifier: StepIds.WaitForPermissions.rawValue)
        self.consentViewController = ORKTaskViewController(task: task, taskRun: nil)
        self.consentViewController.showsProgressInNavigationBar = false
        self.consentViewController.delegate = self
        self.retainSelf = self
    }

    func closeOnboarding() {
        AppDelegate.sharedInstance().transitionToLoadedAppState()
        self.retainSelf = nil
    }

    func hasRequiredPermissions() -> Bool {
        return self.notificationPermission && AppDelegate.sharedInstance().locationPermission
    }

    /* ORK Delegates */

    func taskViewController(_ taskViewController: ORKTaskViewController, didFinishWith reason: ORKTaskViewControllerFinishReason, error: Error?) {
        // Handle results with taskViewController.result
        // taskViewController.dismissViewControllerAnimated(true, completion: nil)
        if reason == ORKTaskViewControllerFinishReason.discarded {
            StudyManager.sharedInstance.leaveStudy().done { _ in
                self.closeOnboarding()
            }
        } else {
            StudyManager.sharedInstance.setConsented().done { _ in
                self.closeOnboarding()
            }
        }
    }

    func taskViewController(_ taskViewController: ORKTaskViewController, didChange result: ORKTaskResult) {
    }

    func taskViewController(_ taskViewController: ORKTaskViewController, shouldPresent step: ORKStep) -> Bool {
        return true
    }

    func taskViewController(_ taskViewController: ORKTaskViewController, learnMoreForStep stepViewController: ORKStepViewController) {
        // Present modal...
        let refreshAlert = UIAlertController(title: "Learning more!", message: "You're smart now", preferredStyle: UIAlertController.Style.alert)

        refreshAlert.addAction(UIAlertAction(title: NSLocalizedString("ok_button_text", comment: ""), style: .default, handler: { (_: UIAlertAction!) in
        }))

        self.consentViewController.present(refreshAlert, animated: true, completion: nil)
    }

    func taskViewController(_ taskViewController: ORKTaskViewController, hasLearnMoreFor step: ORKStep) -> Bool {
        return false
    }

    func taskViewController(_ taskViewController: ORKTaskViewController, viewControllerFor step: ORKStep) -> ORKStepViewController? {
        return nil
    }

    func taskViewController(_ taskViewController: ORKTaskViewController, stepViewControllerWillAppear stepViewController: ORKStepViewController) {
        stepViewController.cancelButtonItem!.title = NSLocalizedString("unregister_alert_title", comment: "")

        if let identifier = StepIds(rawValue: stepViewController.step?.identifier ?? "") {
            switch identifier {
            case .Permission:
                stepViewController.continueButtonTitle = NSLocalizedString("continue_to_permissions_button_title", comment: "")
            case .LocationPermission:
                // setting the location manager delegate to be AppDelegate
                AppDelegate.sharedInstance().locManager.delegate = AppDelegate.sharedInstance()
                // function runs asynchronously
                AppDelegate.sharedInstance().locManager.requestAlwaysAuthorization()
                // since it is asynchronous, need continue button to halt flow until permissions are granted
                stepViewController.continueButtonTitle = NSLocalizedString("continue_button_title", comment: "")
            case .WaitForPermissions:
                let center = UNUserNotificationCenter.current()
                center.requestAuthorization(options: [.sound, .alert, .badge]) { _, error in // TODO: .sound may be unnecessary
                    if error == nil {
                        center.getNotificationSettings { settings in
                            if settings.authorizationStatus == .authorized {
                                self.notificationPermission = true
                            } else {
                                self.notificationPermission = false
                            }
                            // this makes the goForward() call happen on the main thread
                            // app crashes otherwise
                            DispatchQueue.main.async {
                                stepViewController.goForward()
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            stepViewController.goForward()
                        }
                    }
                }
            case .WarningStep:
                stepViewController.continueButtonTitle = NSLocalizedString("continue_button_title", comment: "")
            case .VisualConsent:
                if self.hasRequiredPermissions() {
                    stepViewController.backButtonItem = nil
                }
            default: break
            }
        }
    }
}
