//
//  localAIApp.swift
//  localAI
//
//  Created by 洪昱鹏 on 2026/3/4.
//

import SwiftUI

@main
struct localAIApp: App {
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceRawValue = AppAppearanceMode.system.rawValue
    @StateObject private var localizationManager = LocalizationManager()

    private var preferredColorScheme: ColorScheme? {
        AppAppearanceMode(rawValue: appearanceRawValue)?.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ChatView()
            }
            .preferredColorScheme(preferredColorScheme)
            .environment(\.locale, Locale(identifier: localizationManager.currentLanguage.localeIdentifier))
            .environmentObject(localizationManager)
        }
    }
}
