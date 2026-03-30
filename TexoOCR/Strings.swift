import Foundation

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var bundle: Bundle = .main

    init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        applyLanguage(saved)
    }

    func applyLanguage(_ code: String) {
        UserDefaults.standard.set(code, forKey: "appLanguage")

        if code == "system" {
            bundle = .main
        } else if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
                  let langBundle = Bundle(path: path) {
            bundle = langBundle
        } else {
            bundle = .main
        }

        objectWillChange.send()
    }
}

enum L {
    private static var b: Bundle { LocalizationManager.shared.bundle }

    // MARK: - Status
    static var ready: String { NSLocalizedString("status.ready", bundle: b, comment: "") }
    static var recognizing: String { NSLocalizedString("status.recognizing", bundle: b, comment: "") }
    static var engineFailed: String { NSLocalizedString("status.engineFailed", bundle: b, comment: "") }

    // MARK: - Menu Bar
    static var captureFormula: String { NSLocalizedString("menu.captureFormula", bundle: b, comment: "") }
    static var importImage: String { NSLocalizedString("menu.importImage", bundle: b, comment: "") }
    static var recent: String { NSLocalizedString("menu.recent", bundle: b, comment: "") }
    static var showAllHistory: String { NSLocalizedString("menu.showAllHistory", bundle: b, comment: "") }
    static var noResults: String { NSLocalizedString("menu.noResults", bundle: b, comment: "") }
    static var autoDetect: String { NSLocalizedString("menu.autoDetect", bundle: b, comment: "") }
    static var settings: String { NSLocalizedString("menu.settings", bundle: b, comment: "") }
    static var quit: String { NSLocalizedString("menu.quit", bundle: b, comment: "") }

    // MARK: - History
    static var capturedImage: String { NSLocalizedString("history.capturedImage", bundle: b, comment: "") }
    static var renderedFormula: String { NSLocalizedString("history.renderedFormula", bundle: b, comment: "") }
    static var latexSource: String { NSLocalizedString("history.latexSource", bundle: b, comment: "") }
    static var copy: String { NSLocalizedString("history.copy", bundle: b, comment: "") }
    static var clearAll: String { NSLocalizedString("history.clearAll", bundle: b, comment: "") }
    static var selectItem: String { NSLocalizedString("history.selectItem", bundle: b, comment: "") }
    static var items: String { NSLocalizedString("history.items", bundle: b, comment: "") }
    static var searchPrompt: String { NSLocalizedString("history.searchPrompt", bundle: b, comment: "") }
    static var copyInline: String { NSLocalizedString("history.copyInline", bundle: b, comment: "") }
    static var copyDisplay: String { NSLocalizedString("history.copyDisplay", bundle: b, comment: "") }
    static var copyParens: String { NSLocalizedString("history.copyParens", bundle: b, comment: "") }
    static var save: String { NSLocalizedString("history.save", bundle: b, comment: "") }
    static var revert: String { NSLocalizedString("history.revert", bundle: b, comment: "") }
    static var historyTitle: String { NSLocalizedString("history.title", bundle: b, comment: "") }

    // MARK: - Settings
    static var general: String { NSLocalizedString("settings.general", bundle: b, comment: "") }
    static var about: String { NSLocalizedString("settings.about", bundle: b, comment: "") }
    static var capture: String { NSLocalizedString("settings.capture", bundle: b, comment: "") }
    static var globalShortcut: String { NSLocalizedString("settings.globalShortcut", bundle: b, comment: "") }
    static var pressShortcut: String { NSLocalizedString("settings.pressShortcut", bundle: b, comment: "") }
    static var clipboardMonitoring: String { NSLocalizedString("settings.clipboardMonitoring", bundle: b, comment: "") }
    static var autoDetectClipboard: String { NSLocalizedString("settings.autoDetectClipboard", bundle: b, comment: "") }
    static var notifications: String { NSLocalizedString("settings.notifications", bundle: b, comment: "") }
    static var showNotifications: String { NSLocalizedString("settings.showNotifications", bundle: b, comment: "") }
    static var history: String { NSLocalizedString("settings.history", bundle: b, comment: "") }
    static var maxHistory: String { NSLocalizedString("settings.maxHistory", bundle: b, comment: "") }
    static var system: String { NSLocalizedString("settings.system", bundle: b, comment: "") }
    static var launchAtLogin: String { NSLocalizedString("settings.launchAtLogin", bundle: b, comment: "") }
    static var language: String { NSLocalizedString("settings.language", bundle: b, comment: "") }

    // MARK: - Import
    static var selectFormulaImage: String { NSLocalizedString("import.selectFormulaImage", bundle: b, comment: "") }
    static var couldNotLoad: String { NSLocalizedString("import.couldNotLoad", bundle: b, comment: "") }
}
