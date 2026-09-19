import Foundation

/// Saves a chore together with its photos, following specification.md section 9.6.
///
/// The save spans Storage, `chores` and `chore_attachments` and cannot be atomic, so each
/// step has explicit compensation:
///
/// 1. upload new photos;  2. create or update the chore;  3. insert attachment rows;
/// 4. delete removed attachment rows;  5. remove the removed photos' files.
///
/// Compensation only ever undoes what *this* save created. It never deletes a pre-existing
/// attachment. Storage deletes can be refused by policy, so leftover files are reported
/// (`leftoverPaths` / `orphanedPaths`) rather than assumed gone, and can be retried.
nonisolated struct ChoreSaveService: Sendable {
    let chores: any ChoreRepository
    let attachments: any AttachmentRepository
    let storage: any AttachmentStorage

    struct Request: Sendable {
        enum Kind: Sendable {
            case create(ChoreDraft)
            case edit(original: Chore, patch: ChorePatch)
        }
        var kind: Kind
        /// Existing attachments that remain, in display order.
        var keep: [ChoreAttachment] = []
        /// Existing attachments the user removed.
        var remove: [ChoreAttachment] = []
        var newPhotos: [PhotoUpload] = []
    }

    enum Warning: Sendable, Equatable {
        /// The chore was saved but the removed photos' rows could not be deleted.
        case removedPhotosNotDeleted(DataServiceError)
        /// Files that could not be removed from Storage (still present in the bucket).
        case storageCleanupIncomplete(paths: [String])
    }

    struct Success: Sendable {
        var chore: Chore
        var warnings: [Warning]
    }

    struct Failure: Error, Sendable {
        var error: DataServiceError
        /// Newly uploaded files that could not be removed after the failure.
        var orphanedPaths: [String]
        /// A chore created by this save that could not be deleted again.
        var orphanedChoreID: UUID?
    }

    func save(_ request: Request) async -> Result<Success, Failure> {
        var uploaded: [UploadedFile] = []

        // 1. Upload new photos.
        for photo in request.newPhotos {
            do {
                uploaded.append(try await storage.upload(photo))
            } catch {
                return .failure(await failure(error, cleaning: uploaded))
            }
        }

        let primaryURL = (request.keep.map(\.publicURL) + uploaded.map(\.publicURL)).first
        let newRows = uploaded.enumerated().map { index, file in
            NewAttachment(
                storagePath: file.storagePath, publicURL: file.publicURL, fileName: file.fileName,
                mimeType: file.mimeType, sortOrder: request.keep.count + index
            )
        }

        switch request.kind {
        case .create(var draft):
            draft.imageURL = primaryURL
            return await create(draft, newRows: newRows, uploaded: uploaded)
        case .edit(let original, var patch):
            if primaryURL != original.imageURL { patch.imageURL = .some(primaryURL) }
            return await edit(original: original, patch: patch, request: request, newRows: newRows, uploaded: uploaded)
        }
    }

    // MARK: create

    private func create(_ draft: ChoreDraft, newRows: [NewAttachment], uploaded: [UploadedFile]) async -> Result<Success, Failure> {
        // 2. Create the chore.
        let created: Chore
        do {
            created = try await chores.create(draft)
        } catch {
            return .failure(await failure(error, cleaning: uploaded))
        }

        // 3. Insert attachment rows; on failure undo the chore and the uploads.
        if !newRows.isEmpty {
            do {
                _ = try await attachments.insert(newRows, choreID: created.id)
            } catch {
                var result = await failure(error, cleaning: uploaded)
                do { try await chores.delete(id: created.id) } catch { result.orphanedChoreID = created.id }
                return .failure(result)
            }
        }
        let latest = (try? await chores.fetchChore(id: created.id)) ?? created
        return .success(Success(chore: latest, warnings: []))
    }

    // MARK: edit

    private func edit(
        original: Chore, patch: ChorePatch, request: Request, newRows: [NewAttachment], uploaded: [UploadedFile]
    ) async -> Result<Success, Failure> {
        // 3. Insert new attachment rows first, like the web client.
        var insertedIDs: [UUID] = []
        if !newRows.isEmpty {
            do {
                insertedIDs = try await attachments.insert(newRows, choreID: original.id)
            } catch {
                return .failure(await failure(error, cleaning: uploaded))
            }
        }

        // 2. Update the chore; on failure undo the rows and uploads this save added.
        var updated = original
        if !patch.isEmpty {
            do {
                updated = try await chores.update(id: original.id, patch: patch)
            } catch {
                if !insertedIDs.isEmpty { try? await attachments.delete(ids: insertedIDs) }
                return .failure(await failure(error, cleaning: uploaded))
            }
        }

        var warnings: [Warning] = []

        // 4. Delete removed rows. A legacy image has no row (its synthesized id is the chore's).
        let removedRowIDs = request.remove.filter { $0.id != original.id }.map(\.id)
        var rowsDeleted = true
        if !removedRowIDs.isEmpty {
            do {
                try await attachments.delete(ids: removedRowIDs)
            } catch {
                rowsDeleted = false
                warnings.append(.removedPhotosNotDeleted((error as? DataServiceError) ?? .server))
            }
        }

        // 5. Remove the removed photos' files, but only if their rows are really gone.
        if rowsDeleted {
            let leftover = await removeFiles(paths: request.remove.map(\.storagePath))
            if !leftover.isEmpty { warnings.append(.storageCleanupIncomplete(paths: leftover)) }
        }

        let latest = (try? await chores.fetchChore(id: original.id)) ?? updated
        return .success(Success(chore: latest, warnings: warnings))
    }

    // MARK: cleanup helpers

    /// Removes files and returns the paths still present afterwards (retryable).
    func removeFiles(paths: [String]) async -> [String] {
        let requested = Array(Set(paths.filter { !$0.isEmpty })).sorted()
        guard !requested.isEmpty else { return [] }
        let removed = Set((try? await storage.remove(paths: requested)) ?? [])
        return requested.filter { !removed.contains($0) }
    }

    private func failure(_ error: any Error, cleaning uploaded: [UploadedFile]) async -> Failure {
        let orphans = await removeFiles(paths: uploaded.map(\.storagePath))
        return Failure(error: (error as? DataServiceError) ?? .server, orphanedPaths: orphans, orphanedChoreID: nil)
    }
}

/// Deleting a chore: the row (its comments and attachment rows go with it via the
/// foreign keys' `ON DELETE CASCADE`), then its photo files.
nonisolated struct ChoreDeleteService: Sendable {
    let chores: any ChoreRepository
    let storage: any AttachmentStorage

    struct Outcome: Sendable, Equatable {
        /// Photo files that are still in Storage after the chore was deleted.
        var leftoverPaths: [String]
    }

    func delete(_ chore: Chore) async -> Result<Outcome, DataServiceError> {
        let paths = ChoreAttachments.all(for: chore).map(\.storagePath)
        do {
            try await chores.delete(id: chore.id)
        } catch {
            return .failure((error as? DataServiceError) ?? .server)
        }
        let leftover = await ChoreSaveService(chores: chores, attachments: NoAttachments(), storage: storage).removeFiles(paths: paths)
        return .success(Outcome(leftoverPaths: leftover))
    }

    private struct NoAttachments: AttachmentRepository {
        func insert(_ attachments: [NewAttachment], choreID: UUID) async throws -> [UUID] { [] }
        func delete(ids: [UUID]) async throws {}
    }
}
