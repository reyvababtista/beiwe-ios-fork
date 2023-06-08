import UIKit

class ForgotPasswordHeaderView: UIView {
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var patientId: UILabel! // this is the blank ui label element, it is... unalterably shifted 2/3rds of its height down.
    @IBOutlet weak var patientId2: UILabel! // this is the "Patient ID" label, we overwrite the text entirely in ChangePasswordController
    @IBOutlet weak var callButton: UIButton!
    /*
     // Only override drawRect: if you perform custom drawing.
     // An empty implementation adversely affects performance during animation.
     override func drawRect(rect: CGRect) {
         // Drawing code
     }
     */
}
