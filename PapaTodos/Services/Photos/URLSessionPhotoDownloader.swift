import Foundation

/// Downloads chore photos from the public `chore-images` bucket.
nonisolated struct URLSessionPhotoDownloader: PhotoDownloading {
    var session: URLSession = .shared

    func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
            throw DataServiceError.server
        }
        return data
    }
}
