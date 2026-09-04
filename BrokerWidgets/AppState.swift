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

    private var timer: Timer?
    private var didStart = false

    init() {
        publicSnapshot = SnapshotStore.load(.publicBroker) ?? .setup(.publicBroker)
        fidelitySnapshot = SnapshotStore.load(.fidelity) ?? .setup(.fidelity)
        hasPublicSecret = KeychainStore.get(.publicSecret) != nil
        fidelitySignedIn = FidelityEngine.shared.isLikelySignedIn
    }

    var menuBarSymbol: String {
        if fidelitySnapshot.status == .needsSignIn || publicSnapshot.status == .needsSecret || lastError != nil {
            return "exclamationmark.triangle.fill"
        }
        return "chart.line.uptrend.xyaxis"
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: AppConstants.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAll()
            }
        }
        Task { await refreshAll() }
    }

    func savePublicSecret() throws {
        let secret = publicSecretDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { return }
        try KeychainStore.set(secret, for: .publicSecret)
        KeychainStore.delete(.publicToken)
        publicSecretDraft = ""
        hasPublicSecret = true
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
            try? SnapshotStore.save(publicSnapshot)
            lastError = error.localizedDescription
        }
    }

    func refreshFidelity() async {
        do {
            let snapshot = try await FidelityEngine.shared.fetchPositions()
            fidelitySnapshot = snapshot
            fidelitySignedIn = snapshot.status != .needsSignIn
            try SnapshotStore.save(snapshot)
        } catch {
            fidelitySnapshot.status = .error
            fidelitySnapshot.message = error.localizedDescription
            fidelitySnapshot.updatedAt = Date()
            try? SnapshotStore.save(fidelitySnapshot)
            lastError = error.localizedDescription
        }
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
