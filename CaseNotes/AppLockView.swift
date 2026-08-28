//
//  AppLockView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import LocalAuthentication
import SwiftUI

struct AppLockView: View {
    @State private var isUnlocked = false
    @State private var authenticationError: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if isUnlocked {
                ContentView()
            } else {
                lockedScreen
            }
        }
        .overlay {
            if scenePhase != .active {
                privacyShield
            }
        }
        .task {
            authenticate()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                if !isUnlocked {
                    authenticate()
                }
            case .inactive, .background:
                isUnlocked = false
            @unknown default:
                isUnlocked = false
            }
        }
    }

    private var lockedScreen: some View {
        ContentUnavailableView {
            Label("CaseNotes Locked", systemImage: "lock.fill")
                .foregroundStyle(Theme.Colors.textPrimary)
        } description: {
            if let authenticationError {
                Text(authenticationError)
            } else {
                Text("Authenticate to access your notes.")
            }
        } actions: {
            Button("Unlock") {
                authenticate()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.accent)
        }
        .background(Theme.Colors.canvas)
    }

    /// Covers the interface whenever the scene leaves the foreground so note
    /// content never appears in the app switcher snapshot.
    private var privacyShield: some View {
        ZStack {
            Rectangle()
                .fill(Theme.Colors.canvas)

            Label("CaseNotes Locked", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .ignoresSafeArea()
    }

    private func authenticate() {
        authenticationError = nil

        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &error
        ) else {
            authenticationError = error?.localizedDescription
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock your notes"
        ) { success, error in
            Task { @MainActor in
                if success {
                    isUnlocked = true
                    authenticationError = nil
                } else {
                    authenticationError = error?.localizedDescription
                }
            }
        }
    }
}
