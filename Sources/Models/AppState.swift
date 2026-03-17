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
            bundleIdWhitelist: settings.enabledBundleIds,
            onIntercept: { [weak self] text, completion in
                DispatchQueue.main.async {
                    self?.interceptCount += 1
                    let truncated = text.count > TypeService.maxLength
                    self?.lastPreview = String(text.prefix(60)) + (truncated ? " [已截断]" : "")
                }
                TypeService.type(text, completion: completion)
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

}
