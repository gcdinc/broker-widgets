# Broker Widgets

Two native macOS desktop widgets: **Fidelity positions** and **Public.com positions**. A menu-bar companion app refreshes holdings and writes a snapshot the widgets read.

macOS 14+ (Sonoma).

## Run without Xcode

After you have built **Broker Widgets** once from Xcode (Signing → Personal Team):

1. Quit the Xcode-launched copy.
2. Open `BrokerWidgets.app` from Xcode’s Products folder, or copy it to `/Applications` and launch that.
3. The menu bar icon is the app. Settings → **Open Broker Widgets at login** is on by default.

A `.dmg` is optional. The `.app` is enough: drag it to Applications, open it, keep it in Login Items.

## Secrets stay off git

- Never put API keys, tokens, cookies, or session files in this repo.
- The Public.com secret is pasted in the app and stored in **Keychain**.
- Fidelity login happens in an in-app WebView. Session cookies stay in Keychain / the app’s WebKit data store. No Fidelity password is saved by this app.
- `Secrets.xcconfig`, `.env`, `*cookie*`, and `*storage_state*` are gitignored.

## Setup

1. Open `BrokerWidgets.xcodeproj` in Xcode (or run `xcodegen generate` if you change `project.yml`).
2. Select the **BrokerWidgets** target → Signing & Capabilities → pick your Personal Team.
3. Repeat for **BrokerWidgetsWidgets**.
4. Run **BrokerWidgets** on My Mac. Keep it running so widgets stay fresh.
5. Right-click the desktop (or Notification Center) → Edit Widgets → add **Fidelity Positions** and **Public Positions**.

## Public.com

1. In Public, open Settings and generate an Individual API secret.
2. In Broker Widgets → Settings, paste the secret. It is stored in Keychain only.
3. Refresh. The widget lists combined positions across your Public accounts.

[Public API quickstart](https://public.com/api/docs/quickstart)

## Fidelity

Fidelity has no official retail positions API. This app is read-only:

1. Settings → Sign in to Fidelity.
2. Log in normally (including 2FA) on Fidelity’s page.
3. When you land on Portfolio / Positions, click **Save session**.
4. The app reuses that session to scrape positions. If Fidelity expires it, the widget asks you to sign in again.

This can break when Fidelity changes their site.

## Refresh

The menu-bar app reloads both brokers on a schedule (default **1 hour**; change it in Settings) and asks WidgetKit to reload. Widgets themselves cannot keep a Fidelity web session.

## Build from `project.yml`

```bash
brew install xcodegen
xcodegen generate
open BrokerWidgets.xcodeproj
```
