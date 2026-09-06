import SwiftUI
import AppKit

struct DesktopPanelWindow: View {
    let snapshot: PortfolioSnapshot
    let windowID: String
    @EnvironmentObject private var appState: AppState

    var body: some View {
        PortfolioPanelView(
            snapshot: snapshot,
            scrollable: true,
            fontScale: appState.panelFontScale,
            showsClose: true,
            onClose: {
                appState.setPanelVisible(windowID, false)
                DesktopPanelWindows.close(windowID)
            }
        )
        .padding(14)
        .frame(minWidth: 280, minHeight: 220)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(DesktopWindowConfigurator(windowID: windowID))
    }
}

enum DesktopPanelWindows {
    static func close(_ id: String) {
        for window in NSApplication.shared.windows where matches(window, id: id) {
            window.close()
        }
    }

    static func matches(_ window: NSWindow, id: String) -> Bool {
        if window.identifier?.rawValue == id { return true }
        switch id {
        case "fidelity-desktop":
            return window.title == "Fidelity Positions"
        case "public-desktop":
            return window.title == "Public Positions"
        default:
            return false
        }
    }
}

struct DesktopWindowConfigurator: NSViewRepresentable {
    let windowID: String

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
        window.identifier = NSUserInterfaceItemIdentifier(windowID)
        window.level = .normal
        window.hasShadow = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.resizable)
        window.styleMask.insert(.closable)
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.miniaturizable)
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
