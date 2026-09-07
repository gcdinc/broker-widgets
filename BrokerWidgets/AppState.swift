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
    @Published var showFidelityPanel: Bool
    @Published var showPublicPanel: Bool
    @Published var panelFontScale: Double
    @Published var launchAtLogin: Bool
    @Published var updateStatus: AppUpdateStatus = .idle
    @Published var isUpdating = false

    private var timer: Timer?
    private var updateTimer: Timer?
    private var didStart = false

    init() {
        publicSnapshot = SnapshotStore.load(.publicBroker) ?? .setup(.publicBroker)
        let loadedFidelity = SnapshotStore.load(.fidelity) ?? .setup(.fidelity)
        let cleaned = Self.cleanedFidelity(loadedFidelity)
        fidelitySnapshot = cleaned
        refreshInterval = RefreshSettings.seconds
        let both = UserDefaults.standard.object(forKey: "showDesktopPanels") as? Bool ?? true
        showFidelityPanel = UserDefaults.standard.object(forKey: "showFidelityPanel") as? Bool ?? both
        showPublicPanel = UserDefaults.standard.object(forKey: "showPublicPanel") as? Bool ?? both
        panelFontScale = DisplaySettings.fontScale
        LaunchAtLogin.enableOnFirstLaunchIfNeeded()
        launchAtLogin = LaunchAtLogin.isEnabled
        hasPublicSecret = KeychainStore.get(.publicSecret) != nil
        fidelitySignedIn = FidelityEngine.shared.isLikelySignedIn
        if cleaned.totalValue != loadedFidelity.totalValue || cleaned.positions.count != loadedFidelity.positions.count {
            try? SnapshotStore.save(cleaned)
        }
    }

    var menuBarShowsWarning: Bool {
        fidelitySnapshot.status == .needsSignIn
            || publicSnapshot.status == .needsSecret
            || lastError != nil
            || updateStatus.isAvailable
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        rescheduleTimer()
        scheduleUpdateChecks()
        Task { await refreshAll() }
        Task { await checkForAppUpdate() }
    }

    var lastHoldingsUpdate: Date? {
        let snapshots = [publicSnapshot, fidelitySnapshot]
        let dates = snapshots.compactMap { snapshot -> Date? in
            switch snapshot.status {
            case .ok, .error, .empty:
                return snapshot.updatedAt
            case .needsSignIn, .needsSecret:
                return nil
            }
        }
        return dates.max()
    }

    func setRefreshInterval(_ seconds: TimeInterval) {
        refreshInterval = seconds
        RefreshSettings.seconds = seconds
        rescheduleTimer()
        reloadWidgets()
    }

    func resetRefreshInterval() {
        setRefreshInterval(RefreshSettings.defaultSeconds)
    }

    func setPanelVisible(_ windowID: String, _ show: Bool) {
        switch windowID {
        case "fidelity-desktop":
            showFidelityPanel = show
            UserDefaults.standard.set(show, forKey: "showFidelityPanel")
        case "public-desktop":
            showPublicPanel = show
            UserDefaults.standard.set(show, forKey: "showPublicPanel")
        default:
            break
        }
        UserDefaults.standard.set(showFidelityPanel || showPublicPanel, forKey: "showDesktopPanels")
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

    func checkForAppUpdate() async {
        guard !isUpdating else { return }
        isUpdating = true
        updateStatus = .checking
        do {
            updateStatus = try await AppUpdate.check()
        } catch {
            updateStatus = .failed(error.localizedDescription)
        }
        isUpdating = false
    }

    private static func cleanedFidelity(_ snapshot: PortfolioSnapshot) -> PortfolioSnapshot {
        guard snapshot.status == .ok else { return snapshot }
        let merged = FidelityHoldingRules.mergeDuplicates(snapshot.positions)
            .sorted { $0.resolvedMarketValue > $1.resolvedMarketValue }
        let total = merged.reduce(0) { $0 + $1.resolvedMarketValue }
        let day = merged.reduce(0) { $0 + $1.dayChangeValue }
        var copy = snapshot
        copy.positions = merged
        copy.totalValue = snapshot.totalValue > total ? snapshot.totalValue : total
        if day != 0 {
            copy.dayChangeValue = day
            copy.dayChangePercent = Position.dayPercent(change: day, value: total)
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

    func clearAllSecrets() async {
        publicSecretDraft = ""
        lastError = nil
        clearPublicSecret()
        await signOutFidelity()
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
            let snapshot = Self.cleanedFidelity(try await FidelityEngine.shared.fetchPositions())
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

    private func scheduleUpdateChecks() {
        updateTimer?.invalidate()
        let scheduled = Timer(timeInterval: 12 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.checkForAppUpdate()
            }
        }
        RunLoop.main.add(scheduled, forMode: .common)
        updateTimer = scheduled
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
        WidgetCenter.shared.reloadAllTimelines()
    }
}
