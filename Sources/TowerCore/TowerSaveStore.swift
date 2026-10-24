import Foundation

/// Recovery copies are separate files, so the rotating autosave cannot erase
/// a tower when the player opens another one or starts again.
public struct TowerSaveStore {
    public let recoveryDirectory: URL
    public init(recoveryDirectory: URL) { self.recoveryDirectory = recoveryDirectory }

    public func read(_ url: URL) throws -> TowerState {
        try JSONDecoder().decode(TowerState.self, from: Data(contentsOf: url)).validated()
    }
    public func write(_ game: TowerState, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(game)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    @discardableResult public func preserve(_ game: TowerState) throws -> URL {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = recoveryDirectory.appendingPathComponent("Tower-Day-\(game.day)-\(timestamp)-\(UUID().uuidString).loftyambitions")
        try write(game, to: url)
        return url
    }
    public func switching(from current: TowerState, to url: URL) throws -> (game: TowerState, recoveryURL: URL) {
        let loaded = try read(url)
        let recovery = try preserve(current)
        return (loaded, recovery)
    }
}
