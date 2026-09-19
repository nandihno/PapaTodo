import Foundation
import Supabase

/// The `chore-images` bucket, using PapaBoard's object path convention.
nonisolated struct SupabaseAttachmentStorage: AttachmentStorage {
    let client: SupabaseClient

    func upload(_ photo: PhotoUpload) async throws -> UploadedFile {
        do {
            let userID = try await client.auth.session.user.id.uuidString.lowercased()
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let path = "\(userID)/\(timestamp)-\(UUID().uuidString.lowercased())-\(photo.fileName)"
            let bucket = client.storage.from(ChoreAttachments.bucket)
            try await bucket.upload(
                path, data: photo.data,
                options: FileOptions(cacheControl: "3600", contentType: photo.mimeType, upsert: false)
            )
            return UploadedFile(
                storagePath: path, publicURL: try bucket.getPublicURL(path: path),
                fileName: photo.fileName, mimeType: photo.mimeType
            )
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func remove(paths: [String]) async throws -> [String] {
        guard !paths.isEmpty else { return [] }
        do {
            let removed = try await client.storage.from(ChoreAttachments.bucket).remove(paths: paths)
            return removed.map(\.name)
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }
}
