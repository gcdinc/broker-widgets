import Foundation

enum SnapshotStore {
    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID)
    }

    static var isAvailable: Bool {
        containerURL() != nil || UserDefaults(suiteName: AppConstants.appGroupID) != nil
    }

    static func fileURL(for broker: BrokerKind) -> URL? {
        containerURL()?.appendingPathComponent(broker.snapshotFilename)
    }

    static func load(_ broker: BrokerKind) -> PortfolioSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: raw) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(raw)")
        }
        if let url = fileURL(for: broker),
           let data = try? Data(contentsOf: url),
           let snapshot = try? decoder.decode(PortfolioSnapshot.self, from: data) {
            return snapshot
        }
        if let data = UserDefaults(suiteName: AppConstants.appGroupID)?.data(forKey: defaultsKey(broker)),
           let snapshot = try? decoder.decode(PortfolioSnapshot.self, from: data) {
            return snapshot
        }
        return nil
    }

    static func save(_ snapshot: PortfolioSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)

        var wrote = false
        if let dir = containerURL() {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent(snapshot.broker.snapshotFilename), options: .atomic)
            wrote = true
        }
        if let defaults = UserDefaults(suiteName: AppConstants.appGroupID) {
            defaults.set(data, forKey: defaultsKey(snapshot.broker))
            wrote = true
        }
        guard wrote else {
            throw SnapshotStoreError.noAppGroup
        }
    }

    private static func defaultsKey(_ broker: BrokerKind) -> String {
        "snapshot.\(broker.rawValue)"
    }
}

enum SnapshotStoreError: LocalizedError {
    case noAppGroup

    var errorDescription: String? {
        "App Group container is unavailable. In Xcode, enable App Groups for both targets (group.com.gcd.BrokerWidgets) and run the app again."
    }
}
