import Eureka
import Firebase
import PKHUD
import PromiseKit
import Sentry
import SwiftValidator
import UIKit

enum RegistrationError: Error {
    case incorrectServer
}

class RegisterViewController: FormViewController {
    // static assets
    static let commErrDelay = 7.0
    static let commErr = NSLocalizedString("http_message_server_not_found", comment: "")
    
    // validation behavior? always false?
    let autoValidation = false
    // I guess this property is assigned somewhere, but its not assigned in this file...
    var dismiss: ((_ didRegister: Bool) -> Void)?
    
    // various text colors
    let font = UIFont.systemFont(ofSize: 16.0)
    let small_font = UIFont.systemFont(ofSize: 13.0, weight: UIFont.Weight.bold)
    let less_dark_gray = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1) // darkGray is 0.333, this is much more legible
    let legible_red = UIColor(red: 0.8, green: 0, blue: 0, alpha: 1)
    
    // set the font sizes, colors. Note that the label text is black in light mode and white in dark mode and it seems stuck that way.
    func apply_cell_defaults(_ cell: SVTextCell) {
        cell.backgroundColor = AppColors.Beiwe1 // the lightes "beiwe color'
        cell.textLabel?.font = self.font // the normal label
        cell.detailTextLabel?.font = self.font // text when there is nothing present in the form
        cell.validationLabel.font = self.small_font // the red validation text one
        cell.errorColor = self.legible_red // (also works with row.errorColor)
        
        // these don't work. It appears to be impossible to set this element's color.
        // cell.titleLabel?.textColor = UIColor.white
        // cell.accessibilityIgnoresInvertColors = true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.tableView.backgroundColor = AppColors.Beiwe2 // one step darker than the light coloring
        
        // set the font sizes, colors.  Note that the label text is black in light mode and white in dark mode and it seems stuck that way.
        // (can't work out how to make a generic type function  to handle different rows)
        SVURLRow.defaultCellSetup = { (cell: SVURLCell, row: SVURLRow) in
            self.apply_cell_defaults(cell)
            row.placeholderColor = self.less_dark_gray
            row.onCellHighlightChanged { cell, row in
                cell.titleLabel?.textColor = UIColor.white
            }
        }
        SVTextRow.defaultCellSetup = { (cell: SVTextCell, row: SVTextRow) in
            self.apply_cell_defaults(cell)
            row.placeholderColor = self.less_dark_gray
            row.onCellHighlightChanged { cell, row in
                cell.titleLabel?.textColor = UIColor.white
            }
        }
        SVPasswordRow.defaultCellSetup = { (cell: SVPasswordCell, row: SVPasswordRow) in
            self.apply_cell_defaults(cell)
            row.placeholderColor = self.less_dark_gray
            row.onCellHighlightChanged { cell, row in
                cell.titleLabel?.textColor = UIColor.white
            }
        }
        SVSimplePhoneRow.defaultCellSetup = { (cell: SVSimplePhoneCell, row: SVSimplePhoneRow) in
            self.apply_cell_defaults(cell)
            row.placeholderColor = self.less_dark_gray
            row.onCellHighlightChanged { cell, row in
                cell.titleLabel?.textColor = UIColor.white
            }
        }
        SVAccountRow.defaultCellSetup = { (cell: SVAccountCell, row: SVAccountRow) in
            self.apply_cell_defaults(cell)
            row.placeholderColor = self.less_dark_gray
            row.onCellHighlightChanged { cell, row in
                cell.titleLabel?.textColor = UIColor.white
            }
        }
        
        var section = Section(NSLocalizedString("registration_screen_title", comment: ""))
        section = section
            // server url field (shows the url field, no validation)
            <<< SVURLRow("server") {
                // $0 is the ro object
                // $0.value = "staging.beiwe.org" // speed up your life in debugging by setting a default value
                $0.title = NSLocalizedString("registration_server_url_label", comment: "")
                $0.placeholder = NSLocalizedString("registration_server_url_hint", comment: "")
                $0.customRules = [RequiredRule()] // indicates required field
                $0.autoValidation = autoValidation
                $0.cell.tintColor = UIColor.white
                
                // $0.baseCell.titleLabel?.textColor = UIColor.white
                // the default highlightcolor is blue, we want it to stay white in dark mode, and in light mode it highlights the selected cell...
            }
            // participant id (aka patient id for... no reason)
            <<< SVTextRow("patientId") {
                // $0.value = "susix3kt"
                $0.title = NSLocalizedString("registration_user_id_label", comment: "")
                $0.placeholder = NSLocalizedString("registration_user_id_hint", comment: "")
                $0.customRules = [RequiredRule()]
                $0.autoValidation = autoValidation
            }
            // temporary password - has reduced validation
            <<< SVPasswordRow("tempPassword") {
                // $0.value = "a"
                $0.title = NSLocalizedString("registration_temp_password_label", comment: "")
                $0.placeholder = NSLocalizedString("registration_temp_password_hint", comment: "")
                $0.customRules = [RequiredRule()]
                $0.autoValidation = autoValidation
            }
            // password - has full validation
            <<< SVPasswordRow("password") {
                // $0.value = "      "
                $0.title = NSLocalizedString("registration_new_password_label", comment: "")
                $0.placeholder = NSLocalizedString("registration_new_password_hint", comment: "")
                $0.customRules = [RequiredRule(), RegexRule(regex: Constants.passwordRequirementRegex, message: Constants.passwordRequirementDescription)]
                $0.autoValidation = autoValidation
            }
            // confirm the password
            <<< SVPasswordRow("confirmPassword") {
                // $0.value = "      "
                $0.title = NSLocalizedString("registration_confirm_new_password_label", comment: "")
                $0.placeholder = NSLocalizedString("registration_confirm_new_password_hint", comment: "")
                $0.customRules = [RequiredRule(), MinLengthRule(length: 1)]
                $0.autoValidation = true // will show up as red until in matches, dope
            }
            // clinic phone number for general help
            <<< SVSimplePhoneRow("clinicianPhone") {
                // $0.value = "5555555555"
                $0.title = NSLocalizedString("phone_number_entry_your_clinician_label", comment: "")
                $0.placeholder = NSLocalizedString("phone_number_entry_your_clinician_hint", comment: "")
                $0.customRules = [RequiredRule(), MinLengthRule(length: 8), MaxLengthRule(length: 15), FloatRule()]
                $0.autoValidation = autoValidation
            }
            // research assistant phone numeber (more specific help)
            <<< SVSimplePhoneRow("raPhone") {
                // $0.value = "5555555555"
                $0.title = NSLocalizedString("phone_number_entry_research_assistant_label", comment: "")
                $0.placeholder = NSLocalizedString("phone_number_entry_research_assistant_hint", comment: "")
                $0.customRules = [RequiredRule(), MinLengthRule(length: 8), MaxLengthRule(length: 15), FloatRule()]
                $0.autoValidation = autoValidation
            }
            // the submit button
            <<< ButtonRow {
                $0.title = NSLocalizedString("registration_submit", comment: "")
                $0.baseCell.backgroundColor = AppColors.Beiwe2point5
                $0.cell.tintColor = UIColor.white // button text is ~blue, set it to white, looks nice....
            }
            // this is the validation code when you tap the register button
            .onCellSelection { [unowned self] (cell: ButtonCellOf<String>, row: ButtonRow) in
                runValidationAndRegister()
            }
            
        // the cancel button - why was there a cancel button.  Dismissing this view Never Worked and still doesn't work.
        // <<< ButtonRow {
        //     $0.title = NSLocalizedString("cancel_button_text", comment: "")
        // }.onCellSelection { [unowned self] (cell: ButtonCellOf<String>, row: ButtonRow) in
        //     if let dismiss = self.dismiss {
        //         dismiss(false)
        //     } else {
        //         self.presentingViewController?.dismiss(animated: true, completion: nil)
        //     }
        // }

        form +++ section // stick the sections in the form to allow form validation - I think
        
        // set up the matching values rule, I think?
        let passwordRow: SVPasswordRow? = form.rowBy(tag: "password")
        let confirmRow: SVPasswordRow? = form.rowBy(tag: "confirmPassword")
        confirmRow!.customRules = [ConfirmationRule(confirmField: passwordRow!.cell.textField)]
    }

    /// runs all validation code and the registration request.
    // This used to be an inline function stuck directly in the .onCellSelection code inside the viewDidLoad function above. No. Not okay.
    // Consequently this could and probably should be refactored further ("detangled" may be more accurate), but ... time.
    func runValidationAndRegister() {
        PKHUD.sharedHUD.dimsBackground = true // make it look nice while doing its thing
        
        if self.form.validateAll() {
            PKHUD.sharedHUD.userInteractionOnUnderlyingViewsEnabled = false // probably disables ui taps etc
            HUD.show(.progress) // pop up spinner
            
            // extract form values
            let formValues = self.form.values()
            let patientId: String? = formValues["patientId"] as! String?
            let phoneNumber: String? = "NOT_SUPPLIED"
            let newPassword: String? = formValues["password"] as! String?
            let tempPassword: String? = formValues["tempPassword"] as! String?
            let clinicianPhone: String? = formValues["clinicianPhone"] as! String?
            let raPhone: String? = formValues["raPhone"] as! String?
            
            // url fix
            var server = formValues["server"] as! String // this force conversion is safe even when value is empty
            if !server.starts(with: "https://") { // might as well _safely_ prepend https://
                server = "https://" + server
            }
            
            if let patientId = patientId, let phoneNumber = phoneNumber, let newPassword = newPassword, let clinicianPhone = clinicianPhone, let raPhone = raPhone {
                let registerStudyRequest = RegisterStudyRequest(patientId: patientId, phoneNumber: phoneNumber, newPassword: newPassword)
                    
                // sets tags for Sentry
                Client.shared?.tags = ["user_id": patientId, "server_url": server]
                ApiManager.sharedInstance.password = tempPassword ?? ""
                ApiManager.sharedInstance.patientId = patientId
                ApiManager.sharedInstance.customApiUrl = server
                
                // make the post request - this studysettings object is instantiated inside the RegisterStudyRequest.makePostRequest
                ApiManager.sharedInstance.makePostRequest(registerStudyRequest).then { (studySettings: StudySettings, _: Int) -> Promise<Study> in
                    // we cannot just rely on the request succeeding (200 code), we need to test the data in the response...
                    // ... but StudySettings only has one optional value without a default.
                    guard studySettings.clientPublicKey != nil else {
                          // studySettings.wifiLogFrequencySeconds != nil // old checks?
                          // studySettings.callClinicianButtonEnabled != nil
                        throw RegistrationError.incorrectServer
                    }
                        
                    // configure firebase first
                    if FirebaseApp.app() == nil && studySettings.googleAppID != "" {
                        AppDelegate.sharedInstance().configureFirebase(studySettings: studySettings)
                    }
                        
                    // set password
                    PersistentPasswordManager.sharedInstance.storePassword(newPassword)
                    ApiManager.sharedInstance.password = newPassword
                        
                    // instantiate study, set phone numbers (not part of request return, it was entered locally)
                    let study = Study(patientPhone: phoneNumber, patientId: patientId, studySettings: studySettings, apiUrl: server)
                    study.clinicianPhoneNumber = clinicianPhone
                    study.raPhoneNumber = raPhone
                    
                    // fuzzgps
                    if studySettings.fuzzGps {
                        study.fuzzGpsLatitudeOffset = self.generateLatitudeOffset()
                        study.fuzzGpsLongitudeOffset = self.generateLongitudeOffset()
                    }
                    // Call purge studies to ensure there is no weird data present from possible partial study registrations.
                    StudyManager.sharedInstance.purgeStudies()
                    return Recline.shared.save(study)
                        
                }.then { (_: Study) -> Promise<Bool> in
                    // set study fcm token, load the study
                    let token = Messaging.messaging().fcmToken
                    AppDelegate.sharedInstance().sendFCMToken(fcmToken: token ?? "")
                    HUD.flash(.success, delay: 1)
                    return StudyManager.sharedInstance.loadDefaultStudy()
                    
                }.done { (_: Bool) in
                    // set logged in to True, dismiss login view?
                    AppDelegate.sharedInstance().isLoggedIn = true
                    if let dismiss = self.dismiss {
                        dismiss(true) // no clue...
                    } else {
                        self.presentingViewController?.dismiss(animated: true, completion: nil) // dismisses the view?
                    }
                    
                }.catch { (error: Error) in
                    // Show error message logic
                    print("error received during registration:\n\(error)")
                    var delay = 1.5
                    var err: HUDContentType
                    switch error {
                    case let ApiErrors.failedStatus(code):
                        switch code {
                        case 403, 401:
                            err = .labeledError(title: NSLocalizedString("couldnt_register", comment: ""), subtitle: NSLocalizedString("http_message_403_during_registration", comment: ""))
                        case 405:
                            err = .label(NSLocalizedString("http_message_405", comment: ""))
                            delay = 10.0 // long message, long delay (ui is still locked)
                        case 400:
                            err = .label(NSLocalizedString("http_message_400", comment: ""))
                            delay = 10.0 // long message, long delay (ui is still locked)
                        default:
                            err = .label(RegisterViewController.commErr)
                            delay = RegisterViewController.commErrDelay
                        }
                    default:
                        err = .label(RegisterViewController.commErr)
                        delay = RegisterViewController.commErrDelay
                    }
                    HUD.flash(err, delay: delay) // delay
                }
            }
        } else {
            print("validation failed.")
        }
    }
    
    /// this doesn't do anything....
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning() // Dispose of any resources that can be recreated.
    }
    
    /// Generates a random offset between -1 and 1 (thats not between -0.2 and 0.2)
    func generateLatitudeOffset() -> Double {
        var ran = Double.random(in: -1 ... 1)
        while ran <= 0.2 && ran >= -0.2 {
            ran = Double.random(in: -1 ... 1)
        }
        return ran
    }
    
    /// Generates a random offset between -180 and 180 (thats not between -10 and 10)
    func generateLongitudeOffset() -> Double {
        var ran = Double.random(in: -180 ... 180)
        while ran <= 10 && ran >= -10 {
            ran = Double.random(in: -180 ... 180)
        }
        return ran
    }
}
