import Foundation
import WebKit

enum FidelityWeb {
    static let positionsURL = URL(string: "https://digital.fidelity.com/ftgw/digital/portfolio/positions")!
    private static let storeDefaultsKey = "fidelity.webkit.store.uuid"

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
        let script = WKUserScript(source: interceptJavaScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        return config
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
      if (s.length < 2 || s.length > 10) return false;
      if (!/^[A-Z][A-Z0-9./-]{1,9}$/.test(s)) return false;
      if (/^Z\\d{6,}$/.test(s) || /^\\d{7,}$/.test(s)) return false;
      if (/^(HOLDING|INDIVIDU|INDIVIDUAL|BROKERAGE|ACCOUNT|ROTH|TOD|CASH|TOTAL|VALUE|SYMBOL|QTY|HIGH|LOW|OPEN|CLOSE|APPLY|DISMISS|TIMEFRAME|DOWNLOAD|OVERVIEW|SETTINGS|POSITIONS|BALANCES|SECURITY|RETIREMENT|ACCOUNTS|MENU|RETRY|SUMMARY|SAVE|LABEL|CONSENT|EDUCATION|PLANNING|TRANSACT|OTHER|CANCEL|LOADING|TRANSFER|PRIVACY|MESSAGES|TRADE|DOCUMENTS|INVESTMENT|ANALYSIS|QUOTE|YIELD|PAGE|PRINT|REVIEW|VIEW|ERROR|EX-DATE|SAVECANCEL)$/.test(s)) return false;
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
    var seen = {};
    function addRow(sym, qty, last, mkt, name, day, dayPct) {
      if (!isTicker(sym) || !(qty > 0 || mkt > 0)) return;
      if (last >= 1900 && last <= 2100 && last === Math.floor(last)) return;
      if (last > 25000) return;
      if (qty > 0 && last > 0 && mkt > 0) {
        var implied = mkt / qty;
        if (implied / last < 0.45 || implied / last > 2.2) return;
      }
      var key = String(sym).trim().toUpperCase() + '|' + (qty || 0);
      if (seen[key]) return;
      seen[key] = true;
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
      var m = t.match(/^([A-Z][A-Z0-9./-]{1,9})\\b/);
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
    function pierce(root, visit) {
      if (!root) return;
      visit(root);
      var els = root.querySelectorAll ? root.querySelectorAll('*') : [];
      for (var i = 0; i < els.length; i++) {
        visit(els[i]);
        if (els[i].shadowRoot) pierce(els[i].shadowRoot, visit);
      }
    }
    pierce(document, function(el) {
      if (!el.getAttribute) return;
      var hinted = el.getAttribute('data-symbol') || el.getAttribute('data-ticker');
      if (hinted) {
        var row = el.closest ? (el.closest('tr, [role="row"], [class*="row"]') || el.parentElement) : el.parentElement;
        parseRow(hinted, row && row.innerText ? row.innerText : el.innerText || '');
      }
      var href = el.getAttribute('href') || '';
      var hm = href.match(/[?&](symbol|ticker)=([A-Za-z0-9./-]+)/i);
      if (hm) {
        var row2 = el.closest ? (el.closest('tr, [role="row"], [class*="row"]') || el.parentElement) : el.parentElement;
        parseRow(hm[2], row2 && row2.innerText ? row2.innerText : el.innerText || '');
      }
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
        '/ftgw/digital/portfolio/api/GetPositions',
        '/ftgw/digital/portfolio/api/positions',
        '/ftgw/digital/portfolio/api/GetAccountPositions'
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
        try {
          var get = await fetch(restURLs[i], { credentials: 'include', headers: { accept: 'application/json' } });
          keep(restURLs[i] + '?get', await get.text());
        } catch (e) {}
      }
    } catch (e) {}
    return { rows: rows.length, captured: (window.__brokerCaptured || []).length };
    """

    static let readJavaScript = """
    JSON.stringify({
      href: location.href || '',
      title: document.title || '',
      hasPassword: Boolean(document.querySelector('input[type="password"]')),
      captured: (window.__brokerCaptured || []).map(function(c) { return { url: c.url, text: c.text }; }),
      text: (document.body && document.body.innerText) ? document.body.innerText.slice(0, 100000) : ''
    })
    """
}
