import Foundation

/// Lets tests fail a specific step of a multi-resource operation, once, to prove that
/// compensation leaves nothing behind.
actor FaultInjector {
    enum Point: Hashable, Sendable {
        /// The nth upload (1-based) fails.
        case upload(nth: Int)
        case createChore
        case updateChore
        case deleteChore
        case insertAttachments
        case deleteAttachments
        case removeFiles
    }

    private var armed: [Point: DataServiceError] = [:]
    private var uploads = 0

    func arm(_ point: Point, error: DataServiceError = .server) {
        armed[point] = error
    }

    func check(_ point: Point) throws {
        if let error = armed.removeValue(forKey: point) { throw error }
    }

    func checkUpload() throws {
        uploads += 1
        try check(.upload(nth: uploads))
    }
}
