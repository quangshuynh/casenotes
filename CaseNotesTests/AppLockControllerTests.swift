//
//  AppLockControllerTests.swift
//  CaseNotesTests
//
//  Created by q on 8/27/26.
//

import Foundation
import SwiftUI
import Testing
@testable import CaseNotes

@MainActor
struct AppLockControllerTests {
    /// Stands in for the system authentication sheet, which no test can drive.
    private final class StubAuthenticator: DeviceAuthenticator {
        var result: Result<Void, Error> = .success(())
        private(set) var attempts = 0

        func authenticate(reason: String) async throws {
            attempts += 1
            try result.get()
        }
    }

    /// An authenticator that lets a test act while an attempt is in flight.
    ///
    /// Stands in for the system sheet being on screen: the hook runs after the
    /// attempt has started and before it resolves. It fires once, so a
    /// controller that authenticates again cannot recurse forever.
    private final class ReentrantAuthenticator: DeviceAuthenticator {
        var result: Result<Void, Error> = .success(())
        var duringAttempt: (() async -> Void)?
        private(set) var attempts = 0

        func authenticate(reason: String) async throws {
            attempts += 1

            let hook = duringAttempt
            duringAttempt = nil
            await hook?()

            try result.get()
        }
    }

    private struct StubError: LocalizedError {
        var errorDescription: String? { "Face ID was not recognized." }
    }

    @Test
    func theAppStartsLocked() {
        let lock = AppLockController(authenticator: StubAuthenticator())

        #expect(lock.isUnlocked == false)
        #expect(lock.errorMessage == nil)
    }

    @Test
    func successfulAuthenticationUnlocks() async {
        let authenticator = StubAuthenticator()
        let lock = AppLockController(authenticator: authenticator)

        await lock.authenticate()

        #expect(lock.isUnlocked)
        #expect(lock.errorMessage == nil)
        #expect(authenticator.attempts == 1)
    }

    @Test
    func failedAuthenticationStaysLockedAndExplainsWhy() async {
        let authenticator = StubAuthenticator()
        authenticator.result = .failure(StubError())
        let lock = AppLockController(authenticator: authenticator)

        await lock.authenticate()

        #expect(lock.isUnlocked == false)
        #expect(lock.errorMessage == "Face ID was not recognized.")
    }

    @Test
    func unavailableAuthenticationIsReportedRatherThanIgnored() async {
        let authenticator = StubAuthenticator()
        authenticator.result = .failure(AppLockError.unavailable)
        let lock = AppLockController(authenticator: authenticator)

        await lock.authenticate()

        #expect(lock.isUnlocked == false)
        #expect(lock.errorMessage == AppLockError.unavailable.errorDescription)
    }

    @Test
    func aRetryClearsThePreviousError() async {
        let authenticator = StubAuthenticator()
        authenticator.result = .failure(StubError())
        let lock = AppLockController(authenticator: authenticator)
        await lock.authenticate()

        authenticator.result = .success(())
        await lock.authenticate()

        #expect(lock.isUnlocked)
        #expect(lock.errorMessage == nil)
    }

    /// The app switcher snapshot is taken while the scene is merely inactive,
    /// so this is the case that actually protects note content.
    @Test
    func leavingTheForegroundRelocks() async {
        let lock = AppLockController(authenticator: StubAuthenticator())
        await lock.authenticate()
        #expect(lock.isUnlocked)

        await lock.scenePhaseChanged(to: .inactive)

        #expect(lock.isUnlocked == false)
    }

    @Test
    func backgroundingRelocks() async {
        let lock = AppLockController(authenticator: StubAuthenticator())
        await lock.authenticate()

        await lock.scenePhaseChanged(to: .background)

        #expect(lock.isUnlocked == false)
    }

    @Test
    func returningToTheForegroundWhileLockedAsksAgain() async {
        let authenticator = StubAuthenticator()
        let lock = AppLockController(authenticator: authenticator)

        await lock.scenePhaseChanged(to: .active)

        #expect(authenticator.attempts == 1)
        #expect(lock.isUnlocked)
    }

    @Test
    func returningToTheForegroundWhileUnlockedDoesNotAskAgain() async {
        let authenticator = StubAuthenticator()
        let lock = AppLockController(authenticator: authenticator)
        await lock.authenticate()

        await lock.scenePhaseChanged(to: .active)

        #expect(authenticator.attempts == 1)
        #expect(lock.isUnlocked)
    }

    @Test
    func aFailedReturnToTheForegroundLeavesTheAppLocked() async {
        let authenticator = StubAuthenticator()
        let lock = AppLockController(authenticator: authenticator)
        await lock.authenticate()
        await lock.scenePhaseChanged(to: .background)

        authenticator.result = .failure(StubError())
        await lock.scenePhaseChanged(to: .active)

        #expect(lock.isUnlocked == false)
        #expect(lock.errorMessage == "Face ID was not recognized.")
    }

    /// The authentication sheet makes the scene inactive and then active again,
    /// so the scene phase asks to unlock while the prompt it caused is still up.
    /// One prompt has to be enough, or the user answers Face ID twice.
    @Test
    func aSceneReturningToActiveDuringAPromptDoesNotStackASecondOne() async {
        let authenticator = ReentrantAuthenticator()
        let lock = AppLockController(authenticator: authenticator)
        authenticator.duringAttempt = { [weak lock] in
            await lock?.scenePhaseChanged(to: .active)
        }

        await lock.authenticate()

        #expect(authenticator.attempts == 1)
        #expect(lock.isUnlocked)
    }

    /// The guard covers a prompt in flight, not the app afterwards. A locked app
    /// still has to be able to ask again.
    @Test
    func authenticationCanBeRequestedAgainOnceAPromptHasFinished() async {
        let authenticator = ReentrantAuthenticator()
        authenticator.result = .failure(StubError())
        let lock = AppLockController(authenticator: authenticator)
        await lock.authenticate()

        authenticator.result = .success(())
        await lock.authenticate()

        #expect(authenticator.attempts == 2)
        #expect(lock.isUnlocked)
    }

    @Test
    func lockingDirectlyTakesEffectImmediately() async {
        let lock = AppLockController(authenticator: StubAuthenticator())
        await lock.authenticate()

        lock.lock()

        #expect(lock.isUnlocked == false)
    }
}
