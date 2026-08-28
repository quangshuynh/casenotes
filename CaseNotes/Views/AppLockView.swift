//
//  AppLockView.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftUI

/// Gates the app behind device authentication.
///
/// The view is only presentation. Every decision about when the app is readable
/// lives in ``AppLockController``.
struct AppLockView: View {
    @State private var lock = AppLockController()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if lock.isUnlocked {
                ContentView()
            } else {
                lockedScreen
            }
        }
        // Only the unlock swap is animated. A crossfade softens what is
        // otherwise an abrupt replacement of the whole interface.
        .animation(reduceMotion ? nil : Theme.Motion.unlock, value: lock.isUnlocked)
        .overlay {
            if scenePhase != .active {
                privacyShield
            }
        }
        .task {
            await lock.authenticate()
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task {
                await lock.scenePhaseChanged(to: newPhase)
            }
        }
    }

    /// Shown while the app is locked, explaining the last failure if there was one.
    private var lockedScreen: some View {
        ContentUnavailableView {
            Label("CaseNotes Locked", systemImage: "lock.fill")
                .foregroundStyle(Theme.Colors.textPrimary)
        } description: {
            if let errorMessage = lock.errorMessage {
                Text(errorMessage)
            } else {
                Text("Authenticate to access your notes.")
            }
        } actions: {
            Button("Unlock") {
                Task {
                    await lock.authenticate()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.accent)
        }
        .background(Theme.Colors.canvas)
    }

    /// Covers the interface whenever the scene leaves the foreground so note
    /// content never appears in the app switcher snapshot.
    ///
    /// Deliberately never animated. The system snapshots the window as the
    /// scene becomes inactive, and a shield that faded in would be caught
    /// mid-transition with note content still visible behind it.
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
}
