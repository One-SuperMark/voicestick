import CryptoKit
import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let encoded = String(data: input, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
      let seed = Data(base64Encoded: encoded),
      seed.count == 32 else {
    fputs("Invalid Sparkle private key format.\n", stderr)
    exit(1)
}

do {
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    print(key.publicKey.rawRepresentation.base64EncodedString())
} catch {
    fputs("Unable to derive Sparkle public key.\n", stderr)
    exit(1)
}
