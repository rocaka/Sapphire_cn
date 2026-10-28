//
//  AppSecurity.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

#if !SAPPHIRE_FULL_BUILD
import Foundation
import Security

struct AppCodeSignatureIdentity: Equatable {
    let signingIdentifier: String
    let teamIdentifier: String?
    let bundleIdentifier: String
}

enum AppSecurityValidationError: LocalizedError {
    case invalidSignature(OSStatus)
    case publisherMismatch
    case notAnApplication
    case bundleIdentifierMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .invalidSignature(let status):
            "签名验证失败（\(status)）。请重新下载应用。"
        case .publisherMismatch:
            "更新必须由相同的 Apple 开发者团队签名。临时签名版本请手动安装。"
        case .notAnApplication:
            "The downloaded item is not a valid application bundle."
        case .bundleIdentifierMismatch(let expected, let actual):
            "The update is for \(actual), not \(expected)."
        }
    }
}

enum AppSecurityValidator {
    static func identity(at bundleURL: URL, requireValidSignature: Bool = true) throws -> AppCodeSignatureIdentity {
        guard bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
              let bundleIdentifier = Bundle(url: bundleURL)?.bundleIdentifier else {
            throw AppSecurityValidationError.notAnApplication
        }
        var code: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code)
        guard createStatus == errSecSuccess, let code else {
            throw AppSecurityValidationError.invalidSignature(createStatus)
        }
        if requireValidSignature {
            let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
            let status = SecStaticCodeCheckValidity(code, flags, nil)
            guard status == errSecSuccess else { throw AppSecurityValidationError.invalidSignature(status) }
        }
        var info: CFDictionary?
        let status = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard status == errSecSuccess, let info = info as? [String: Any],
              let identifier = info[kSecCodeInfoIdentifier as String] as? String else {
            throw AppSecurityValidationError.invalidSignature(status)
        }
        return AppCodeSignatureIdentity(
            signingIdentifier: identifier,
            teamIdentifier: info[kSecCodeInfoTeamIdentifier as String] as? String,
            bundleIdentifier: bundleIdentifier
        )
    }

    static func validateReplacement(candidate: URL, replacing installed: URL) throws {
        let candidateIdentity = try identity(at: candidate)
        let installedIdentity = try identity(at: installed)
        let candidateID = candidateIdentity.bundleIdentifier
        let installedID = installedIdentity.bundleIdentifier
        guard candidateID == installedID else {
            throw AppSecurityValidationError.bundleIdentifierMismatch(expected: installedID, actual: candidateID)
        }
        guard let installedTeam = installedIdentity.teamIdentifier, !installedTeam.isEmpty,
              candidateIdentity.teamIdentifier == installedTeam,
              candidateIdentity.signingIdentifier == installedIdentity.signingIdentifier else {
            throw AppSecurityValidationError.publisherMismatch
        }
    }

    static func applicationGroups(at bundleURL: URL) -> Set<String> { [] }

    static func isSafeIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.utf8.count <= 255
            && identifier.range(of: #"^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$"#, options: .regularExpression) != nil
    }
}
#endif
