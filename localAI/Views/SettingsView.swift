import SwiftUI

struct SettingsView: View {
    private enum SettingsSelector: String, Identifiable {
        case language
        case appearance
        case chatTitle
        case chatStyle
        case thinkingMode

        var id: String { rawValue }

        var titleKey: AppLocalizedKey {
            switch self {
            case .language:
                return .settingsLanguage
            case .appearance:
                return .settingsAppearance
            case .chatTitle:
                return .settingsChatTitle
            case .chatStyle:
                return .settingsChatStyle
            case .thinkingMode:
                return .settingsThinkingMode
            }
        }
    }

    private struct SelectionOption: Identifiable {
        let id: String
        let title: String
        let isSelected: Bool
        let action: () -> Void
    }

    @AppStorage(AppAppearanceMode.storageKey) private var appearanceRawValue = AppAppearanceMode.system.rawValue
    @AppStorage(ChatTitleMode.storageKey) private var chatTitleModeRawValue = ChatTitleMode.content.rawValue
    @AppStorage(ChatStyle.storageKey) private var chatStyleRawValue = ChatStyle.defaultStyle.rawValue
    @AppStorage("thinking_mode_unlocked") private var thinkingModeUnlocked = false
    @EnvironmentObject private var localization: LocalizationManager

    @State private var activeSelector: SettingsSelector?
    @State private var showThinkingModeWarning = false
    @State private var showDeleteHistoryConfirmation = false
    @State private var showRestoreDefaultsConfirmation = false
    @State private var pendingThinkingModeEnable = false

    private var appearanceBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { AppAppearanceMode(rawValue: appearanceRawValue) ?? .system },
            set: { appearanceRawValue = $0.rawValue }
        )
    }

    private var chatTitleModeBinding: Binding<ChatTitleMode> {
        Binding(
            get: { ChatTitleMode(rawValue: chatTitleModeRawValue) ?? .content },
            set: { chatTitleModeRawValue = $0.rawValue }
        )
    }

    private var chatStyleBinding: Binding<ChatStyle> {
        Binding(
            get: { ChatStyle(rawValue: chatStyleRawValue) ?? .defaultStyle },
            set: { chatStyleRawValue = $0.rawValue }
        )
    }

    private var languageBinding: Binding<AppLanguage?> {
        Binding(
            get: { localization.selectedLanguage },
            set: { localization.setLanguage($0) }
        )
    }

    private var displayedLanguageLabel: String {
        if localization.followsSystemLanguage {
            return localization.text(.settingsLanguageAuto)
                .replacingOccurrences(of: "%@", with: localization.systemLanguage.displayName)
        }
        return localization.currentLanguage.displayName
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient
                .ignoresSafeArea()
                .blur(radius: activeSelector == nil ? 0 : 2)

            Form {
                Section {
                    selectionRow(value: displayedLanguageLabel) {
                        activeSelector = .language
                    }
                } header: {
                    Text(localization.text(.settingsLanguage))
                }

                Section {
                    selectionRow(value: localization.text(appearanceBinding.wrappedValue.titleKey)) {
                        activeSelector = .appearance
                    }
                } header: {
                    Text(localization.text(.settingsAppearance))
                }

                Section {
                    selectionRow(value: localization.text(chatTitleModeBinding.wrappedValue.titleKey)) {
                        activeSelector = .chatTitle
                    }
                } header: {
                    Text(localization.text(.settingsChatTitle))
                }

                Section {
                    selectionRow(value: localization.text(chatStyleBinding.wrappedValue.titleKey)) {
                        activeSelector = .chatStyle
                    }
                } header: {
                    Text(localization.text(.settingsChatStyle))
                }

                Section {
                    selectionRow(value: localization.text(thinkingModeUnlocked ? .thinkingModeEnabled : .thinkingModeDisabled)) {
                        activeSelector = .thinkingMode
                    }
                } header: {
                    Text(localization.text(.settingsThinkingMode))
                }

                Section {
                    destructiveActionRow(localization.text(.settingsDeleteHistoryAction)) {
                        showDeleteHistoryConfirmation = true
                    }
                } header: {
                    Text(localization.text(.settingsDeleteHistory))
                }

                Section {
                    destructiveActionRow(localization.text(.settingsRestoreDefaultsAction)) {
                        showRestoreDefaultsConfirmation = true
                    }
                } header: {
                    Text(localization.text(.settingsRestoreDefaults))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .blur(radius: activeSelector == nil ? 0 : 2)
            .disabled(activeSelector != nil)

            if let activeSelector {
                selectionOverlay(for: activeSelector)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: activeSelector)
        .alert(localization.text(.settingsThinkingMode), isPresented: $showThinkingModeWarning) {
            Button(localization.text(.commonCancel), role: .cancel) {
                pendingThinkingModeEnable = false
            }
            Button(localization.text(.thinkingModeWarningConfirm)) {
                thinkingModeUnlocked = true
                pendingThinkingModeEnable = false
            }
        } message: {
            Text(localization.text(.thinkingModeWarning))
        }
        .alert(localization.text(.settingsDeleteHistoryTitle), isPresented: $showDeleteHistoryConfirmation) {
            Button(localization.text(.commonCancel), role: .cancel) { }
            Button(localization.text(.settingsDeleteHistoryConfirm), role: .destructive) {
                ChatViewModel.deleteAllLocalHistory()
            }
        } message: {
            Text(localization.text(.settingsDeleteHistoryMessage))
        }
        .alert(localization.text(.settingsRestoreDefaultsTitle), isPresented: $showRestoreDefaultsConfirmation) {
            Button(localization.text(.commonCancel), role: .cancel) { }
            Button(localization.text(.settingsRestoreDefaultsConfirm), role: .destructive) {
                localization.setLanguage(nil)
                appearanceRawValue = AppAppearanceMode.system.rawValue
                chatTitleModeRawValue = ChatTitleMode.content.rawValue
                chatStyleRawValue = ChatStyle.defaultStyle.rawValue
                thinkingModeUnlocked = false
                ChatViewModel.restoreDefaultSettings()
            }
        } message: {
            Text(localization.text(.settingsRestoreDefaultsMessage))
        }
        .navigationTitle(localization.text(.settingsTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func selectionRow(value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(value)
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func destructiveActionRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(Color.red)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func selectionOverlay(for selector: SettingsSelector) -> some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture {
                    activeSelector = nil
                }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(localization.text(selector.titleKey))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)

                    Spacer()

                    Button(localization.text(.commonCancel)) {
                        activeSelector = nil
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

                Divider()
                    .overlay(Color.white.opacity(0.08))

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(selectionOptions(for: selector)) { option in
                            Button {
                                option.action()
                                activeSelector = nil
                            } label: {
                                HStack(spacing: 12) {
                                    Text(option.title)
                                        .foregroundStyle(AppTheme.primaryText)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    if option.isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(option.isSelected ? AppTheme.accent.opacity(0.16) : Color.white.opacity(0.08))
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(option.isSelected ? AppTheme.accent.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                }
                .frame(maxHeight: 360)
            }
            .frame(maxWidth: 380)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .shadow(color: .black.opacity(0.18), radius: 28, x: 0, y: 14)
            .padding(.horizontal, 20)
        }
    }

    private func selectionOptions(for selector: SettingsSelector) -> [SelectionOption] {
        switch selector {
        case .language:
            let autoOption = SelectionOption(
                id: AppLanguage.autoStorageValue,
                title: localization.text(.settingsLanguageAuto)
                    .replacingOccurrences(of: "%@", with: localization.systemLanguage.displayName),
                isSelected: localization.followsSystemLanguage,
                action: { languageBinding.wrappedValue = nil }
            )
            let manualOptions = AppLanguage.allCases.map { language in
                SelectionOption(
                    id: language.rawValue,
                    title: language.displayName,
                    isSelected: languageBinding.wrappedValue == language,
                    action: { languageBinding.wrappedValue = language }
                )
            }
            return [autoOption] + manualOptions
        case .appearance:
            return AppAppearanceMode.allCases.map { mode in
                SelectionOption(
                    id: mode.rawValue,
                    title: localization.text(mode.titleKey),
                    isSelected: appearanceBinding.wrappedValue == mode,
                    action: { appearanceBinding.wrappedValue = mode }
                )
            }
        case .chatTitle:
            return ChatTitleMode.allCases.map { mode in
                SelectionOption(
                    id: mode.rawValue,
                    title: localization.text(mode.titleKey),
                    isSelected: chatTitleModeBinding.wrappedValue == mode,
                    action: { chatTitleModeBinding.wrappedValue = mode }
                )
            }
        case .chatStyle:
            return ChatStyle.allCases.map { style in
                SelectionOption(
                    id: style.rawValue,
                    title: localization.text(style.titleKey),
                    isSelected: chatStyleBinding.wrappedValue == style,
                    action: { chatStyleBinding.wrappedValue = style }
                )
            }
        case .thinkingMode:
            return [
                SelectionOption(
                    id: "enabled",
                    title: localization.text(.thinkingModeEnabled),
                    isSelected: thinkingModeUnlocked,
                    action: {
                        if !thinkingModeUnlocked {
                            pendingThinkingModeEnable = true
                            showThinkingModeWarning = true
                        }
                    }
                ),
                SelectionOption(
                    id: "disabled",
                    title: localization.text(.thinkingModeDisabled),
                    isSelected: !thinkingModeUnlocked,
                    action: { thinkingModeUnlocked = false }
                )
            ]
        }
    }
}

#Preview("设置") {
    NavigationStack {
        SettingsView()
            .environmentObject(LocalizationManager())
    }
}
