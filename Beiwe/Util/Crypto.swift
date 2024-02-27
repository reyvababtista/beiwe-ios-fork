import Foundation
import IDZSwiftCommonCrypto

class Crypto {
    static let sharedInstance = Crypto()
    fileprivate static let defaultRSAPadding: SecPadding = .PKCS1

    // generates a URL-safe-base64 string containing the SHA256 hash of the input string
    // (used on the password parameter sent to the server)
    func sha256Base64URL(_ str: String) -> String {
        let sha256: Digest = Digest(algorithm: .sha256)
        sha256.update(string: str)
        let digest = sha256.final()
        let data = Data(bytes: digest)
        let base64Str = data.base64EncodedString()
        return self.base64ToBase64URL(base64Str)
    }

    // takes a string containing base64 data and returns the string but containing URL-safe base64 data
    func base64ToBase64URL(_ base64str: String) -> String {
        // replaceAll('/', '_').replaceAll('+', '-');
        return base64str.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }

    // generates random data for whatever purpose we desire (e.g. generating the aes encryption key).
    func randomBytes(_ length: Int) -> Data {
        var data = Data(count: length)
        let result = data.withUnsafeMutableBytes { [count = data.count]
            (mutableBytes: UnsafeMutablePointer<UInt8>) -> Int32 in
                SecRandomCopyBytes(kSecRandomDefault, count, mutableBytes)
        }
        
        if result == errSecSuccess {
            return data
        } else {
            // if this process faily we crash because that's insane
            // (February 2024 - literally never seen after 8+ years)
            fatalError("random data generation failed")
        }
    }
    
    // generates a new 128-bit AES key - should only ever be called with 128, for now.
    func newAesKey(_ keyLength: Int = 128) -> Data {
        // this is an integer divide, it rounds any value of bits that is not divisible by 8 up to
        // the nearest multiple of 8. (e.g. it normalizes bits to bytes)
        let length = (keyLength + 7) / 8
        return self.randomBytes(length)
    }

    // using the RSA key (provided by the beiwe server for this participant) to encrypt a string,
    // output is a base64 encoded string containing raw bytes.
    func rsaEncryptString(_ str: String, publicKey: SecKey, padding: SecPadding = defaultRSAPadding) throws -> String {
        // setup
        let blockSize = SecKeyGetBlockSize(publicKey)
        let plainTextData = [UInt8](str.utf8) // get string as byte array
        let plainTextDataLength = Int(str.count)
        var encryptedData = [UInt8](repeating: 0, count: Int(blockSize)) // allocate 0s
        var encryptedDataLength = blockSize
        
        // Do the encrypt, throw on any errors
        let status = SecKeyEncrypt(
            publicKey, padding, plainTextData, plainTextDataLength, &encryptedData, &encryptedDataLength
        )
        if status != noErr {
            // (February 2024 - literally never seen after 8+ years) - what are we doing when we catch this tho
            throw NSError(domain: "beiwe.crypto", code: 1, userInfo: [:])
        }
        
        // get encrypted blob as bytes, convert to url-safe-base64
        let data = Data(bytes: UnsafePointer<UInt8>(encryptedData), count: encryptedDataLength)
        return self.base64ToBase64URL(data.base64EncodedString(options: []))
    }

    // encrypts a string using AES 128 - I think it is CBC mode? - using the provided key and iv.
    func aesEncrypt(_ iv: Data, key: Data, plainText: String) -> Data {
        // TODO: MAKE THIS DATA RETURN NON OPTIONA!
        let arrayKey = Array(
            UnsafeBufferPointer(start: (key as NSData)
                .bytes.bindMemory(to: UInt8.self, capacity: key.count), count: key.count)
        )
        let arrayIv = Array(
            UnsafeBufferPointer(start: (iv as NSData)
                .bytes.bindMemory(to: UInt8.self, capacity: iv.count), count: iv.count)
        )

        let cryptor = Cryptor(
            operation: .encrypt, algorithm: .aes, options: .PKCS7Padding, key: arrayKey, iv: arrayIv
        )
        let cipherText = cryptor.update(string: plainText)?.final()
        if let cipherText = cipherText {
            return Data(cipherText)
        }
        // (February 2024 - literally never seen after 8+ years) - we crashed elsewhere tho
        fatalError("could not encrypt string with AES")
    }
}
