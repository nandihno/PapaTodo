import Foundation

/// Fetches the bytes of a chore photo from its public URL.
nonisolated protocol PhotoDownloading: Sendable {
    func data(from url: URL) async throws -> Data
}
