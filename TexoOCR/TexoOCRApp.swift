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
            Image(systemName: appState.isProcessing ? "sparkle.magnifyingglass" : "camera.metering.matrix")
                .symbolRenderingMode(.hierarchical)
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
