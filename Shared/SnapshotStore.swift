import Foundation

enum SnapshotStore {
    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID)
    }

    static func fileURL(for broker: BrokerKind) -> URL? {
        containerURL()?.appendingPathComponent(broker.snapshotFilename)
    }

    static func load(_ broker: BrokerKind) -> PortfolioSnapshot? {
        guard let url = fileURL(for: broker),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PortfolioSnapshot.self, from: data)
    }

    static func save(_ snapshot: PortfolioSnapshot) throws {
        guard let dir = containerURL() else {
            throw SnapshotStoreError.noAppGroup
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let url = dir.appendingPathComponent(snapshot.broker.snapshotFilename)
        try data.write(to: url, options: .atomic)
    }
}

enum SnapshotStoreError: LocalizedError {
    case noAppGroup

    var errorDescription: String? {
        "App Group container is unavailable. Check signing and group.com.gcd.BrokerWidgets."
    }
}
