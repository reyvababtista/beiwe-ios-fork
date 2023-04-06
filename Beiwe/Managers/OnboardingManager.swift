import Foundation
import ResearchKit

class OnboardingManager: NSObject, ORKTaskViewControllerDelegate {
    var retainSelf: AnyObject?
    var onboardingViewController: ORKTaskViewController!

    var WelcomeStep: ORKStep {
        let instructionStep = ORKInstructionStep(identifier: "WelcomeStep")
        // image is commented out since the new ResearchKit distorts the image dimensions
        // instructionStep.image = UIImage(named: "welcome-image")
        instructionStep.title = NSLocalizedString("welcome_screen_title", comment: "")
        instructionStep.text = NSLocalizedString("welcome_screen_body_text", comment: "")
        return instructionStep
    }

    override init() {
        super.init()
        var steps = [ORKStep]()

        steps += [self.WelcomeStep]
        // steps += [SecondStep];
        // steps += [PreRegisterStep];
        steps += [ORKWaitStep(identifier: "WaitForRegister")]

        let task = ORKOrderedTask(identifier: "OnboardingTask", steps: steps)
        self.onboardingViewController = ORKTaskViewController(task: task, taskRun: nil)
        self.onboardingViewController.showsProgressInNavigationBar = false
        self.onboardingViewController.delegate = self
        self.retainSelf = self
    }

    func closeOnboarding() {
        AppDelegate.sharedInstance().transitionToLoadedAppState()
        self.retainSelf = nil
    }

    /* ORK Delegates */
    func taskViewController(_ taskViewController: ORKTaskViewController, didFinishWith reason: ORKTaskViewControllerFinishReason, error: Error?) {
        // Handle results with taskViewController.result
        // taskViewController.dismissViewControllerAnimated(true, completion: nil)
        self.closeOnboarding()
        log.info("Onboarding closed")
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

        self.onboardingViewController.present(refreshAlert, animated: true, completion: nil)
    }

    func taskViewController(_ taskViewController: ORKTaskViewController, hasLearnMoreFor step: ORKStep) -> Bool {
        switch step.identifier {
        case "SecondStep":
            return true
        default: return false
        }
    }

    func taskViewController(_ taskViewController: ORKTaskViewController, viewControllerFor step: ORKStep) -> ORKStepViewController? {
        return nil
    }

    func taskViewController(_ taskViewController: ORKTaskViewController, stepViewControllerWillAppear stepViewController: ORKStepViewController) {
        if let identifier = stepViewController.step?.identifier {
            switch identifier {
            case "WelcomeStep":
                stepViewController.cancelButtonItem = nil
                stepViewController.continueButtonTitle = NSLocalizedString("welcome_screen_go_to_registration_button_text", comment: "")
            case "WaitForRegister":
                let registerViewController = RegisterViewController()
                registerViewController.dismiss = { [unowned self] didRegister in
                    self.onboardingViewController.dismiss(animated: true, completion: nil)
                    if !didRegister {
                        self.onboardingViewController.goBackward()
                    } else {
                        // They did register, so if we close this onboarding, it should restart up
                        // with the consent form.
                        self.closeOnboarding()
                    }
                }
                self.onboardingViewController.present(registerViewController, animated: true, completion: nil)
            default: break
            }
        }
        /*
         if (stepViewController.step?.identifier == "login") {
             stepViewController.cancelButtonItem = nil;
         }
         */

        // stepViewController.continueButtonTitle = "Go!"
    }
}
