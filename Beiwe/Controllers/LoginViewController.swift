//
//  LoginViewController.swift
//  Beiwe
//
//  Created by Keary Griffin on 4/4/16.
//  Copyright © 2016 Rocketfarm Studios. All rights reserved.
//

import UIKit
import PKHUD
import ResearchKit
import Firebase

class LoginViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var callClinicianButton: UIButton!
    @IBOutlet weak var loginButton: BWBorderedButton!
    @IBOutlet weak var password: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController?.presentTransparentNavigationBar()

        var clinicianText: String
        clinicianText = StudyManager.sharedInstance.currentStudy?.studySettings?.callClinicianText ?? NSLocalizedString("default_call_clinician_text", comment: "")
        callClinicianButton.setTitle(clinicianText, for: UIControl.State())
        callClinicianButton.setTitle(clinicianText, for: UIControl.State.highlighted)
        if #available(iOS 9.0, *) {
            callClinicianButton.setTitle(clinicianText, for: UIControl.State.focused)
        }
        // Hide call button if it's disabled in the study settings
        if !(StudyManager.sharedInstance.currentStudy?.studySettings?.callClinicianButtonEnabled)! {
            callClinicianButton.isHidden = true
        }

        password.delegate = self
        loginButton.isEnabled = false
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tap))
        view.addGestureRecognizer(tapGesture)

        // Do any additional setup after loading the view.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func loginPressed(_ sender: AnyObject) {
        password.resignFirstResponder()
        PKHUD.sharedHUD.dimsBackground = true
        PKHUD.sharedHUD.userInteractionOnUnderlyingViewsEnabled = false

        if let password = password.text, password.count > 0 {
            if (AppDelegate.sharedInstance().checkPasswordAndLogin(password)) {
                // register for notifications and log in?
                HUD.flash(.success, delay: 0.5)
                AppDelegate.sharedInstance().checkFirebaseCredentials()
                if let token: String = Messaging.messaging().fcmToken {
                    AppDelegate.sharedInstance().sendFCMToken(fcmToken: token)
                }
                AppDelegate.sharedInstance().transitionToLoadedAppState()
            } else {
                HUD.flash(.error, delay: 1)
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        loginPressed(self)
        textField.resignFirstResponder()
        return true
    }

    @objc func tap(_ gesture: UITapGestureRecognizer) {
        password.resignFirstResponder()
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {

        // Find out what the text field will be after adding the current edit
        if let text = (password.text as NSString?)?.replacingCharacters(in: range, with: string) {
            if !text.isEmpty{//Checking if the input field is not empty
                loginButton.isEnabled = true //Enabling the button
            } else {
                loginButton.isEnabled = false //Disabling the button
            }
        }

        // Return true so the text field will be changed
        return true
    }

    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        return true
    }

    @IBAction func forgotPassword(_ sender: AnyObject) {
        let vc = ChangePasswordViewController()
        vc.isForgotPassword = true
        vc.finished = { _ in
            self.dismiss(animated: true, completion: nil)
        }
        present(vc, animated: true, completion: nil)

    }

    @IBAction func callClinician(_ sender: AnyObject) {
        confirmAndCallClinician(self)
    }

}
