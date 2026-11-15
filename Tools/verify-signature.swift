// Verification uses only the app's public key, never the Keychain/private key.
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4,
      let keyData = Data(base64Encoded: args[1]),
      let signature = Data(base64Encoded: args[3]) else { exit(2) }
do {
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    exit(key.isValidSignature(signature, for: data) ? 0 : 1)
} catch { exit(2) }
