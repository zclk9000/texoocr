import SwiftUI
import Combine
import UserNotifications

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    // Show notification even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

struct HistoryItem: Identifiable, Codable, Sendable {
    let id: UUID
    let latex: String
    let timestamp: Date
    let imageData: Data?

    init(latex: String, imageData: Data? = nil) {
        self.id = UUID()
        self.latex = latex
        self.timestamp = Date()
        self.imageData = imageData
    }

    init(id: UUID, latex: String, timestamp: Date, imageData: Data?) {
        self.id = id
        self.latex = latex
        self.timestamp = timestamp
        self.imageData = imageData
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var isMonitoring = false
    @Published var isProcessing = false
    @Published var history: [HistoryItem] = []
    @Published var lastResult: String?
    enum Status {
        case ready, recognizing, error(String)
    }
    @Published var status: Status = .ready

    var statusMessage: String {
        switch status {
        case .ready: return L.ready
        case .recognizing: return L.recognizing
        case .error(let msg): return msg
        }
    }
    @Published var engineReady = false

    @AppStorage("autoClipboardMonitoring") var autoClipboardMonitoring = false
    @AppStorage("checkInterval") var checkInterval: Double = 0.5
    @AppStorage("showNotifications") var showNotifications = true
    @AppStorage("maxHistory") var maxHistory = 50
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("hotkeyCode") var hotkeyCode: Int = 37       // L
    @AppStorage("hotkeyModifiers") var hotkeyModifiers: Int = 0  // stored raw value

    @Published var shortcutDisplay = "⌘⇧L"

    private var clipboardMonitor: ClipboardMonitor?
    private var ocrEngine: OCREngine?
    private let captureService = ScreenCaptureService()
    var hotkeyManager: HotkeyManager?

    init() {
        loadHistory()
        setupEngine()
        setupNotifications()

        let code = UInt16(UserDefaults.standard.integer(forKey: "hotkeyCode"))
        let modsRaw = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        let mods: NSEvent.ModifierFlags = modsRaw == 0
            ? [.command, .shift]
            : NSEvent.ModifierFlags(rawValue: UInt(modsRaw))

        hotkeyManager = HotkeyManager(keyCode: code == 0 ? 37 : code, modifiers: mods) { [weak self] in
            Task { @MainActor in
                self?.captureRegion()
            }
        }
        shortcutDisplay = HotkeyManager.shortcutDisplayString(
            keyCode: hotkeyManager!.keyCode, modifiers: hotkeyManager!.modifiers
        )
    }

    func updateShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        hotkeyManager?.updateShortcut(keyCode: keyCode, modifiers: modifiers)
        hotkeyCode = Int(keyCode)
        hotkeyModifiers = Int(modifiers.rawValue)
        shortcutDisplay = HotkeyManager.shortcutDisplayString(keyCode: keyCode, modifiers: modifiers)
    }

    private func setupEngine() {
        Task {
            do {
                let engine = try await Task.detached { try OCREngine() }.value
                self.ocrEngine = engine
                self.engineReady = true
                self.status = .ready
                if self.autoClipboardMonitoring {
                    self.startMonitoring()
                }
            } catch {
                self.status = .error("\(L.engineFailed): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Capture & Import

    func captureRegion() {
        guard engineReady, !isProcessing else { return }

        clipboardMonitor?.pause()

        Task {
            do {
                let image = try await captureService.captureRegion()
                self.processImage(image)
            } catch is ScreenCaptureService.CaptureError {
                // User cancelled or no image — silent
            } catch {
                self.status = .error("Capture: \(error.localizedDescription)")
                print("[Capture] Error: \(error)")
            }
            self.clipboardMonitor?.resume()
        }
    }

    func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L.selectFormulaImage

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url) else {
            status = .error(L.couldNotLoad)
            return
        }
        processImage(image)
    }

    // MARK: - Clipboard Monitoring

    func startMonitoring() {
        guard clipboardMonitor == nil else { return }
        clipboardMonitor = ClipboardMonitor(interval: checkInterval) { [weak self] image in
            Task { @MainActor in
                self?.processImage(image)
            }
        }
        clipboardMonitor?.start()
        isMonitoring = true
    }

    func stopMonitoring() {
        clipboardMonitor?.stop()
        clipboardMonitor = nil
        isMonitoring = false
    }

    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    // MARK: - OCR Processing

    func processImage(_ image: NSImage) {
        guard let engine = ocrEngine, !isProcessing else { return }

        let imageData = image.tiffRepresentation
        isProcessing = true
        status = .recognizing

        // Run OCR on background thread, update UI on main
        let recognizer = engine
        Task {
            do {
                let latex = try await Task.detached {
                    try recognizer.recognize(image: image)
                }.value

                self.lastResult = latex
                self.isProcessing = false
                self.status = .ready

                let item = HistoryItem(latex: latex, imageData: imageData)
                self.history.insert(item, at: 0)
                if self.history.count > self.maxHistory {
                    self.history = Array(self.history.prefix(self.maxHistory))
                }
                self.saveHistory()

                self.clipboardMonitor?.pause()
                self.copyToClipboard(latex)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.clipboardMonitor?.resume()
                }

                if self.showNotifications {
                    self.sendNotification(latex: latex)
                }
            } catch {
                self.isProcessing = false
                self.status = .error(error.localizedDescription)
            }
        }
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func setupNotifications() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            print("[Notification] Authorization: granted=\(granted), error=\(String(describing: error))")
        }
    }

    private func sendNotification(latex: String) {
        let content = UNMutableNotificationContent()
        content.title = "LaTeX Recognized"
        content.body = String(latex.prefix(80))
        content.sound = .default

        // Use a tiny delay trigger instead of nil (more reliable on macOS)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[Notification] Failed: \(error)")
            } else {
                print("[Notification] Sent successfully")
            }
        }
    }

    // MARK: - Persistence

    private var historyURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TexoOCR", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(Array(history.prefix(maxHistory))) {
            try? data.write(to: historyURL)
        }
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let items = try? decoder.decode([HistoryItem].self, from: data) {
            history = items
        }
    }

    func updateHistoryItem(id: UUID, latex: String) {
        if let index = history.firstIndex(where: { $0.id == id }) {
            let old = history[index]
            history[index] = HistoryItem(id: old.id, latex: latex, timestamp: old.timestamp, imageData: old.imageData)
            saveHistory()
        }
    }

    func clearHistory() {
        history.removeAll()
        try? FileManager.default.removeItem(at: historyURL)
    }
}
