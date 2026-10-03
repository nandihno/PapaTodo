import Foundation
import Testing
@testable import PapaTodos

/// Counts downloads; can be slowed down or made to fail.
actor SpyPhotoDownloader: PhotoDownloading {
    private(set) var requests: [URL] = []
    var failing = false
    var delay: Duration = .zero

    func setFailing(_ value: Bool) { failing = value }
    func setDelay(_ value: Duration) { delay = value }

    func data(from url: URL) async throws -> Data {
        requests.append(url)
        if delay > .zero { try? await Task.sleep(for: delay) }
        if failing { throw DataServiceError.offline }
        return Data(url.absoluteString.utf8)
    }
}

@MainActor
struct ChorePhotoStoreTests {
    let me = FixtureData.currentUserID

    private func url(_ name: String) -> URL {
        URL(string: "https://example.supabase.co/storage/v1/object/public/chore-images/\(name).jpg")!
    }

    private func entry(photos: [URL], id: UUID = UUID()) -> CachedChore {
        let at = Date(timeIntervalSince1970: 0)
        let attachments = photos.enumerated().map { index, url in
            ChoreAttachment(id: UUID(), choreId: id, storagePath: "p\(index)", publicURL: url, fileName: nil,
                            mimeType: "image/jpeg", sortOrder: index, createdBy: nil, createdAt: at)
        }
        let chore = Chore(id: id, title: "Photos", description: nil, assignedTo: me, createdBy: me, status: .pending,
                          dueDate: nil, imageURL: photos.first, createdAt: at, updatedAt: at, attachments: attachments)
        return CachedChore(chore: chore, comments: [], people: [], savedAt: at)
    }

    @Test func aSavedPhotoIsServedWithoutDownloading() async {
        let cache = SQLiteChoreCache(fileURL: nil)
        let downloader = SpyPhotoDownloader()
        let store = ChorePhotoStore(cache: cache, downloader: downloader)
        let photo = url("a")
        let saved = entry(photos: [photo])
        await cache.save(saved, userID: me)
        await cache.savePhoto(Data("on the phone".utf8), url: photo, choreID: saved.chore.id, userID: me)

        #expect(await store.data(for: photo, choreID: saved.chore.id, userID: me) == Data("on the phone".utf8))
        #expect(await downloader.requests.isEmpty)
    }

    @Test func aDownloadedPhotoIsKeptOnlyWhenItsChoreIsSaved() async {
        let cache = SQLiteChoreCache(fileURL: nil)
        let store = ChorePhotoStore(cache: cache, downloader: SpyPhotoDownloader())
        let photo = url("a")
        let saved = entry(photos: [photo])

        _ = await store.data(for: photo, choreID: saved.chore.id, userID: me)
        #expect(await cache.photo(url: photo, userID: me) == nil)

        await cache.save(saved, userID: me)
        _ = await store.data(for: photo, choreID: saved.chore.id, userID: me)
        #expect(await cache.photo(url: photo, userID: me) == Data(photo.absoluteString.utf8))
    }

    @Test func simultaneousRequestsShareOneDownload() async {
        let downloader = SpyPhotoDownloader()
        await downloader.setDelay(.milliseconds(50))
        let store = ChorePhotoStore(cache: SQLiteChoreCache(fileURL: nil), downloader: downloader)
        let photo = url("a")
        let chore = UUID()

        async let first = store.data(for: photo, choreID: chore, userID: me)
        async let second = store.data(for: photo, choreID: chore, userID: me)
        let (a, b) = await (first, second)
        #expect(a != nil && a == b)
        #expect(await downloader.requests.count == 1)
    }

    @Test func aFailedDownloadGivesNothing() async {
        let downloader = SpyPhotoDownloader()
        await downloader.setFailing(true)
        let store = ChorePhotoStore(cache: SQLiteChoreCache(fileURL: nil), downloader: downloader)
        #expect(await store.data(for: url("a"), choreID: UUID(), userID: me) == nil)
    }

    @Test func prefetchDownloadsOnlyTheMissingPhotos() async {
        let cache = SQLiteChoreCache(fileURL: nil)
        let downloader = SpyPhotoDownloader()
        let store = ChorePhotoStore(cache: cache, downloader: downloader)
        let have = url("have")
        let missing = url("missing")
        let saved = entry(photos: [have, missing])
        await cache.save(saved, userID: me)
        await cache.savePhoto(Data("x".utf8), url: have, choreID: saved.chore.id, userID: me)

        await store.prefetch(saved, userID: me)
        #expect(await downloader.requests == [missing])
        #expect(await cache.storedPhotoURLs(choreID: saved.chore.id, userID: me) == [have, missing])
    }

    // MARK: detail screen

    @Test func openingAChoreKeepsItsPhotosForOffline() async {
        let cache = SQLiteChoreCache(fileURL: nil)
        let photos = [url("one"), url("two")]
        let chore = entry(photos: photos).chore
        let model = ChoreDetailModel(
            choreID: chore.id, choreRepository: FixtureChoreRepository(chores: [chore]),
            commentRepository: FixtureCommentRepository(comments: []), profileRepository: FixtureProfileRepository(),
            cache: cache, photos: ChorePhotoStore(cache: cache, downloader: SpyPhotoDownloader()), userID: me
        )
        await model.load()

        let deadline = ContinuousClock.now + .seconds(3)
        while await cache.storedPhotoURLs(choreID: chore.id, userID: me).count < 2, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(await cache.storedPhotoURLs(choreID: chore.id, userID: me) == Set(photos))
    }

    @Test func offlineTheScreenShowsTheSavedPhotos() async {
        let cache = SQLiteChoreCache(fileURL: nil)
        let photo = url("one")
        let saved = entry(photos: [photo])
        await cache.save(saved, userID: me)
        await cache.savePhoto(Data("saved photo".utf8), url: photo, choreID: saved.chore.id, userID: me)
        let downloader = SpyPhotoDownloader()
        await downloader.setFailing(true)
        let faults = FaultInjector()
        await faults.arm(.fetchChore, error: .offline)

        let model = ChoreDetailModel(
            choreID: saved.chore.id, choreRepository: FixtureChoreRepository(chores: [], faults: faults),
            commentRepository: FixtureCommentRepository(comments: []), profileRepository: FixtureProfileRepository(),
            cache: cache, photos: ChorePhotoStore(cache: cache, downloader: downloader), userID: me
        )
        await model.load()
        #expect(model.isReadOnly)
        #expect(await model.photoData(for: photo) == Data("saved photo".utf8))
        #expect(await model.photoData(for: url("never saved")) == nil)
    }
}
