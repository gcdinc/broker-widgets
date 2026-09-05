import SwiftUI
import AppKit

struct DesktopPanelWindow: View {
    let snapshot: PortfolioSnapshot
    let windowID: String
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        PortfolioPanelView(
            snapshot: snapshot,
            scrollable: true,
            fontScale: appState.panelFontScale,
            showsClose: true,
            onClose: {
                dismissWindow(id: windowID)
            }
        )
        .padding(14)
        .frame(minWidth: 280, minHeight: 220)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(DesktopWindowConfigurator())
    }
}

struct DesktopWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.level = .normal
        window.hasShadow = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.resizable)
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.miniaturizable)
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.isEnabled = false
    }
}
