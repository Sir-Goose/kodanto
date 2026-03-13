import AppKit
import SwiftUI
import WebKit

struct TerminalWebView: NSViewRepresentable {
    let sessionID: String
    let outputRevision: Int
    let consumeOutput: () -> [String]
    let onInput: (String) -> Void
    let onResize: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sessionID: sessionID,
            onInput: onInput,
            onResize: onResize
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.updateSessionIfNeeded(sessionID: sessionID)

        if context.coordinator.lastOutputRevision != outputRevision {
            context.coordinator.lastOutputRevision = outputRevision
            context.coordinator.enqueue(chunks: consumeOutput())
        }

        context.coordinator.flush()
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        private let messageHandlerName = "kodantoTerminal"
        private var onInput: (String) -> Void
        private var onResize: (Int, Int) -> Void

        var lastOutputRevision = 0
        private var webView: WKWebView?
        private var sessionID: String
        private var isReady = false
        private var pendingChunks: [String] = []

        init(
            sessionID: String,
            onInput: @escaping (String) -> Void,
            onResize: @escaping (Int, Int) -> Void
        ) {
            self.sessionID = sessionID
            self.onInput = onInput
            self.onResize = onResize
        }

        func makeWebView() -> WKWebView {
            let controller = WKUserContentController()
            controller.add(self, name: messageHandlerName)

            let configuration = WKWebViewConfiguration()
            configuration.userContentController = controller
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true

            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.setValue(false, forKey: "drawsBackground")
            webView.loadHTMLString(Self.html, baseURL: nil)
            self.webView = webView
            return webView
        }

        func teardown() {
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: messageHandlerName)
            webView = nil
            pendingChunks.removeAll(keepingCapacity: false)
        }

        func updateSessionIfNeeded(sessionID: String) {
            guard self.sessionID != sessionID else { return }
            self.sessionID = sessionID
            isReady = false
            pendingChunks.removeAll(keepingCapacity: false)
            webView?.loadHTMLString(Self.html, baseURL: nil)
        }

        func enqueue(chunks: [String]) {
            guard !chunks.isEmpty else { return }
            pendingChunks.append(contentsOf: chunks)
            if pendingChunks.count > 1_000 {
                pendingChunks.removeFirst(pendingChunks.count - 1_000)
            }
        }

        func flush() {
            guard isReady, !pendingChunks.isEmpty, let webView else { return }
            let joined = pendingChunks.joined()
            pendingChunks.removeAll(keepingCapacity: true)

            guard let data = joined.data(using: .utf8) else { return }
            let encoded = data.base64EncodedString()
            webView.evaluateJavaScript("window.kodantoAppendBase64('\(encoded)')")

            webView.evaluateJavaScript("window.kodantoFocus && window.kodantoFocus()")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == messageHandlerName,
                  let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String
            else {
                return
            }

            switch type {
            case "ready":
                isReady = true
                flush()
            case "input":
                if let value = payload["data"] as? String {
                    onInput(value)
                }
            case "resize":
                let rows = (payload["rows"] as? NSNumber)?.intValue ?? (payload["rows"] as? Int)
                let cols = (payload["cols"] as? NSNumber)?.intValue ?? (payload["cols"] as? Int)
                guard let rows, let cols
                else {
                    return
                }
                onResize(rows, cols)
            default:
                break
            }
        }

        private static let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset=\"utf-8\" />
          <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\" />
          <link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/css/xterm.css\" />
          <style>
            html, body {
              margin: 0;
              width: 100%;
              height: 100%;
              overflow: hidden;
              background: #101113;
            }
            #terminal {
              width: 100%;
              height: 100%;
              padding: 10px;
              box-sizing: border-box;
            }
            #fallback {
              display: none;
              color: #d1d5db;
              font: 12px -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
              padding: 12px;
            }
          </style>
        </head>
        <body>
          <div id=\"terminal\"></div>
          <div id=\"fallback\">Terminal renderer failed to load.</div>
          <script src=\"https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/lib/xterm.js\"></script>
          <script src=\"https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.8.0/lib/xterm-addon-fit.min.js\"></script>
          <script>
            (function() {
              const post = (payload) => {
                if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.kodantoTerminal) {
                  return;
                }
                window.webkit.messageHandlers.kodantoTerminal.postMessage(payload);
              };

              const decodeBase64Utf8 = (encoded) => {
                const binary = atob(encoded);
                const bytes = new Uint8Array(binary.length);
                for (let i = 0; i < binary.length; i += 1) {
                  bytes[i] = binary.charCodeAt(i);
                }
                return new TextDecoder().decode(bytes);
              };

              const terminalNode = document.getElementById('terminal');
              const fallbackNode = document.getElementById('fallback');
              let term;
              let fit;
              let queued = [];

              const emitSize = () => {
                if (!term) return;
                post({ type: 'resize', rows: term.rows, cols: term.cols });
              };

              const flushQueue = () => {
                if (!term || queued.length === 0) return;
                const text = queued.join('');
                queued = [];
                term.write(text);
              };

              window.kodantoAppendBase64 = (encoded) => {
                const text = decodeBase64Utf8(encoded);
                if (!text) return;
                if (!term) {
                  queued.push(text);
                  return;
                }
                term.write(text);
              };

              window.kodantoFocus = () => {
                if (term) term.focus();
              };

              const boot = () => {
                if (!window.Terminal || !window.FitAddon || !window.FitAddon.FitAddon) {
                  fallbackNode.style.display = 'block';
                  post({ type: 'ready' });
                  return;
                }

                term = new window.Terminal({
                  cursorBlink: true,
                  convertEol: false,
                  theme: {
                    background: '#101113',
                    foreground: '#e5e7eb',
                    cursor: '#e5e7eb'
                  },
                  fontFamily: 'Menlo, Monaco, SFMono-Regular, ui-monospace, monospace',
                  fontSize: 12,
                  scrollback: 10000
                });

                fit = new window.FitAddon.FitAddon();
                term.loadAddon(fit);
                term.open(terminalNode);
                fit.fit();

                term.onData((data) => {
                  post({ type: 'input', data });
                });

                term.onResize(({ rows, cols }) => {
                  post({ type: 'resize', rows, cols });
                });

                const observer = new ResizeObserver(() => {
                  if (!fit) return;
                  fit.fit();
                  emitSize();
                });
                observer.observe(terminalNode);

                flushQueue();
                emitSize();
                post({ type: 'ready' });
                term.focus();
              };

              if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', boot, { once: true });
              } else {
                boot();
              }
            })();
          </script>
        </body>
        </html>
        """
    }
}
