//
//  AuthenticationService.swift
//  WithU
//
//  Face ID / Touch ID plus a PIN fallback. Only hashes of the PIN and the
//  is stored, in the Keychain.
//

import CryptoKit
import Foundation
import LocalAuthentication
import Observation
import Security

nonisolated enum PINVerification: Sendable {
    case match
    case mismatch
}

@Observable
final class AuthenticationService {
    private enum Key {
        static let pin = "withu.pin.hash"
    }

    private(set) var hasPIN: Bool

    init() {
        hasPIN = Keychain.read(Key.pin) != nil
    }

    var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    var biometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    var biometryName: String {
        switch biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "Face ID"
        }
    }

    /// Returns true when the device owner confirmed with biometrics.
    func authenticateWithBiometrics(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use PIN"
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return false }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            return false
        }
    }

    /// Face ID / Touch ID with the device passcode as fallback. Used before
    /// ending a trip so nobody else can switch tracking off.
    func authenticateOwner(reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            // No passcode set on the device: nothing to verify against.
            return true
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    // MARK: PIN management

    func setPIN(_ pin: String) {
        Keychain.write(Self.hash(pin), for: Key.pin)
        hasPIN = true
    }

    func verify(_ pin: String) -> PINVerification {
        let hashed = Self.hash(pin)
        if let real = Keychain.read(Key.pin), real == hashed { return .match }
        return .mismatch
    }

    private static func hash(_ pin: String) -> String {
        let digest = SHA256.hash(data: Data("withu:\(pin)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Keychain

nonisolated enum Keychain {
    private static let service = "com.jahanzaibali.withu.auth"

    static func write(_ value: String, for key: String) {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
