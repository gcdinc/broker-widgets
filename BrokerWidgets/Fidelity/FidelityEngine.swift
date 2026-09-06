import AppKit
import Foundation
import WebKit

@MainActor
final class FidelityEngine: NSObject, WKNavigationDelegate {
    static let shared = FidelityEngine()

    let webView: WKWebView
    private let hostWindow: NSWindow
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    override init() {
        let config = FidelityWeb.makeConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: config)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 1
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
        window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.setFrameOrigin(NSPoint(x: -12000, y: -12000))
        hostWindow = window
        super.init()
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        returnWebViewToHost()
    }

    var isLikelySignedIn: Bool {
        KeychainStore.getData(.fidelityCookies) != nil
    }

    func returnWebViewToHost() {
        webView.removeFromSuperview()
        webView.frame = hostWindow.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        webView.autoresizingMask = [.width, .height]
        hostWindow.contentView?.addSubview(webView)
        hostWindow.setFrameOrigin(NSPoint(x: -12000, y: -12000))
        hostWindow.orderBack(nil)
    }

    func prepareLoginPage() async {
        for _ in 0..<30 {
            if webView.window != nil, webView.window !== hostWindow { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        await restoreCookiesIfNeeded()
        _ = try? await evaluate(FidelityWeb.interceptJavaScript)
        webView.load(URLRequest(url: FidelityWeb.positionsURL))
    }

    func persistCookies() async throws {
        let cookies = await allCookies()
        let records = cookies.map(Self.record(from:))
        try KeychainStore.setData(try JSONEncoder().encode(records), for: .fidelityCookies)
    }

    func restoreCookiesIfNeeded() async {
        guard let data = KeychainStore.getData(.fidelityCookies),
              let records = try? JSONDecoder().decode([CookieRecord].self, from: data) else {
            return
        }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for record in records {
            var props: [HTTPCookiePropertyKey: Any] = [:]
            for (key, value) in record.properties {
                props[HTTPCookiePropertyKey(key)] = value
            }
            if let cookie = HTTPCookie(properties: props) {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    store.setCookie(cookie) { cont.resume() }
                }
            }
        }
    }

    func signOut() async {
        KeychainStore.delete(.fidelityCookies)
        await webView.configuration.websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }

    func fetchPositions() async throws -> PortfolioSnapshot {
        if webView.superview == nil {
            returnWebViewToHost()
        }
        await restoreCookiesIfNeeded()
        _ = try? await evaluate(FidelityWeb.interceptJavaScript)
        try await waitForPositionsPage()
        return try await extractSnapshot()
    }

    private func waitForPositionsPage() async throws {
        let href = webView.url?.absoluteString ?? ""
        let onPositions = href.contains("/portfolio/positions") && !href.localizedCaseInsensitiveContains("login")
        if onPositions {
            try await Task.sleep(nanoseconds: 1_200_000_000)
            return
        }
        try await load(FidelityWeb.positionsURL)
        try await Task.sleep(nanoseconds: 6_000_000_000)
    }

    private func extractSnapshot() async throws -> PortfolioSnapshot {
        _ = try? await evaluateAsync(FidelityWeb.extractPositionsJavaScript)
        try? await persistCookies()
        let extracted = try await snapshotFromCurrentPage()
        if extracted.status == .ok || isWebViewInLoginUI {
            return await withStockMoves(extracted)
        }
        try await load(FidelityWeb.positionsURL)
        try await Task.sleep(nanoseconds: 6_000_000_000)
        _ = try? await evaluateAsync(FidelityWeb.extractPositionsJavaScript)
        try? await persistCookies()
        return await withStockMoves(try await snapshotFromCurrentPage())
    }

    private func withStockMoves(_ snapshot: PortfolioSnapshot) async -> PortfolioSnapshot {
        guard snapshot.status == .ok else { return snapshot }
        var copy = snapshot
        copy.positions = await MarketQuotes.fillDayChanges(snapshot.positions)
        return copy
    }

    private var isWebViewInLoginUI: Bool {
        webView.window != nil && webView.window !== hostWindow
    }

    private func snapshotFromCurrentPage() async throws -> PortfolioSnapshot {
        FidelityCaptureParser.snapshot(from: try await readCapturedPage())
    }

    private func readCapturedPage() async throws -> CapturedPage {
        let raw = try await evaluate(FidelityWeb.readJavaScript)
        let data: Data
        if let string = raw as? String, let encoded = string.data(using: .utf8) {
            data = encoded
        } else {
            data = try JSONSerialization.data(withJSONObject: raw as Any)
        }
        return try JSONDecoder().decode(CapturedPage.self, from: data)
    }

    private func evaluate(_ script: String) async throws -> Any {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Any, Error>) in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: result ?? NSNull())
                }
            }
        }
    }

    private func evaluateAsync(_ script: String) async throws -> Any {
        try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) ?? NSNull()
    }

    private func load(_ url: URL) async throws {
        if let navigationContinuation {
            navigationContinuation.resume(throwing: CancellationError())
            self.navigationContinuation = nil
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            navigationContinuation = cont
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45))
        }
    }

    private func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { cont in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cont.resume(returning: $0) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishNavigation(error: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishNavigation(error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishNavigation(error: error)
    }

    private func finishNavigation(error: Error?) {
        guard let navigationContinuation else { return }
        self.navigationContinuation = nil
        if let error {
            navigationContinuation.resume(throwing: error)
        } else {
            navigationContinuation.resume(returning: ())
        }
    }

    private static func record(from cookie: HTTPCookie) -> CookieRecord {
        let props = cookie.properties ?? [:]
        var encoded: [String: String] = [:]
        for (key, value) in props {
            encoded[key.rawValue] = String(describing: value)
        }
        encoded["Name"] = cookie.name
        encoded["Value"] = cookie.value
        encoded["Domain"] = cookie.domain
        encoded["Path"] = cookie.path
        encoded["Secure"] = cookie.isSecure ? "TRUE" : "FALSE"
        return CookieRecord(properties: encoded)
    }
}
