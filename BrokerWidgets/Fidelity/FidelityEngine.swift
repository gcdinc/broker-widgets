import Foundation
import WebKit

struct CookieRecord: Codable {
    var properties: [String: String]
}

enum FidelityWeb {
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

    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: dataStoreIdentifier)
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        return config
    }
}

final class FidelityEngine: NSObject, WKNavigationDelegate {
    static let shared = FidelityEngine()

    let webView: WKWebView
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    override init() {
        let config = FidelityWeb.makeConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    }

    var isLikelySignedIn: Bool {
        KeychainStore.getData(.fidelityCookies) != nil
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
        let data = try JSONEncoder().encode(records)
        try KeychainStore.setData(data, for: .fidelityCookies)
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
        let store = webView.configuration.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await store.removeData(ofTypes: types, modifiedSince: .distantPast)
    }

    func fetchPositions() async throws -> PortfolioSnapshot {
        await restoreCookiesIfNeeded()
        try await load(FidelityWeb.positionsURL)
        try await Task.sleep(nanoseconds: 3_500_000_000)
        try await persistCookies()

        guard let raw = try await webView.evaluateJavaScript(Self.scrapeJavaScript) else {
            throw FidelityError.scrapeFailed
        }
        let data = try JSONSerialization.data(withJSONObject: raw)
        let scraped = try JSONDecoder().decode(FidelityScrapeResult.self, from: data)

        if !scraped.signedIn {
            return PortfolioSnapshot.setup(.fidelity)
        }

        let positions: [Position] = scraped.positions.compactMap { row in
            let symbol = row.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !symbol.isEmpty else { return nil }
            let qty = row.quantity ?? 0
            let last = row.lastPrice ?? 0
            let value = (row.marketValue ?? 0) == 0 ? qty * last : (row.marketValue ?? 0)
            return Position(
                symbol: symbol,
                name: row.name ?? symbol,
                quantity: qty,
                lastPrice: last,
                marketValue: value,
                dayChangeValue: row.dayChangeValue ?? 0,
                dayChangePercent: row.dayChangePercent ?? 0
            )
        }
        .sorted { $0.resolvedMarketValue > $1.resolvedMarketValue }

        let dayChange = positions.reduce(0) { $0 + $1.dayChangeValue }
        var total = scraped.totalValue ?? 0
        if total == 0 {
            total = positions.reduce(0) { $0 + $1.resolvedMarketValue }
        }
        let prior = total - dayChange
        let dayPct = prior == 0 ? 0 : (dayChange / prior) * 100

        let status: SnapshotStatus = positions.isEmpty ? .empty : .ok
        return PortfolioSnapshot(
            broker: .fidelity,
            updatedAt: Date(),
            totalValue: total,
            dayChangeValue: dayChange,
            dayChangePercent: dayPct,
            cash: nil,
            positions: positions,
            status: status,
            message: positions.isEmpty ? "Signed in, but no positions were found on the page." : nil
        )
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

    private static let scrapeJavaScript = """
    (() => {
      const href = location.href || '';
      const hasPassword = Boolean(document.querySelector('input[type="password"]'));
      const signedIn = !/\\/login/i.test(href) && !hasPassword;

      const parseMoney = (s) => {
        if (s === null || s === undefined) return null;
        const str = String(s);
        const neg = /\\(.*\\)/.test(str) || /^\\s*-/.test(str);
        const n = parseFloat(str.replace(/[^0-9.]/g, ''));
        if (Number.isNaN(n)) return null;
        return neg ? -Math.abs(n) : n;
      };

      const positions = [];
      const seen = new Set();
      const add = (p) => {
        if (!p || !p.symbol) return;
        const symbol = String(p.symbol).trim().toUpperCase();
        if (!/^[A-Z][A-Z0-9./^-]{0,20}$/.test(symbol)) return;
        if (seen.has(symbol)) return;
        seen.add(symbol);
        positions.push({
          symbol,
          name: p.name || symbol,
          quantity: Number(p.quantity) || 0,
          lastPrice: Number(p.lastPrice) || 0,
          marketValue: Number(p.marketValue) || 0,
          dayChangeValue: Number(p.dayChangeValue) || 0,
          dayChangePercent: Number(p.dayChangePercent) || 0
        });
      };

      const walk = (node) => {
        if (!node) return;
        if (Array.isArray(node)) { node.forEach(walk); return; }
        if (typeof node !== 'object') return;
        const symbol = node.symbol || node.ticker || node.underlyingSymbol || node.optionSymbol;
        const qty = node.quantity ?? node.qty ?? node.shares ?? node.shareQuantity ?? node.quantityLong;
        const last = node.lastPrice ?? node.price ?? node.currentPrice ?? node.last ?? node.mark;
        const value = node.marketValue ?? node.currentValue ?? node.mktValue ?? node.value ?? node.marketVal;
        if (symbol && (qty != null || value != null)) {
          add({
            symbol,
            name: node.description || node.name || node.securityDescription || node.longName,
            quantity: parseMoney(qty) ?? Number(qty),
            lastPrice: parseMoney(last) ?? Number(last),
            marketValue: parseMoney(value) ?? Number(value),
            dayChangeValue: parseMoney(node.todayGainLoss ?? node.dayChange ?? node.change ?? node.todaysGainLossDollar) || 0,
            dayChangePercent: parseMoney(node.todayGainLossPercent ?? node.dayChangePercent ?? node.todaysGainLossPercent) || 0
          });
        }
        Object.values(node).forEach(walk);
      };

      document.querySelectorAll('script').forEach((script) => {
        const t = script.textContent || '';
        if (t.length < 40 || t.length > 4000000) return;
        const idx = t.indexOf('{');
        if (idx < 0) return;
        try { walk(JSON.parse(t.slice(idx))); } catch (e) {}
      });

      document.querySelectorAll('table tbody tr, [role="row"]').forEach((tr) => {
        const cells = [...tr.querySelectorAll('td, [role="gridcell"], [role="cell"]')]
          .map((c) => (c.innerText || '').trim())
          .filter(Boolean);
        if (cells.length < 3) return;
        const symbolCell = cells.find((c) => /^[A-Z]{1,6}([./-][A-Z0-9]+)?$/.test(c.split('\\n')[0].trim()));
        if (!symbolCell) return;
        const symbol = symbolCell.split('\\n')[0].trim();
        const nums = cells.map(parseMoney).filter((n) => n !== null);
        add({
          symbol,
          name: cells[1] || symbol,
          quantity: nums[0] || 0,
          lastPrice: nums[1] || 0,
          marketValue: nums[2] || 0,
          dayChangeValue: nums[3] || 0,
          dayChangePercent: nums[4] || 0
        });
      });

      document.querySelectorAll('[data-symbol], [data-ticker]').forEach((el) => {
        add({
          symbol: el.getAttribute('data-symbol') || el.getAttribute('data-ticker'),
          name: el.getAttribute('data-name') || (el.innerText || '').trim(),
          quantity: parseMoney(el.getAttribute('data-quantity') || '') || 0,
          lastPrice: parseMoney(el.getAttribute('data-price') || '') || 0,
          marketValue: parseMoney(el.getAttribute('data-value') || '') || 0,
          dayChangeValue: 0,
          dayChangePercent: 0
        });
      });

      let totalValue = 0;
      const bodyText = document.body ? document.body.innerText : '';
      const totalMatch = bodyText.match(/Total Account Value[^$]*\\$([0-9,]+(?:\\.[0-9]+)?)/i)
        || bodyText.match(/Account (?:total|value)[^$]*\\$([0-9,]+(?:\\.[0-9]+)?)/i);
      if (totalMatch) totalValue = parseMoney(totalMatch[0]) || 0;
      if (!totalValue) totalValue = positions.reduce((sum, p) => sum + (p.marketValue || 0), 0);

      return { signedIn, url: href, title: document.title, totalValue, positions };
    })()
    """
}

private struct FidelityScrapeResult: Decodable {
    var signedIn: Bool
    var url: String?
    var title: String?
    var totalValue: Double?
    var positions: [FidelityScrapePosition]
}

private struct FidelityScrapePosition: Decodable {
    var symbol: String
    var name: String?
    var quantity: Double?
    var lastPrice: Double?
    var marketValue: Double?
    var dayChangeValue: Double?
    var dayChangePercent: Double?
}

enum FidelityError: LocalizedError {
    case scrapeFailed

    var errorDescription: String? {
        "Fidelity positions page did not return any data. Try signing in again."
    }
}
