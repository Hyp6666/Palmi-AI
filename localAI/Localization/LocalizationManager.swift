import SwiftUI
import Combine

@MainActor
final class LocalizationManager: ObservableObject {
    @Published private(set) var currentLanguage: AppLanguage
    @Published private(set) var systemLanguage: AppLanguage
    @Published private(set) var followsSystemLanguage: Bool

    private let userDefaults: UserDefaults
    private var localeChangeCancellable: AnyCancellable?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedPreference = AppLanguage.storedPreference(userDefaults: userDefaults)
        let resolvedSystemLanguage = AppLanguage.resolvedSystemLanguage()
        self.followsSystemLanguage = storedPreference == nil
        self.systemLanguage = resolvedSystemLanguage
        self.currentLanguage = storedPreference ?? resolvedSystemLanguage
        observeSystemLocaleChanges()
    }

    var selectedLanguage: AppLanguage? {
        followsSystemLanguage ? nil : currentLanguage
    }

    func setLanguage(_ language: AppLanguage?) {
        let shouldFollowSystem = language == nil
        let resolvedLanguage = language ?? AppLanguage.resolvedSystemLanguage()

        guard followsSystemLanguage != shouldFollowSystem || currentLanguage != resolvedLanguage else { return }

        followsSystemLanguage = shouldFollowSystem
        currentLanguage = resolvedLanguage

        if let language {
            userDefaults.set(language.rawValue, forKey: AppLanguage.storageKey)
        } else {
            userDefaults.set(AppLanguage.autoStorageValue, forKey: AppLanguage.storageKey)
        }
    }

    func text(_ key: AppLocalizedKey) -> String {
        LocalizationCatalog.text(key, language: currentLanguage)
    }

    private func observeSystemLocaleChanges() {
        localeChangeCancellable = NotificationCenter.default
            .publisher(for: NSLocale.currentLocaleDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let resolvedSystemLanguage = AppLanguage.resolvedSystemLanguage()
                self.systemLanguage = resolvedSystemLanguage
                guard self.followsSystemLanguage else { return }
                self.currentLanguage = resolvedSystemLanguage
            }
    }
}
