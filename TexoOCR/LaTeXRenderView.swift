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
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    /// Inlined KaTeX JS, CSS (with base64 fonts) — loaded once from bundle
    private static let katexJS: String = {
        // Try subdirectory first (folder reference), then flat (group)
        let url = Bundle.main.url(forResource: "katex.min", withExtension: "js", subdirectory: "katex")
                ?? Bundle.main.url(forResource: "katex.min", withExtension: "js")
        guard let url, let js = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return js
    }()

    private static let katexCSS: String = {
        let cssURL = Bundle.main.url(forResource: "katex.min", withExtension: "css", subdirectory: "katex")
                   ?? Bundle.main.url(forResource: "katex.min", withExtension: "css")
        guard let cssURL, var css = try? String(contentsOf: cssURL, encoding: .utf8) else { return "" }

        // Find fonts directory
        let fontsDir: URL? = {
            if let d = Bundle.main.resourceURL?.appendingPathComponent("katex/fonts"),
               FileManager.default.fileExists(atPath: d.path) { return d }
            if let d = Bundle.main.resourceURL?.appendingPathComponent("fonts"),
               FileManager.default.fileExists(atPath: d.path) { return d }
            return nil
        }()

        // Replace font URL references with inline base64 data URIs
        if let fontsDir {
            let pattern = try! NSRegularExpression(pattern: #"url\(fonts/([^)]+\.woff2)\)"#)
            while let match = pattern.firstMatch(in: css, range: NSRange(css.startIndex..., in: css)) {
                guard let fileRange = Range(match.range(at: 1), in: css),
                      let fullRange = Range(match.range, in: css) else { break }
                let filename = String(css[fileRange])
                let fontURL = fontsDir.appendingPathComponent(filename)
                if let data = try? Data(contentsOf: fontURL) {
                    let b64 = data.base64EncodedString()
                    css.replaceSubrange(fullRange, with: "url(data:font/woff2;base64,\(b64))")
                } else {
                    // Font file missing — remove the url() so regex won't match it again
                    css.replaceSubrange(fullRange, with: "url()")
                }
            }
        }

        return css
    }()

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let processed = Self.injectDisplayStyle(latex)
        let html = buildHTML(latex: processed)
        webView.loadHTMLString(html, baseURL: nil)
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
        <style>\(Self.katexCSS)</style>
        <script>\(Self.katexJS)</script>
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
