import SwiftUI
import WebKit

struct FidelityLoginScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(appState.fidelitySignedIn ? "Fidelity session" : "Sign in to Fidelity")
                    .font(.headline)
                Spacer()
                Button(isSaving ? "Saving…" : "Save session & load positions") {
                    Task {
                        isSaving = true
                        await appState.saveFidelitySession()
                        isSaving = false
                        dismiss()
                        dismissWindow(id: "fidelity-login")
                    }
                }
                .disabled(isSaving)
                .keyboardShortcut(.defaultAction)
                Button("Close") {
                    dismiss()
                    dismissWindow(id: "fidelity-login")
                    NSApplication.shared.windows
                        .filter { $0.title == "Fidelity Sign In" }
                        .forEach { $0.close() }
                }
            }
            .padding(12)
            Text(appState.fidelitySignedIn
                 ? "You're already signed in. Positions should appear here — click Save session to store cookies again. Your password is not stored."
                 : "Log in as usual, including 2FA. Wait until Portfolio or Positions is visible, then click Save session. Your password is not stored.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            FidelityWebView()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding([.horizontal, .bottom], 12)
        }
        .task {
            await FidelityEngine.shared.prepareLoginPage()
        }
        .onDisappear {
            FidelityEngine.shared.returnWebViewToHost()
        }
    }
}

struct FidelityWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let webView = FidelityEngine.shared.webView
        webView.frame = holder.bounds
        webView.autoresizingMask = [.width, .height]
        if webView.superview !== holder {
            webView.removeFromSuperview()
            holder.addSubview(webView)
        }
        return holder
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let webView = FidelityEngine.shared.webView
        if webView.superview !== nsView {
            webView.removeFromSuperview()
            webView.frame = nsView.bounds
            webView.autoresizingMask = [.width, .height]
            nsView.addSubview(webView)
        }
    }
}
