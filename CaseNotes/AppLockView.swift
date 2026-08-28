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
                ContentUnavailableView {
                    Label("CaseNotes Locked", systemImage: "lock.fill")
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
                }
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
