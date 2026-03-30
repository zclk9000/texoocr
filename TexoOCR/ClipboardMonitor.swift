import AppKit

class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int
    private let interval: TimeInterval
    private let onNewImage: (NSImage) -> Void
    private var isPaused = false

    init(interval: TimeInterval = 0.5, onNewImage: @escaping (NSImage) -> Void) {
        self.interval = interval
        self.onNewImage = onNewImage
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        lastChangeCount = NSPasteboard.general.changeCount
        isPaused = false
    }

    private func checkClipboard() {
        guard !isPaused else { return }

        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard let types = pasteboard.types,
              types.contains(.tiff) || types.contains(.png) else { return }

        if let image = NSImage(pasteboard: pasteboard) {
            onNewImage(image)
        }
    }
}
