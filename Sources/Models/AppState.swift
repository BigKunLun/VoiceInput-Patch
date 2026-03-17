//
//  AppState.swift
//  VoiceInput
//

import Foundation
import Combine

class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isRunning: Bool = false
    @Published var interceptCount: Int = 0
    @Published var lastPreview: String = ""

    let settings = Settings.shared

    private var interceptService: InterceptService?

    private init() {}

    func start() {
        guard !isRunning else { return }

        interceptService = InterceptService(
            whitelist: settings.enabledTerminalsLowercased,
            onIntercept: { [weak self] text in
                DispatchQueue.main.async {
                    self?.handleIntercept(text)
                }
            }
        )

        interceptService?.start()
        isRunning = true
    }

    func stop() {
        interceptService?.stop()
        interceptService = nil
        isRunning = false
    }

    private func handleIntercept(_ text: String) {
        interceptCount += 1
        lastPreview = String(text.prefix(60))
        TypeService.type(text)
    }
}
