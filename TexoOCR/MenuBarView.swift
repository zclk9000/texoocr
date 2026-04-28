import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Status
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(appState.statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                if appState.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 8)

            // Accessibility warning
            if !ScreenCaptureService.isAccessibilityGranted {
                Button {
                    ScreenCaptureService.requestAccessibility()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 12))
                        Text(L.accessibilityRequired)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(L.grant)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.08))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider().padding(.horizontal, 8)
            }

            // Actions
            VStack(spacing: 2) {
                MenuButton(
                    icon: "camera.viewfinder",
                    title: L.captureFormula,
                    shortcut: appState.shortcutDisplay,
                    disabled: !appState.engineReady || appState.isProcessing
                ) {
                    appState.captureRegion()
                }

                MenuButton(
                    icon: "photo.on.rectangle.angled",
                    title: L.importImage,
                    disabled: !appState.engineReady || appState.isProcessing
                ) {
                    appState.importImage()
                }
            }
            .padding(.vertical, 4)

            Divider().padding(.horizontal, 8)

            // Recent
            if !appState.history.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L.recent)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    ForEach(appState.history.prefix(5)) { item in
                        Button {
                            appState.copyToClipboard(item.latex)
                        } label: {
                            HStack(spacing: 10) {
                                if let data = item.imageData, let img = NSImage(data: data) {
                                    Image(nsImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 30, height: 30)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                Text(item.latex)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.quaternary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        openWindow(id: "history")
                    } label: {
                        HStack {
                            Spacer()
                            Text(L.showAllHistory)
                                .font(.system(size: 11))
                                .foregroundStyle(.blue)
                            Spacer()
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack {
                    Spacer()
                    Text(L.noResults)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.vertical, 12)
            }

            Divider().padding(.horizontal, 8)

            // Auto-detect toggle
            HStack(spacing: 8) {
                Image(systemName: "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(L.autoDetect)
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appState.autoClipboardMonitoring },
                    set: { newValue in
                        appState.autoClipboardMonitoring = newValue
                        if newValue { appState.startMonitoring() }
                        else { appState.stopMonitoring() }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider().padding(.horizontal, 8)

            // Footer
            HStack {
                SettingsLink {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                        Text(L.settings)
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text(L.quit)
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
    }

    private var statusColor: Color {
        if !appState.engineReady { return .orange }
        if appState.isProcessing { return .blue }
        return .green
    }
}

// MARK: - Menu Button Component

struct MenuButton: View {
    let icon: String
    let title: String
    var shortcut: String? = nil
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(disabled ? .tertiary : .secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
