import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label(L.general, systemImage: "gearshape")
                }

            AboutView()
                .tabItem {
                    Label(L.about, systemImage: "info.circle")
                }
        }
        .frame(width: 420, height: 380)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var localization = LocalizationManager.shared
    @State private var isRecording = false
    @State private var selectedLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"

    var body: some View {
        Form {
            Picker(selection: $selectedLanguage) {
                Text("System Default").tag("system")
                Text("English").tag("en")
                Text("简体中文").tag("zh-Hans")
            } label: {
                Label(L.language, systemImage: "globe")
            }
            .onChange(of: selectedLanguage) { _, newValue in
                localization.applyLanguage(newValue)
            }

            LabeledContent {
                ShortcutRecorderButton(
                    display: appState.shortcutDisplay,
                    isRecording: $isRecording,
                    onRecord: { keyCode, modifiers in
                        appState.updateShortcut(keyCode: keyCode, modifiers: modifiers)
                    }
                )
            } label: {
                Label(L.globalShortcut, systemImage: "keyboard")
            }

            Toggle(isOn: Binding(
                get: { appState.autoClipboardMonitoring },
                set: { newValue in
                    appState.autoClipboardMonitoring = newValue
                    if newValue { appState.startMonitoring() }
                    else { appState.stopMonitoring() }
                }
            )) {
                Label(L.autoDetectClipboard, systemImage: "doc.on.clipboard")
            }

            if appState.autoClipboardMonitoring {
                LabeledContent {
                    Text("\(appState.checkInterval, specifier: "%.1f")s")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 32)
                } label: {
                    Slider(value: $appState.checkInterval, in: 0.3...3.0, step: 0.1)
                }
            }

            Toggle(isOn: $appState.showNotifications) {
                Label(L.showNotifications, systemImage: "bell")
            }

            Picker(selection: $appState.maxHistory) {
                Text("20").tag(20)
                Text("50").tag(50)
                Text("100").tag(100)
                Text("200").tag(200)
            } label: {
                Label(L.maxHistory, systemImage: "clock.arrow.circlepath")
            }

            Toggle(isOn: Binding(
                get: { appState.launchAtLogin },
                set: { newValue in
                    appState.launchAtLogin = newValue
                    updateLaunchAtLogin(newValue)
                }
            )) {
                Label(L.launchAtLogin, systemImage: "power")
            }
        }
        .formStyle(.grouped)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            print("Launch at login error: \(error)")
        }
    }
}

// MARK: - Shortcut Recorder

struct ShortcutRecorderButton: View {
    let display: String
    @Binding var isRecording: Bool
    let onRecord: (UInt16, NSEvent.ModifierFlags) -> Void

    var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            Text(isRecording ? L.pressShortcut : display)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isRecording ? Color.accentColor.opacity(0.15) : .secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .background(isRecording ? ShortcutKeyListener(onKey: { keyCode, mods in
            onRecord(keyCode, mods)
            isRecording = false
        }) : nil)
    }
}

struct ShortcutKeyListener: NSViewRepresentable {
    let onKey: (UInt16, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureView {
        let view = ShortcutCaptureView()
        view.onKey = onKey
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureView, context: Context) {}
}

class ShortcutCaptureView: NSView {
    var onKey: ((UInt16, NSEvent.ModifierFlags) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let validMods: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let mods = event.modifierFlags.intersection(validMods)
        guard !mods.isEmpty else { return }
        guard event.keyCode < 55 || event.keyCode > 63 else { return }
        onKey?(event.keyCode, mods)
    }
}

// MARK: - About

struct AboutView: View {
    @State private var showPrivacyPolicy = false
    @State private var showLicenses = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "function")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.blue)

            Text("TexoOCR")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Text("LaTeX Formula Recognition")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)

            Spacer()

            VStack(spacing: 4) {
                Label("FormulaNet", systemImage: "brain")
                Label("ONNX Runtime (MIT)", systemImage: "cpu")
                Label("KaTeX (MIT)", systemImage: "function")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button(L.privacyPolicy) {
                    showPrivacyPolicy = true
                }
                Button(L.licenses) {
                    showLicenses = true
                }
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Spacer().frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showLicenses) {
            LicensesView()
        }
    }
}

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L.privacyPolicy)
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text(L.privacyOverviewTitle)
                            .font(.system(size: 14, weight: .semibold))
                        Text(L.privacyOverview)
                            .font(.system(size: 12))

                        Text(L.privacyDataTitle)
                            .font(.system(size: 14, weight: .semibold))
                        Text(L.privacyData)
                            .font(.system(size: 12))

                        Text(L.privacyLocalTitle)
                            .font(.system(size: 14, weight: .semibold))
                        Text(L.privacyLocal)
                            .font(.system(size: 12))

                        Text(L.privacyContactTitle)
                            .font(.system(size: 14, weight: .semibold))
                        Text("zclk9000@me.com")
                            .font(.system(size: 12))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 420, height: 400)
    }
}

struct LicensesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L.licenses)
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    licenseSection(
                        name: "ONNX Runtime",
                        url: "https://github.com/microsoft/onnxruntime",
                        license: "MIT License\nCopyright (c) Microsoft Corporation.\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files, to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software."
                    )

                    Divider()

                    licenseSection(
                        name: "KaTeX",
                        url: "https://github.com/KaTeX/KaTeX",
                        license: "MIT License\nCopyright (c) 2013-2020 Khan Academy and other contributors.\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files, to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software."
                    )

                    Divider()

                    licenseSection(
                        name: "FormulaNet",
                        url: "https://github.com/Texo-AI/FormulaNet",
                        license: "Model weights used for formula recognition.\nSee project repository for license details."
                    )
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 460, height: 420)
    }

    private func licenseSection(name: String, url: String, license: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
            Text(url)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(license)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
