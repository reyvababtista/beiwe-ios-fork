import Eureka
import PKHUD
import PromiseKit
import SwiftValidator
import UIKit

/// This class is used in two places, the forgot password menu (on the login page), and the logged in change password (user menu option)
class ChangePasswordViewController: FormViewController {
    let autoValidation = false
    var isForgotPassword = false // flag determines whether this is the forgot password or change password use-case
    let db = Recline.shared // this is not used
    var finished: ((_ changed: Bool) -> Void)? // dunnoo
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // self.view = GradientView() // This doesn't work at all
        tableView?.backgroundColor = AppColors.Beiwe1
        
        // create the "form" (menu option) elements
        form +++ Section { section in
            if self.isForgotPassword {
                // populate
                var header = HeaderFooterView<ForgotPasswordHeaderView>(.nibFile(name: "ForgotPasswordHeaderView", bundle: nil))
                header.onSetupView = { (headerView: ForgotPasswordHeaderView, _: Section) in
                    // headerView.patientId - is offset vertically (down) by about 2/3rds of a line height and and I can't work out how to fix it
                    // headerView.patientId.text = StudyManager.sharedInstance.currentStudy?.patientId ?? ""
                    // so instead we bind to the other element if we delete headerView.patientId from the .nib file it breaks text flow differently
                    headerView.patientId2.text = "Patient ID: " + (StudyManager.sharedInstance.currentStudy?.patientId ?? "")!
                    
                    // add the call button, but hide it if it's disabled in the study settings
                    headerView.callButton.addTarget(self, action: #selector(ChangePasswordViewController.callAssistant(_:)), for: UIControl.Event.touchUpInside)
                    if !(StudyManager.sharedInstance.currentStudy?.studySettings?.callResearchAssistantButtonEnabled)! {
                        headerView.descriptionLabel.text = NSLocalizedString("forgot_password_title", comment: "")
                        headerView.callButton.isHidden = true
                    }
                }
                section.header = header
            } else {
                // sets the ~title to "CHANGE PASSWOORD" for the logged-in change password, but its like gray
                section.header = HeaderFooterView(stringLiteral: NSLocalizedString("title_activity_reset_password", comment: ""))
            }
        }
        
            // these are the cells (items) in the menu
            // tewporary / current password field
            <<< SVPasswordRow("currentPassword") { // button setup
                $0.title = isForgotPassword ? NSLocalizedString("forgot_password_temporary_password_caption", comment: "") : NSLocalizedString("reset_password_current_password_caption", comment: "")
                let placeholder: String = String($0.title!.lowercased().dropLast())
                $0.placeholder = placeholder
                $0.customRules = [RequiredRule()]
                $0.autoValidation = autoValidation
                $0.cell.backgroundColor = AppColors.Beiwe1
                $0.cell.tintColor = UIColor.white // sets the text color
            }
            // new password field
            <<< SVPasswordRow("password") { // button setup
                $0.title = NSLocalizedString("reset_password_new_password_caption", comment: "")
                $0.placeholder = NSLocalizedString("reset_password_new_password_hint", comment: "")
                $0.customRules = [RequiredRule(), RegexRule(regex: Constants.passwordRequirementRegex, message: Constants.passwordRequirementDescription)]
                $0.autoValidation = autoValidation
                $0.cell.backgroundColor = AppColors.Beiwe1
                $0.cell.tintColor = UIColor.white
            }
            // new password again field
            <<< SVPasswordRow("confirmPassword") { // button setup
                $0.title = NSLocalizedString("reset_password_confirm_new_password_caption", comment: "")
                $0.placeholder = NSLocalizedString("reset_password_confirm_new_password_hint", comment: "")
                $0.customRules = [RequiredRule(), MinLengthRule(length: 1)]
                $0.autoValidation = autoValidation
                $0.cell.backgroundColor = AppColors.Beiwe1
                $0.cell.tintColor = UIColor.white
            }
            // submit button
            <<< ButtonRow { // button setup
                $0.title = NSLocalizedString("reset_password_submit", comment: "")
                $0.cell.backgroundColor = AppColors.Beiwe2 // set a darker color on the submit and cancel buttons
                $0.cell.tintColor = UIColor.cyan // and a different text color for distinction
            }
            // the code for doing a password reset, contacting the server etc. (TERRIBLE FACTORING WHY WOULD ANYONE WITH A BRAIN IN THEIR HEAD THINK THIS WAS TOLERABLE)
            .onCellSelection { [unowned self] (cell: ButtonCellOf<String>, row: ButtonRow) in
                if self.form.validateAll() {
                    // ui lock etc
                    PKHUD.sharedHUD.dimsBackground = true
                    PKHUD.sharedHUD.userInteractionOnUnderlyingViewsEnabled = false
                    HUD.show(.progress)
                    
                    // get the values
                    let formValues = self.form.values()
                    let newPassword: String? = formValues["password"] as! String?
                    let currentPassword: String? = formValues["currentPassword"] as! String?
                    
                    // do the request
                    if let newPassword = newPassword, let currentPassword = currentPassword {
                        let changePasswordRequest = ChangePasswordRequest(newPassword: newPassword)
                        ApiManager.sharedInstance.makePostRequest(changePasswordRequest, password: currentPassword).done { (arg: (ChangePasswordRequest.ApiReturnType, Int)) in
                            // success case
                            let (body, code) = arg
                            log.info("Password changed")
                            PersistentPasswordManager.sharedInstance.storePassword(newPassword)
                            HUD.flash(.success, delay: 1)
                            if let finished = self.finished {
                                finished(true)
                            } else {
                                self.presentingViewController?.dismiss(animated: true, completion: nil)
                            }
                        }.catch { (error: Error) in
                            // error case
                            log.info("error received from change password: \(error)")
                            var err: HUDContentType
                            switch error {
                            case let ApiErrors.failedStatus(code):
                                switch code {
                                case 403, 401:
                                    err = .labeledError(title: NSLocalizedString("reset_password_error_alert_title", comment: ""), subtitle: NSLocalizedString("invalid_old_password", comment: ""))
                                default:
                                    err = .labeledError(title: NSLocalizedString("reset_password_error_alert_title", comment: ""), subtitle: NSLocalizedString("reset_password_communication_error", comment: ""))
                                }
                            default:
                                err = .labeledError(title: NSLocalizedString("reset_password_error_alert_title", comment: ""), subtitle: NSLocalizedString("reset_password_communication_error", comment: ""))
                            }
                            HUD.flash(err, delay: 2.0)
                        } // end catch
                    } // end request clause
                } // end self.form.validateAll()
                else {
                    // print("Bad validation.")
                }
            } // end submit button (have I mentioned this is terrible factoring?)
            
            // The Cancel button
            <<< ButtonRow { // button setup
                $0.title = NSLocalizedString("cancel_button_text", comment: "")
                $0.cell.backgroundColor = AppColors.Beiwe2
                $0.cell.tintColor = UIColor.cyan
            }.onCellSelection { [unowned self] (cell: ButtonCellOf<String>, row: ButtonRow) in
                if let finished = self.finished {
                    finished(false) // ... call itself? what is this?
                } else {
                    self.presentingViewController?.dismiss(animated: true, completion: nil)
                }
            }
        
        // I guess this is some kind of configuration of the confirmation field that has to be assigned/set up outside the active code.
        let passwordRow: SVPasswordRow? = form.rowBy(tag: "password")
        let confirmRow: SVPasswordRow? = form.rowBy(tag: "confirmPassword")
        confirmRow!.customRules = [ConfirmationRule(confirmField: passwordRow!.cell.textField)]
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @objc func callAssistant(_ sender: UIButton!) {
        confirmAndCallClinician(self, callAssistant: true)
    }
    
    /* MARK: - Navigation
     In a storyboard-based application, you will often want to do a little preparation before navigation
     override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
         Get the new view controller using segue.destinationViewController.
         Pass the selected object to the new view controller.
     }*/
}
