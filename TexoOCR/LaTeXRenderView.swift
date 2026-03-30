import SwiftUI
import WebKit

struct LaTeXRenderView: NSViewRepresentable {
    let latex: String
    @Binding var contentHeight: CGFloat

    init(latex: String, contentHeight: Binding<CGFloat> = .constant(80)) {
        self.latex = latex
        self._contentHeight = contentHeight
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    /// Directory with copied katex resources for WKWebView file access
    private static let renderDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("texo-katex")
        let fm = FileManager.default

        // Only copy once per launch
        if !fm.fileExists(atPath: dir.appendingPathComponent("katex.min.js").path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if let katexURL = Bundle.main.resourceURL?.appendingPathComponent("katex") {
                for name in ["katex.min.js", "katex.min.css"] {
                    try? fm.copyItem(at: katexURL.appendingPathComponent(name), to: dir.appendingPathComponent(name))
                }
                let fontsDir = dir.appendingPathComponent("fonts")
                if !fm.fileExists(atPath: fontsDir.path) {
                    try? fm.copyItem(at: katexURL.appendingPathComponent("fonts"), to: fontsDir)
                }
            }
        }
        return dir
    }()

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let processed = Self.injectDisplayStyle(latex)
        let html = buildHTML(latex: processed)

        let htmlFile = Self.renderDir.appendingPathComponent("render.html")
        try? html.write(to: htmlFile, atomically: true, encoding: .utf8)
        webView.loadFileURL(htmlFile, allowingReadAccessTo: Self.renderDir)
    }

    /// Inject \displaystyle into each line of multi-line environments
    /// so fractions, sums etc. render at full size everywhere.
    static func injectDisplayStyle(_ latex: String) -> String {
        var s = latex

        // For each line separator (\\), insert \displaystyle after it
        s = s.replacingOccurrences(of: "\\\\", with: "\\\\ \\displaystyle ")

        // For each & (column separator in arrays/cases), insert \displaystyle after it
        s = s.replacingOccurrences(of: "&", with: "& \\displaystyle ")

        // Prepend \displaystyle to the whole expression
        s = "\\displaystyle " + s

        return s
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: LaTeXRenderView

        init(_ parent: LaTeXRenderView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Poll until KaTeX has rendered (check for .katex element)
            pollHeight(webView: webView, attempts: 0)
        }

        private func pollHeight(webView: WKWebView, attempts: Int) {
            guard attempts < 10 else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                webView.evaluateJavaScript("""
                    (function() {
                        var el = document.querySelector('.katex');
                        if (!el) return -1;
                        return el.getBoundingClientRect().height + 32;
                    })()
                """) { result, _ in
                    if let height = result as? CGFloat, height > 40 {
                        self.parent.contentHeight = height
                    } else {
                        // KaTeX not ready yet, retry
                        self.pollHeight(webView: webView, attempts: attempts + 1)
                    }
                }
            }
        }
    }

    private func buildHTML(latex: String) -> String {
        let escaped = latex
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <link rel="stylesheet" href="katex.min.css">
        <script src="katex.min.js"></script>
        <style>
            * { margin: 0; padding: 0; }
            body {
                padding: 16px;
                display: flex;
                justify-content: center;
                align-items: flex-start;
                background: transparent;
            }
            .katex { font-size: 1.2em; }
            .katex-display { margin: 0; text-align: center; }
            @media (prefers-color-scheme: dark) {
                body { color: #e0e0e0; }
                .katex { color: #e0e0e0; }
            }
            #error { color: #e74c3c; font-family: system-ui; font-size: 13px; }
        </style>
        </head>
        <body>
        <div id="math"></div>
        <div id="error"></div>
        <script>
            try {
                katex.render("\(escaped)", document.getElementById("math"), {
                    displayMode: true,
                    throwOnError: false,
                    output: "html"
                });
            } catch(e) {
                document.getElementById("error").textContent = e.message;
            }
        </script>
        </body>
        </html>
        """
    }
}
