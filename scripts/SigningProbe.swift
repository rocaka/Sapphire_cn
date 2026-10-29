import Foundation

@main
struct SigningProbe {
    static func main() throws {
        precondition(AppSecurityValidator.isSafeIdentifier("com.example.Useful-App"))
        for invalid in ["../Library/Caches", "/Applications/Test.app", "com.example..app", "com.example:app"] {
            precondition(!AppSecurityValidator.isSafeIdentifier(invalid))
        }
        let app = URL(fileURLWithPath: CommandLine.arguments[1])
        let identity = try AppSecurityValidator.identity(at: app)
        precondition(identity.bundleIdentifier == "com.rocaka.sapphirecn.tests.signing-fixture")
        precondition(identity.signingIdentifier == identity.bundleIdentifier)
        precondition(identity.teamIdentifier == nil)
        do {
            try AppSecurityValidator.validateReplacement(candidate: app, replacing: app)
            preconditionFailure("Ad-hoc apps must require manual updates")
        } catch AppSecurityValidationError.publisherMismatch {}
        let tampered = app.deletingLastPathComponent().appendingPathComponent("TamperedSigningFixture.app")
        try FileManager.default.copyItem(at: app, to: tampered)
        let executable = tampered.appendingPathComponent("Contents/MacOS/SapphireSigningFixture")
        let handle = try FileHandle(forWritingTo: executable)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("tampered".utf8))
        try handle.close()
        do {
            _ = try AppSecurityValidator.identity(at: tampered)
            preconditionFailure("Tampered executable was accepted")
        } catch AppSecurityValidationError.invalidSignature {}
        print("Nested ad-hoc signature, publisher checks and tamper rejection passed")
    }
}
