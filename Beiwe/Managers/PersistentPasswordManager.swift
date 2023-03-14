import Foundation
import KeychainSwift

/// standardized name format
fileprivate func keyForStudy(_ study: String, prefix: String) -> String {
    return prefix + study
}

struct PersistentPasswordManager {
    static let sharedInstance = PersistentPasswordManager()  // static singleton reference
    static let bundlePrefix = Bundle.main.bundleIdentifier ?? "com.rocketarmstudios.beiwe"

    // Apple Keychain connection for secure storage
    fileprivate let keychain: KeychainSwift

    // file name prefixes
    fileprivate let passwordKeyPrefix = "password:"
    fileprivate let rsaKeyPrefix = PersistentPasswordManager.bundlePrefix + ".rsapk."

    init() {
        // instantiate the keychain depending on development environment (TODO: why do we do this?)
        #if targetEnvironment(simulator)
            self.keychain = KeychainSwift(keyPrefix: PersistentPasswordManager.bundlePrefix + ".")
        #else
            self.keychain = KeychainSwift()
        #endif
    }

    /// Gets the password for the current study, but is optional
    func passwordForStudy(_ study: String = Constants.defaultStudyId) -> String? {
        // passwords are stored on a per-study basis, so in principle someone could have multiple instances of study information present.
        return self.keychain.get(keyForStudy(study, prefix: self.passwordKeyPrefix))
    }

    /// Sets the password string for the participant on a particular study in the keychain for secure storage, device-only (not icloud shared?)
    /// - study - FIXME: study has a stupid default value, purge.
    func storePassword(_ password: String, study: String = Constants.defaultStudyId) {
        self.keychain.set(
            password, forKey: keyForStudy(study, prefix: self.passwordKeyPrefix), withAccess: .accessibleAlwaysThisDeviceOnly
        )
    }

    /// Gets the SecKey object (RSA encryption operations) for the partcipant
    ///  - study - FIXME: this default value is a hardcoded constant and there is one call to this function
    func storePublicKeyForStudy(_ publicKey: String, patientId: String, study: String = Constants.defaultStudyId) throws -> SecKey {
        let keyref = try SwiftyRSA.storePublicKey(publicKey, keyId: self.publicKeyName(patientId, study: study))
        return keyref
    }

    /// Gets the name of the participant's RSA key
    func publicKeyName(_ patientId: String, study: String = Constants.defaultStudyId) -> String {
        return keyForStudy(study, prefix: self.rsaKeyPrefix) + "." + patientId
    }
}
