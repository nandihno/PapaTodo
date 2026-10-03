import Foundation
import SQLite3
import Synchronization
import Testing
@testable import PapaTodos

/// Each call returns a moment one second later, so "least recently viewed" is deterministic.
nonisolated final class TickingClock: Sendable {
    private let current = Mutex(Date(timeIntervalSince1970: 1_000_000))
    func tick() -> Date {
        current.withLock { $0 = $0.addingTimeInterval(1); return $0 }
    }
}

@MainActor
struct ChoreCacheTests {
    let userA = FixtureData.currentUserID
    let userB = FixtureData.otherUserID

    private func makeCache(
        fileURL: URL? = nil, entryLimit: Int = 10, photoByteLimit: Int = 1_000
    ) -> SQLiteChoreCache {
        let clock = TickingClock()
        return SQLiteChoreCache(
            fileURL: fileURL, entryLimit: entryLimit, photoByteLimit: photoByteLimit, now: { clock.tick() }
        )
    }

    private func entry(id: UUID = UUID(), title: String = "Chore", photos: [URL] = []) -> CachedChore {
        let created = Date(timeIntervalSince1970: 500_000)
        let attachments = photos.enumerated().map { index, url in
            ChoreAttachment(
                id: UUID(), choreId: id, storagePath: "chores/\(index).jpg", publicURL: url,
                fileName: nil, mimeType: "image/jpeg", sortOrder: index, createdBy: nil, createdAt: created
            )
        }
        let chore = Chore(
            id: id, title: title, description: "Line one\n\n- a bullet", assignedTo: userA, createdBy: userA,
            status: .pending, dueDate: created, imageURL: photos.first, createdAt: created, updatedAt: created,
            assignedProfile: ProfileSummary(id: userA, fullName: "Nando", avatarURL: nil),
            createdProfile: nil, attachments: attachments
        )
        let comment = ChoreComment(id: UUID(), choreId: id, authorId: userB, body: "On it", createdAt: created)
        return CachedChore(
            chore: chore, comments: [comment],
            people: [ProfileSummary(id: userB, fullName: "Alex", avatarURL: nil)], savedAt: created
        )
    }

    private func photoURL(_ name: String) -> URL {
        URL(string: "https://example.supabase.co/storage/v1/object/public/chore-images/\(name).jpg")!
    }

    // MARK: entries

    @Test func savedEntryReadsBackUnchanged() async {
        let cache = makeCache()
        let saved = entry(photos: [photoURL("a")])
        await cache.save(saved, userID: userA)
        #expect(await cache.entry(choreID: saved.chore.id, userID: userA) == saved)
    }

    @Test func savingAgainReplacesTheEntry() async {
        let cache = makeCache()
        var saved = entry(title: "Old")
        await cache.save(saved, userID: userA)
        saved.chore.title = "New"
        await cache.save(saved, userID: userA)
        #expect(await cache.entries(userID: userA).map(\.chore.title) == ["New"])
    }

    @Test func eleventhSaveDropsTheLeastRecentlyViewed() async {
        let cache = makeCache()
        let saved = (0..<10).map { entry(title: "Chore \($0)") }
        for item in saved { await cache.save(item, userID: userA) }
        // Chore 0 was saved first but viewed again, so chore 1 is now the least recently viewed.
        await cache.markViewed(choreID: saved[0].chore.id, userID: userA)
        await cache.save(entry(title: "Chore 10"), userID: userA)

        let titles = await cache.entries(userID: userA).map(\.chore.title)
        #expect(titles.count == 10)
        #expect(titles.first == "Chore 10")
        #expect(titles.contains("Chore 0"))
        #expect(!titles.contains("Chore 1"))
    }

    @Test func entriesAreMostRecentlyViewedFirst() async {
        let cache = makeCache()
        let first = entry(title: "First")
        let second = entry(title: "Second")
        await cache.save(first, userID: userA)
        await cache.save(second, userID: userA)
        await cache.markViewed(choreID: first.chore.id, userID: userA)
        #expect(await cache.entries(userID: userA).map(\.chore.title) == ["First", "Second"])
    }

    @Test func accountsNeverSeeEachOthersEntries() async {
        let cache = makeCache(entryLimit: 1)
        let mine = entry(title: "Mine")
        await cache.save(mine, userID: userA)
        await cache.save(entry(title: "Theirs"), userID: userB)

        #expect(await cache.entry(choreID: mine.chore.id, userID: userB) == nil)
        #expect(await cache.entries(userID: userA).map(\.chore.title) == ["Mine"])
        #expect(await cache.entries(userID: userB).map(\.chore.title) == ["Theirs"])
    }

    @Test func removeDeletesOneEntryAndItsPhotos() async {
        let cache = makeCache()
        let url = photoURL("a")
        let saved = entry(photos: [url])
        await cache.save(saved, userID: userA)
        await cache.savePhoto(Data(repeating: 1, count: 10), url: url, choreID: saved.chore.id, userID: userA)

        await cache.remove(choreID: saved.chore.id, userID: userA)
        #expect(await cache.entry(choreID: saved.chore.id, userID: userA) == nil)
        #expect(await cache.photo(url: url, userID: userA) == nil)
    }

    @Test func removeAllErasesEveryAccount() async {
        let cache = makeCache()
        await cache.save(entry(), userID: userA)
        await cache.save(entry(), userID: userB)
        await cache.removeAll()
        #expect(await cache.entries(userID: userA).isEmpty)
        #expect(await cache.entries(userID: userB).isEmpty)
    }

    // MARK: on disk

    @Test func entriesSurviveReopeningAndDamagedRowsAreDropped() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ChoreCacheTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let fileURL = folder.appending(path: "chores.sqlite")
        let good = entry(title: "Good")
        let damaged = entry(title: "Damaged")

        do {
            let cache = makeCache(fileURL: fileURL)
            await cache.save(good, userID: userA)
            await cache.save(damaged, userID: userA)
        }

        // Corrupt one row behind the cache's back, as an old or damaged file would be.
        var db: OpaquePointer?
        #expect(sqlite3_open(fileURL.path, &db) == SQLITE_OK)
        let sql = "UPDATE cached_chore SET payload = x'00' WHERE chore_id = '\(damaged.chore.id.uuidString)'"
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        let reopened = makeCache(fileURL: fileURL)
        #expect(await reopened.entries(userID: userA).map(\.chore.title) == ["Good"])
        #expect(await reopened.entry(choreID: damaged.chore.id, userID: userA) == nil)
        let excluded = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        #expect(excluded == true)
    }

    // MARK: photos

    @Test func photosAreStoredOnlyForSavedChoresAndTheirOwnURLs() async {
        let cache = makeCache()
        let url = photoURL("a")
        let saved = entry(photos: [url])
        let data = Data(repeating: 7, count: 20)

        await cache.savePhoto(data, url: url, choreID: UUID(), userID: userA)
        await cache.savePhoto(data, url: photoURL("stranger"), choreID: saved.chore.id, userID: userA)
        #expect(await cache.photo(url: url, userID: userA) == nil)

        await cache.save(saved, userID: userA)
        await cache.savePhoto(data, url: photoURL("stranger"), choreID: saved.chore.id, userID: userA)
        await cache.savePhoto(data, url: url, choreID: saved.chore.id, userID: userA)
        #expect(await cache.photo(url: url, userID: userA) == data)
        #expect(await cache.photo(url: url, userID: userB) == nil)
        #expect(await cache.storedPhotoURLs(choreID: saved.chore.id, userID: userA) == [url])
    }

    @Test func refreshingAChoreDropsPhotosItNoLongerHas() async {
        let cache = makeCache()
        let kept = photoURL("kept")
        let removed = photoURL("removed")
        let saved = entry(photos: [kept, removed])
        await cache.save(saved, userID: userA)
        await cache.savePhoto(Data(repeating: 1, count: 10), url: kept, choreID: saved.chore.id, userID: userA)
        await cache.savePhoto(Data(repeating: 2, count: 10), url: removed, choreID: saved.chore.id, userID: userA)

        var refreshed = saved
        refreshed.chore.attachments = saved.chore.attachments?.filter { $0.publicURL == kept }
        refreshed.chore.imageURL = kept
        await cache.save(refreshed, userID: userA)

        #expect(await cache.storedPhotoURLs(choreID: saved.chore.id, userID: userA) == [kept])
    }

    @Test func photoOverTheCapEvictsTheLeastRecentlyViewedOtherChores() async {
        let cache = makeCache(photoByteLimit: 100)
        let urls = (0..<3).map { photoURL("p\($0)") }
        let chores = urls.map { entry(photos: [$0]) }
        for (item, url) in zip(chores, urls) {
            await cache.save(item, userID: userA)
            await cache.savePhoto(Data(repeating: 1, count: 40), url: url, choreID: item.chore.id, userID: userA)
        }
        // 3 x 40 > 100, so saving the third photo evicted the first chore.
        #expect(await cache.entry(choreID: chores[0].chore.id, userID: userA) == nil)
        #expect(await cache.photo(url: urls[1], userID: userA) != nil)
        #expect(await cache.photo(url: urls[2], userID: userA) != nil)
    }

    @Test func photoThatCanNeverFitIsSkippedWithoutEvictingAnything() async {
        let cache = makeCache(photoByteLimit: 100)
        let small = photoURL("small")
        let huge = photoURL("huge")
        let other = entry(photos: [small])
        let big = entry(photos: [huge])
        await cache.save(other, userID: userA)
        await cache.savePhoto(Data(repeating: 1, count: 40), url: small, choreID: other.chore.id, userID: userA)
        await cache.save(big, userID: userA)

        await cache.savePhoto(Data(repeating: 1, count: 101), url: huge, choreID: big.chore.id, userID: userA)
        #expect(await cache.photo(url: huge, userID: userA) == nil)
        #expect(await cache.photo(url: small, userID: userA) != nil)
    }
}
