import Foundation

/// Answers every photo URL with a small teal image, so fixture chores show real photos without
/// touching the network. With `failing`, every download fails as if offline.
nonisolated struct FixturePhotoDownloader: PhotoDownloading {
    /// An 8x8 teal PNG.
    static let photo = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGMw2HAcK2IYWhIALG9pwTfG8uAAAAAASUVORK5CYII=")!

    var failing = false

    func data(from url: URL) async throws -> Data {
        if failing { throw DataServiceError.offline }
        return Self.photo
    }
}
