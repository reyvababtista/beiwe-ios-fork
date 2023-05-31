//
//  BWORKTaskViewController.swift
//  Beiwe
//
//  Created by Keary Griffin on 4/15/16.
//  Copyright © 2016 Rocketfarm Studios. All rights reserved.
//

import Foundation
import ResearchKit

class BWORKTaskViewController: ORKTaskViewController {
    var displayDiscard = true

    /*
     @objc override func preferredStatusBarStyle() -> UIStatusBarStyle {
         return UIStatusBarStyle.LightContent
     }
     */

    @objc override func presentCancelOptions(_ saveable: Bool, sender: UIBarButtonItem?) {
        super.presentCancelOptions(self.displayDiscard ? saveable : false, sender: sender)
    }
}
