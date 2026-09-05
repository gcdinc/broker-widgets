import AppKit
import Foundation
import WebKit

struct CookieRecord: Codable {
    var properties: [String: String]
}

enum FidelityWeb {
    static let summaryURL = URL(string: "https://digital.fidelity.com/ftgw/digital/portfolio/summary")!
    static let positionsURL = URL(string: "https://digital.fidelity.com/ftgw/digital/portfolio/positions")!
    static let storeDefaultsKey = "fidelity.webkit.store.uuid"

    static var dataStoreIdentifier: UUID {
        if let saved = UserDefaults.standard.string(forKey: storeDefaultsKey),
           let uuid = UUID(uuidString: saved) {
            return uuid
        }
        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: storeDefaultsKey)
        return uuid
    }

    static let interceptJavaScript = """
    (function() {
      if (window.__brokerHooked) return;
      window.__brokerHooked = true;
      window.__brokerCaptured = [];
      function keep(url, text) {
        try {
          var u = String(url || '');
          var t = String(text || '');
          if (t.length < 20) return;
          var first = t.charAt(0);
          if (first !== '{' && first !== '[') return;
          if (!/graphql|position|portfolio|balance|holding/i.test(u) && !/symbol|ticker|quantity|qty|holding/i.test(t)) return;
          window.__brokerCaptured.push({ url: u, text: t.slice(0, 1500000) });
          if (window.__brokerCaptured.length > 60) window.__brokerCaptured.shift();
        } catch (e) {}
      }
      var origFetch = window.fetch;
      window.fetch = function() {
        var url = arguments[0];
        return origFetch.apply(this, arguments).then(function(res) {
          try {
            var href = (typeof url === 'string') ? url : (url && url.url);
            res.clone().text().then(function(text) { keep(href, text); }).catch(function() {});
          } catch (e) {}
          return res;
        });
      };
      var origOpen = XMLHttpRequest.prototype.open;
      var origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url) {
        this.__brokerUrl = url;
        return origOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function() {
        this.addEventListener('load', function() { keep(this.__brokerUrl, this.responseText); });
        return origSend.apply(this, arguments);
      };
    })();
    """

    /// GraphQL is WAF-blocked. Scrape the visible Positions table and try same-origin REST.
    static let extractPositionsJavaScript = """
    function keep(url, text) {
      try {
        if (!window.__brokerCaptured) window.__brokerCaptured = [];
        var t = String(text || '');
        if (t.length < 20) return;
        var first = t.charAt(0);
        if (first !== '{' && first !== '[') return;
        window.__brokerCaptured.push({ url: String(url || ''), text: t.slice(0, 1500000) });
        if (window.__brokerCaptured.length > 60) window.__brokerCaptured.shift();
      } catch (e) {}
    }
    function isTicker(sym) {
      if (!sym) return false;
      var s = String(sym).trim().toUpperCase();
      if (!/^[A-Z][A-Z0-9./-]{0,9}$/.test(s)) return false;
      if (/^Z\\d{6,}$/.test(s) || /^\\d{7,}$/.test(s)) return false;
      return true;
    }
    function signedNum(raw) {
      var s = String(raw);
      var neg = /^\\s*[-−]/.test(s) || /\\(.*\\)/.test(s) || /−/.test(s);
      var n = parseFloat(s.replace(/[^0-9.]/g, ''));
      if (!isFinite(n)) return 0;
      return neg ? -n : n;
    }
    var rows = [];
    function addRow(sym, qty, last, mkt, name, day, dayPct) {
      if (!isTicker(sym) || !(qty > 0 || mkt > 0)) return;
      rows.push({
        symbol: String(sym).trim().toUpperCase(),
        quantity: qty || 0,
        lastPrice: last || 0,
        marketVal: mkt || 0,
        securityDescription: name || String(sym).trim().toUpperCase(),
        todaysGainLoss: day || 0,
        todaysGainLossPct: dayPct || 0
      });
    }
    function parseRow(symHint, text) {
      var t = (text || '').replace(/\\s+/g, ' ').trim();
      var m = t.match(/^([A-Z][A-Z0-9./-]{0,9})\\b/);
      var sym = symHint || (m && m[1]);
      if (!isTicker(sym)) return;
      var tokens = t.match(/\\(?[-−+]?\\$?[-−+]?[0-9][0-9,]*\\.?[0-9]*%?\\)?/g) || [];
      var plain = [];
      var pcts = [];
      tokens.forEach(function(tok) {
        var n = signedNum(tok);
        if (tok.indexOf('%') !== -1) pcts.push(n);
        else plain.push(n);
      });
      if (plain.length < 2) return;
      var qty = Math.abs(plain[0]);
      var last = Math.abs(plain[1]);
      var mkt = plain.length > 2 ? Math.abs(plain[2]) : qty * last;
      var day = 0;
      var dayPct = pcts.length ? pcts[0] : 0;
      if (plain.length > 3) {
        var fourth = plain[3];
        if (last > 0 && Math.abs(fourth) <= last * 0.3) {
          day = qty * fourth;
          if (!dayPct) dayPct = (fourth / last) * 100;
        } else {
          day = fourth;
          if (!dayPct && mkt) dayPct = (day / (mkt - day)) * 100;
        }
      }
      addRow(sym, qty, last, mkt, '', day, dayPct);
    }
    document.querySelectorAll('[data-symbol]').forEach(function(el) {
      var row = el.closest('tr, [role="row"], [class*="row"]') || el.parentElement;
      parseRow(el.getAttribute('data-symbol'), row ? row.innerText : '');
    });
    document.querySelectorAll('tr, [role="row"], .ag-row').forEach(function(row) {
      parseRow(null, row.innerText || '');
    });
    if (rows.length) {
      keep('dom:positions', JSON.stringify({ positionDetail: rows }));
    }
    var contextText = null;
    (window.__brokerCaptured || []).forEach(function(c) {
      if (String(c.url || '').indexOf('GetContext') !== -1) contextText = c.text;
    });
    if (!contextText) {
      try {
        var cres = await fetch('/ftgw/digital/portfolio/api/GetContext', { credentials: 'include' });
        contextText = await cres.text();
        keep('/ftgw/digital/portfolio/api/GetContext', contextText);
      } catch (e) {}
    }
    try {
      var ctx = JSON.parse(contextText || '{}');
      var person = (ctx.getContext && ctx.getContext.person) || {};
      var assets = (person.assets || []).filter(function(a) {
        return a && a.acctNum && a.acctType !== 'External' && String(a.acctNum).indexOf('-') === -1;
      });
      var customerId = (person.customerAttrDetail && person.customerAttrDetail.externalCustomerID) || null;
      var acctList = assets.map(function(a) {
        return { acctNum: a.acctNum, acctType: a.acctType, acctSubType: a.acctSubType };
      });
      var restURLs = [
        '/ftgw/digital/portfolio/api/GetPosition',
        '/ftgw/digital/portfolio/api/positions',
        '/ftgw/digital/portfolio/api/GetPositions'
      ];
      for (var i = 0; i < restURLs.length; i++) {
        try {
          var res = await fetch(restURLs[i], {
            method: 'POST',
            credentials: 'include',
            headers: { 'content-type': 'application/json', 'accept': 'application/json' },
            body: JSON.stringify({ acctList: acctList, customerId: customerId })
          });
          keep(restURLs[i], await res.text());
        } catch (e) {}
      }
    } catch (e) {}
    return { rows: rows.length, captured: (window.__brokerCaptured || []).length };
    """

    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: dataStoreIdentifier)
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let script = WKUserScript(source: interceptJavaScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        return config
    }
}

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
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
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
        webView.frame = hostWindow.contentView?.bounds ?? webView.frame
        webView.autoresizingMask = [.width, .height]
        hostWindow.contentView?.addSubview(webView)
        if !hostWindow.isVisible {
            hostWindow.orderBack(nil)
        }
    }

    func openPositionsPage() {
        webView.load(URLRequest(url: FidelityWeb.positionsURL))
    }

    func persistCookies() async throws {
        let cookies = await allCookies()
        let records = cookies.map { cookie -> CookieRecord in
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

        if let current = try? await snapshotFromCurrentPage(), current.status == .ok {
            try? await persistCookies()
            return await withStockMoves(current)
        }

        let href = webView.url?.absoluteString ?? ""
        let alreadyOnPositions = href.contains("/portfolio/positions") && !href.localizedCaseInsensitiveContains("login")
        if !alreadyOnPositions {
            try await load(FidelityWeb.positionsURL)
            try await Task.sleep(nanoseconds: 5_000_000_000)
        } else {
            try await Task.sleep(nanoseconds: 800_000_000)
        }

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
        let page = try await readCapturedPage()
        return FidelityCaptureParser.snapshot(from: page)
    }

    private func readCapturedPage() async throws -> CapturedPage {
        let raw = try await evaluate(Self.readJavaScript)
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
        if navigationContinuation != nil {
            navigationContinuation?.resume(throwing: CancellationError())
            navigationContinuation = nil
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

    private static let readJavaScript = """
    JSON.stringify({
      href: location.href || '',
      title: document.title || '',
      hasPassword: Boolean(document.querySelector('input[type="password"]')),
      captured: (window.__brokerCaptured || []).map(function(c) { return { url: c.url, text: c.text }; }),
      text: (document.body && document.body.innerText) ? document.body.innerText.slice(0, 100000) : ''
    })
    """
}

struct CapturedPage: Decodable {
    var href: String
    var title: String?
    var hasPassword: Bool
    var captured: [CapturedNetwork]
    var text: String?
}

struct CapturedNetwork: Decodable {
    var url: String?
    var text: String?
}


enum FidelityError: LocalizedError {
    case scrapeFailed
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .scrapeFailed:
            return "Fidelity positions page did not return any data. Try signing in again."
        case .fetchFailed(let message):
            return message
        }
    }
}
