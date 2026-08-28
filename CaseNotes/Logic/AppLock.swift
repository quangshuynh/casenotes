//
//  AppLock.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import Foundation
import LocalAuthentication
import SwiftUI

/// Something that can ask the device owner to prove who they are.
///
/// The protocol exists so the lock's policy can be exercised without the system
/// authentication sheet, which no test can drive.
protocol DeviceAuthenticator {
    /// Asks for device owner authentication.
    ///
    /// - Parameter reason: Text shown by the system prompt.
    /// - Throws: When authentication is unavailable, is cancelled, or fails.
    func authenticate(reason: String) async throws
}

/// Reasons the app lock could not admit someone.
enum AppLockError: LocalizedError {
    /// The device has no passcode or biometry configured.
    case unavailable

    /// The attempt completed without succeeding.
    case failed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Device authentication is not available on this device."
        case .failed:
            "Authentication was not successful."
        }
    }
}

/// Device authentication backed by LocalAuthentication.
///
/// Uses `deviceOwnerAuthentication`, so Face ID or Touch ID is offered where
/// available and the device passcode is always a fallback. Nothing is stored and
/// nothing leaves the device: the framework reports success or failure and that
/// is the whole of it.
struct LocalDeviceAuthenticator: DeviceAuthenticator {
    /// Presents the system authentication prompt.
    ///
    /// - Parameter reason: Text shown by the system prompt.
    /// - Throws: The `LAError` reported by LocalAuthentication, or
    ///   ``AppLockError`` when the framework gives no error of its own.
    func authenticate(reason: String) async throws {
        let context = LAContext()
        var availabilityError: NSError?

        guard context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &availabilityError
        ) else {
            throw availabilityError ?? AppLockError.unavailable
        }

        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            ) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? AppLockError.failed)
                }
            }
        }
    }
}

/// Decides when notes are readable.
///
/// The rule is deliberately strict: the app locks the moment the scene stops
/// being active, so returning from the app switcher, a phone call, or a relaunch
/// all require authenticating again. Holding this policy apart from the view
/// keeps it testable, which matters more here than elsewhere because it is the
/// app's only privacy control.
@MainActor
@Observable
final class AppLockController {
    /// Whether notes may currently be shown.
    private(set) var isUnlocked = false

    /// Why the last attempt did not succeed, if it did not.
    private(set) var errorMessage: String?

    private let authenticator: DeviceAuthenticator
    private let reason: String

    /// - Parameters:
    ///   - authenticator: How the user proves who they are. Defaults to the
    ///     LocalAuthentication backed implementation, and is replaced by a stub
    ///     in tests. Built inside the initializer rather than as a default
    ///     argument, since default arguments are evaluated outside this type's
    ///     actor.
    ///   - reason: Text shown by the system authentication prompt.
    init(
        authenticator: DeviceAuthenticator? = nil,
        reason: String = "Unlock your notes"
    ) {
        self.authenticator = authenticator ?? LocalDeviceAuthenticator()
        self.reason = reason
    }

    /// Asks for authentication and unlocks on success.
    ///
    /// A failure leaves the app locked and reports why, so the user can retry
    /// deliberately rather than being trapped on a blank screen.
    func authenticate() async {
        errorMessage = nil

        do {
            try await authenticator.authenticate(reason: reason)
            isUnlocked = true
        } catch {
            isUnlocked = false
            errorMessage = error.localizedDescription
        }
    }

    /// Applies the lock policy for a scene phase change.
    ///
    /// Locking on `inactive` as well as `background` is what keeps note content
    /// out of the app switcher snapshot, since the snapshot is taken while the
    /// scene is merely inactive.
    ///
    /// - Parameter phase: The phase the scene moved to.
    func scenePhaseChanged(to phase: ScenePhase) async {
        switch phase {
        case .active:
            if !isUnlocked {
                await authenticate()
            }
        case .inactive, .background:
            lock()
        @unknown default:
            lock()
        }
    }

    /// Locks the app immediately.
    func lock() {
        isUnlocked = false
    }
}
