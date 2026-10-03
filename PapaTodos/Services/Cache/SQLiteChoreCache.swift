import Foundation
import SQLite3

/// `ChoreCache` backed by SQLite (docs/phase-8-offline-plan.md).
///
/// Each entry is stored as the JSON of a `CachedChore`, so new `Chore` fields never need a
/// schema change. Photos live in their own table and are deleted with their chore. Tests and
/// fixtures use an in-memory database, so they exercise the same SQL as the app.
///
/// iOS already gives app files "readable after first unlock" protection by default; the folder
/// is also excluded from iCloud backups, and `secure_delete` overwrites erased rows on disk.
actor SQLiteChoreCache: ChoreCache {
    static let defaultEntryLimit = 10
    /// Photos are at most 2048 px (ImageProcessing), so roughly 0.5-1.5 MB each.
    static let defaultPhotoByteLimit = 150 * 1024 * 1024

    private var db: OpaquePointer?
    private let entryLimit: Int
    private let photoByteLimit: Int
    private let now: @Sendable () -> Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// - Parameter fileURL: where the database lives; nil keeps it in memory (tests, fixtures).
    init(
        fileURL: URL?,
        entryLimit: Int = SQLiteChoreCache.defaultEntryLimit,
        photoByteLimit: Int = SQLiteChoreCache.defaultPhotoByteLimit,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.entryLimit = entryLimit
        self.photoByteLimit = photoByteLimit
        self.now = now
        self.db = Self.open(fileURL)
    }

    isolated deinit {
        sqlite3_close(db)
    }

    /// `Application Support/OfflineCache/chores.sqlite`.
    nonisolated static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "OfflineCache", directoryHint: .isDirectory)
            .appending(path: "chores.sqlite")
    }

    // MARK: ChoreCache

    func save(_ entry: CachedChore, userID: UUID) async {
        guard let payload = try? encoder.encode(entry) else { return }
        let user = userID.uuidString
        let chore = entry.chore.id.uuidString
        let keep = entry.photoURLs
        transaction {
            guard run("""
                INSERT INTO cached_chore (user_id, chore_id, payload, saved_at, last_viewed_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (user_id, chore_id) DO UPDATE SET
                    payload = excluded.payload,
                    saved_at = excluded.saved_at,
                    last_viewed_at = excluded.last_viewed_at
                """, [.text(user), .text(chore), .blob(payload),
                      .real(entry.savedAt.timeIntervalSince1970), .real(now().timeIntervalSince1970)])
            else { return false }
            for url in storedPhotos(user: user, chore: chore) where !keep.contains(url) {
                guard run("DELETE FROM cached_photo WHERE user_id = ? AND chore_id = ? AND url = ?",
                          [.text(user), .text(chore), .text(url.absoluteString)])
                else { return false }
            }
            return run("""
                DELETE FROM cached_chore WHERE user_id = ? AND chore_id NOT IN (
                    SELECT chore_id FROM cached_chore WHERE user_id = ?
                    ORDER BY last_viewed_at DESC LIMIT ?
                )
                """, [.text(user), .text(user), .int(Int64(entryLimit))])
        }
    }

    func entry(choreID: UUID, userID: UUID) async -> CachedChore? {
        storedEntry(user: userID.uuidString, chore: choreID.uuidString)
    }

    func entries(userID: UUID) async -> [CachedChore] {
        let user = userID.uuidString
        var found: [CachedChore] = []
        var unreadable: [String] = []
        run("SELECT chore_id, payload FROM cached_chore WHERE user_id = ? ORDER BY last_viewed_at DESC",
            [.text(user)]) { statement in
            if let entry = decode(Self.blob(statement, 1)) {
                found.append(entry)
            } else {
                unreadable.append(Self.text(statement, 0))
            }
        }
        for chore in unreadable { delete(user: user, chore: chore) }
        return found
    }

    func markViewed(choreID: UUID, userID: UUID) async {
        run("UPDATE cached_chore SET last_viewed_at = ? WHERE user_id = ? AND chore_id = ?",
            [.real(now().timeIntervalSince1970), .text(userID.uuidString), .text(choreID.uuidString)])
    }

    func remove(choreID: UUID, userID: UUID) async {
        delete(user: userID.uuidString, chore: choreID.uuidString)
    }

    func removeAll() async {
        transaction {
            run("DELETE FROM cached_photo") && run("DELETE FROM cached_chore")
        }
    }

    func savePhoto(_ data: Data, url: URL, choreID: UUID, userID: UUID) async {
        let user = userID.uuidString
        let chore = choreID.uuidString
        guard !data.isEmpty,
              let entry = storedEntry(user: user, chore: chore),
              entry.photoURLs.contains(url)
        else { return }
        // Give up without evicting anything if this chore alone can't fit under the cap.
        let ownOtherBytes = photoBytes(user: user, chore: chore, excluding: url)
        guard ownOtherBytes + data.count <= photoByteLimit else { return }
        transaction {
            while photoBytes(user: user, excluding: url) + data.count > photoByteLimit {
                guard let victim = leastRecentlyViewed(user: user, excluding: chore),
                      run("DELETE FROM cached_chore WHERE user_id = ? AND chore_id = ?", [.text(user), .text(victim)])
                else { return false }
            }
            return run("""
                INSERT INTO cached_photo (user_id, chore_id, url, data) VALUES (?, ?, ?, ?)
                ON CONFLICT (user_id, chore_id, url) DO UPDATE SET data = excluded.data
                """, [.text(user), .text(chore), .text(url.absoluteString), .blob(data)])
        }
    }

    func photo(url: URL, userID: UUID) async -> Data? {
        var data: Data?
        run("SELECT data FROM cached_photo WHERE user_id = ? AND url = ? LIMIT 1",
            [.text(userID.uuidString), .text(url.absoluteString)]) { data = Self.blob($0, 0) }
        return data
    }

    func storedPhotoURLs(choreID: UUID, userID: UUID) async -> Set<URL> {
        storedPhotos(user: userID.uuidString, chore: choreID.uuidString)
    }

    // MARK: queries

    private func storedEntry(user: String, chore: String) -> CachedChore? {
        var payload: Data?
        run("SELECT payload FROM cached_chore WHERE user_id = ? AND chore_id = ?",
            [.text(user), .text(chore)]) { payload = Self.blob($0, 0) }
        guard let payload else { return nil }
        guard let entry = decode(payload) else {
            // Written by an older app version, or damaged: drop it rather than fail every read.
            delete(user: user, chore: chore)
            return nil
        }
        return entry
    }

    private func storedPhotos(user: String, chore: String) -> Set<URL> {
        var urls = Set<URL>()
        run("SELECT url FROM cached_photo WHERE user_id = ? AND chore_id = ?",
            [.text(user), .text(chore)]) { statement in
            if let url = URL(string: Self.text(statement, 0)) { urls.insert(url) }
        }
        return urls
    }

    private func photoBytes(user: String, chore: String? = nil, excluding url: URL) -> Int {
        var bytes = 0
        let sql = "SELECT COALESCE(SUM(LENGTH(data)), 0) FROM cached_photo WHERE user_id = ? AND url != ?"
            + (chore == nil ? "" : " AND chore_id = ?")
        var bindings: [Binding] = [.text(user), .text(url.absoluteString)]
        if let chore { bindings.append(.text(chore)) }
        run(sql, bindings) { bytes = Int(sqlite3_column_int64($0, 0)) }
        return bytes
    }

    private func leastRecentlyViewed(user: String, excluding chore: String) -> String? {
        var found: String?
        run("""
            SELECT chore_id FROM cached_chore WHERE user_id = ? AND chore_id != ?
            ORDER BY last_viewed_at ASC LIMIT 1
            """, [.text(user), .text(chore)]) { found = Self.text($0, 0) }
        return found
    }

    private func delete(user: String, chore: String) {
        run("DELETE FROM cached_chore WHERE user_id = ? AND chore_id = ?", [.text(user), .text(chore)])
    }

    private func decode(_ payload: Data) -> CachedChore? {
        try? decoder.decode(CachedChore.self, from: payload)
    }

    // MARK: SQLite plumbing

    nonisolated enum Binding {
        case text(String)
        case blob(Data)
        case real(Double)
        case int(Int64)
    }

    /// Runs `body` in a transaction, rolling back if it returns false.
    private func transaction(_ body: () -> Bool) {
        guard run("BEGIN IMMEDIATE") else { return }
        run(body() ? "COMMIT" : "ROLLBACK")
    }

    /// Runs one statement, calling `row` for each result row. Returns false on any error.
    @discardableResult
    private func run(_ sql: String, _ bindings: [Binding] = [], row: (OpaquePointer) -> Void = { _ in }) -> Bool {
        guard let db else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32 = switch binding {
            case .text(let value): sqlite3_bind_text(statement, index, value, -1, Self.transient)
            case .real(let value): sqlite3_bind_double(statement, index, value)
            case .int(let value): sqlite3_bind_int64(statement, index, value)
            case .blob(let value):
                value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), Self.transient) }
            }
            guard result == SQLITE_OK else { return false }
        }
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: row(statement)
            case SQLITE_DONE: return true
            default: return false
            }
        }
    }

    nonisolated private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    nonisolated private static func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    nonisolated private static func blob(_ statement: OpaquePointer, _ column: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    /// Opens (creating if needed) the database. A file that can't be opened or set up is
    /// deleted and recreated once; if that fails too, an in-memory database is used so the
    /// app still works, just without keeping copies across launches.
    nonisolated private static func open(_ fileURL: URL?) -> OpaquePointer? {
        if let fileURL {
            let folder = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var excluded = folder
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? excluded.setResourceValues(values)
            if let db = openAndPrepare(fileURL.path) { return db }
            for suffix in ["", "-journal", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: fileURL.path + suffix)
            }
            if let db = openAndPrepare(fileURL.path) { return db }
        }
        return openAndPrepare(":memory:")
    }

    nonisolated private static func openAndPrepare(_ path: String) -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        let schema = """
            PRAGMA foreign_keys = ON;
            PRAGMA secure_delete = ON;
            CREATE TABLE IF NOT EXISTS cached_chore (
                user_id TEXT NOT NULL,
                chore_id TEXT NOT NULL,
                payload BLOB NOT NULL,
                saved_at REAL NOT NULL,
                last_viewed_at REAL NOT NULL,
                PRIMARY KEY (user_id, chore_id)
            );
            CREATE TABLE IF NOT EXISTS cached_photo (
                user_id TEXT NOT NULL,
                chore_id TEXT NOT NULL,
                url TEXT NOT NULL,
                data BLOB NOT NULL,
                PRIMARY KEY (user_id, chore_id, url),
                FOREIGN KEY (user_id, chore_id) REFERENCES cached_chore (user_id, chore_id) ON DELETE CASCADE
            );
            PRAGMA user_version = 1;
            """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        return db
    }
}
