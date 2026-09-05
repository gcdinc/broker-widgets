import Combine
import Foundation
import WidgetKit

@MainActor
final class AppState: ObservableObject {
    @Published var publicSnapshot: PortfolioSnapshot
    @Published var fidelitySnapshot: PortfolioSnapshot
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var publicSecretDraft = ""
    @Published var hasPublicSecret = false
    @Published var fidelitySignedIn = false
    @Published var refreshInterval: TimeInterval
    @Published var showDesktopPanels: Bool
    @Published var panelFontScale: Double
    @Published var launchAtLogin: Bool

    private var timer: Timer?
    private var didStart = false

    init() {
        publicSnapshot = SnapshotStore.load(.publicBroker) ?? .setup(.publicBroker)
        fidelitySnapshot = SnapshotStore.load(.fidelity) ?? .setup(.fidelity)
        hasPublicSecret = KeychainStore.get(.publicSecret) != nil
        fidelitySignedIn = FidelityEngine.shared.isLikelySignedIn
        refreshInterval = RefreshSettings.seconds
        showDesktopPanels = UserDefaults.standard.object(forKey: "showDesktopPanels") as? Bool ?? true
        panelFontScale = DisplaySettings.fontScale
        LaunchAtLogin.enableOnFirstLaunchIfNeeded()
        launchAtLogin = LaunchAtLogin.isEnabled
        if let loaded = SnapshotStore.load(.fidelity) {
            let cleaned = cleanedFidelity(loaded)
            fidelitySnapshot = cleaned
            if cleaned.totalValue != loaded.totalValue || cleaned.positions.count != loaded.positions.count {
                try? SnapshotStore.save(cleaned)
            }
        }
    }

    var menuBarShowsWarning: Bool {
        fidelitySnapshot.status == .needsSignIn || publicSnapshot.status == .needsSecret || lastError != nil
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        rescheduleTimer()
        Task { await refreshAll() }
    }

    func setRefreshInterval(_ seconds: TimeInterval) {
        refreshInterval = seconds
        RefreshSettings.seconds = seconds
        rescheduleTimer()
        reloadWidgets()
    }

    func setShowDesktopPanels(_ show: Bool) {
        showDesktopPanels = show
        UserDefaults.standard.set(show, forKey: "showDesktopPanels")
    }

    func setPanelFontScale(_ scale: Double) {
        panelFontScale = scale
        DisplaySettings.fontScale = scale
        reloadWidgets()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LaunchAtLogin.setEnabled(enabled)
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    private func cleanedFidelity(_ snapshot: PortfolioSnapshot) -> PortfolioSnapshot {
        guard snapshot.status == .ok else { return snapshot }
        let merged = FidelityCaptureParser.mergeDuplicates(snapshot.positions)
            .sorted { $0.resolvedMarketValue > $1.resolvedMarketValue }
        let total = merged.reduce(0) { $0 + $1.resolvedMarketValue }
        let day = merged.reduce(0) { $0 + $1.dayChangeValue }
        let prior = total - day
        var copy = snapshot
        copy.positions = merged
        copy.totalValue = snapshot.totalValue > total ? snapshot.totalValue : total
        if day != 0 {
            copy.dayChangeValue = day
            copy.dayChangePercent = prior == 0 ? 0 : (day / prior) * 100
        }
        if merged.isEmpty, !snapshot.positions.isEmpty {
            copy.status = .empty
            copy.message = "Ignored invalid Fidelity rows (account IDs were parsed as holdings). Refresh Fidelity."
        }
        return copy
    }

    func savePublicSecret() throws {
        let secret = publicSecretDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !secret.isEmpty else { return }
        try KeychainStore.set(secret, for: .publicSecret)
        KeychainStore.delete(.publicToken)
        publicSecretDraft = ""
        hasPublicSecret = true
    }

    func savePublicSecretAndRefresh() async {
        do {
            try savePublicSecret()
            await refreshPublic()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearPublicSecret() {
        KeychainStore.delete(.publicSecret)
        KeychainStore.delete(.publicToken)
        hasPublicSecret = false
        publicSnapshot = .setup(.publicBroker)
        try? SnapshotStore.save(publicSnapshot)
        reloadWidgets()
    }

    func saveFidelitySession() async {
        do {
            try await FidelityEngine.shared.persistCookies()
            fidelitySignedIn = true
            await refreshFidelity()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOutFidelity() async {
        await FidelityEngine.shared.signOut()
        fidelitySignedIn = false
        fidelitySnapshot = .setup(.fidelity)
        try? SnapshotStore.save(fidelitySnapshot)
        reloadWidgets()
    }

    func refreshAll() async {
        isRefreshing = true
        lastError = nil
        await refreshPublic()
        await refreshFidelity()
        isRefreshing = false
        reloadWidgets()
    }

    func refreshPublic() async {
        guard let secret = KeychainStore.get(.publicSecret), !secret.isEmpty else {
            publicSnapshot = .setup(.publicBroker)
            try? SnapshotStore.save(publicSnapshot)
            hasPublicSecret = false
            reloadWidgets()
            return
        }
        hasPublicSecret = true
        do {
            let snapshot = try await PublicClient.fetchSnapshot(secret: secret)
            publicSnapshot = snapshot
            try SnapshotStore.save(snapshot)
        } catch {
            publicSnapshot.message = error.localizedDescription
            publicSnapshot.status = .error
            publicSnapshot.updatedAt = Date()
            lastError = error.localizedDescription
            try? SnapshotStore.save(publicSnapshot)
        }
        reloadWidgets()
    }

    func refreshFidelity() async {
        do {
            let snapshot = cleanedFidelity(try await FidelityEngine.shared.fetchPositions())
            fidelitySnapshot = snapshot
            fidelitySignedIn = snapshot.status != .needsSignIn
            try SnapshotStore.save(snapshot)
        } catch {
            fidelitySnapshot.status = .error
            fidelitySnapshot.message = error.localizedDescription
            fidelitySnapshot.updatedAt = Date()
            lastError = error.localizedDescription
            try? SnapshotStore.save(fidelitySnapshot)
        }
        reloadWidgets()
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        let interval = max(refreshInterval, 60)
        let scheduled = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAll()
            }
        }
        scheduled.tolerance = min(60, interval / 10)
        RunLoop.main.add(scheduled, forMode: .common)
        timer = scheduled
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: "FidelityPositionsWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "PublicPositionsWidget")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
