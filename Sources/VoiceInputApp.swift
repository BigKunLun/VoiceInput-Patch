//
//  VoiceInputApp.swift
//  VoiceInput
//
//  Created on 2026-03-17.
//

import SwiftUI

@main
struct VoiceInputApp: App {
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("", systemImage: state.isRunning ? "text.bubble.fill" : "text.bubble") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
