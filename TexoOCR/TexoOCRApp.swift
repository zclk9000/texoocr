import SwiftUI

@main
struct TexoOCRApp: App {
    @StateObject private var appState = AppState()
    @ObservedObject private var localization = LocalizationManager.shared

    init() {}

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .id(localization.bundle)
        } label: {
            if appState.isProcessing {
                Image(systemName: "sparkle.magnifyingglass")
                    .symbolRenderingMode(.hierarchical)
            } else {
                Image("MenuBarIcon")
                    .renderingMode(.template)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .id(localization.bundle)
        }

        Window(L.historyTitle, id: "history") {
            HistoryView()
                .environmentObject(appState)
                .frame(minWidth: 700, minHeight: 500)
                .id(localization.bundle)
        }
    }
}
