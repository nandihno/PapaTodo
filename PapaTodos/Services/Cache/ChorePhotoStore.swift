import Foundation

/// Where the detail screen gets chore photos (docs/phase-8-offline-plan.md): the phone's saved
/// copy when there is one, otherwise a download, which is kept if the chore is saved.
///
/// Every upload gets its own storage path, so a saved photo is never out of date and is used
/// even when online. Concurrent requests for the same photo share one download.
actor ChorePhotoStore {
    private let cache: any ChoreCache
    private let downloader: any PhotoDownloading
    private var inFlight: [URL: Task<Data?, Never>] = [:]

    init(cache: any ChoreCache, downloader: any PhotoDownloading) {
        self.cache = cache
        self.downloader = downloader
    }

    /// - Parameter userID: the signed-in account; nil skips the phone's copies entirely.
    func data(for url: URL, choreID: UUID, userID: UUID?) async -> Data? {
        if let userID, let saved = await cache.photo(url: url, userID: userID) { return saved }
        if let running = inFlight[url] { return await running.value }
        let downloader = downloader
        let download = Task { try? await downloader.data(from: url) }
        inFlight[url] = download
        let data = await download.value
        inFlight[url] = nil
        if let data, let userID {
            // Ignored by the cache unless the chore is saved and still has this photo.
            await cache.savePhoto(data, url: url, choreID: choreID, userID: userID)
        }
        return data
    }

    /// Downloads the saved chore's photos that aren't on the phone yet, one at a time.
    func prefetch(_ entry: CachedChore, userID: UUID) async {
        let stored = await cache.storedPhotoURLs(choreID: entry.chore.id, userID: userID)
        let missing = entry.photoURLs.subtracting(stored).sorted { $0.absoluteString < $1.absoluteString }
        for url in missing {
            _ = await data(for: url, choreID: entry.chore.id, userID: userID)
        }
    }
}
