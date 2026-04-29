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
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        return webView
    }

    /// KaTeX JS and CSS with base64-inlined fonts, loaded once from bundle
    private static let katexJS: String = {
        let url = Bundle.main.url(forResource: "katex.min", withExtension: "js", subdirectory: "katex")
                ?? Bundle.main.url(forResource: "katex.min", withExtension: "js")
        guard let url, let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }()

    private static let katexCSS: String = {
        // Use pre-processed CSS with base64-inlined fonts
        let url = Bundle.main.url(forResource: "katex.inlined", withExtension: "css", subdirectory: "katex")
                ?? Bundle.main.url(forResource: "katex.inlined", withExtension: "css")
        guard let url, let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
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
            .katex { font-size: 1.2em; color: #000000; }
            .katex-display { margin: 0; text-align: center; }
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
