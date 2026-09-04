import SwiftUI
import WebKit

struct FidelityLoginScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to Fidelity")
                    .font(.headline)
                Spacer()
                Button("Save session") {
                    Task {
                        await appState.saveFidelitySession()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                Button("Close") { dismiss() }
            }
            .padding(12)
            Text("Log in as you normally would, including 2FA. When you see Portfolio or Positions, click Save session. Your password is not stored by this app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            FidelityWebView()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding([.horizontal, .bottom], 12)
        }
        .onAppear {
            FidelityEngine.shared.openPositionsPage()
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
