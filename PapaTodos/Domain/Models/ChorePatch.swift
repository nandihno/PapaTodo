import Foundation

/// The fields of a chore that an edit actually changes. Nothing is sent for an unchanged
/// field, so an untouched due date (and its date-only noon sentinel) or an untouched rich
/// description is never rewritten.
///
/// `Optional<T?>` fields use `nil` for "unchanged" and `.some(nil)` for "set to null".
nonisolated struct ChorePatch: Sendable, Equatable {
    var title: String?
    var description: String??
    var assignedTo: UUID??
    var status: ChoreStatus?
    var dueDate: Date??
    var imageURL: URL??

    init(
        title: String? = nil, description: String?? = nil, assignedTo: UUID?? = nil,
        status: ChoreStatus? = nil, dueDate: Date?? = nil, imageURL: URL?? = nil
    ) {
        self.title = title
        self.description = description
        self.assignedTo = assignedTo
        self.status = status
        self.dueDate = dueDate
        self.imageURL = imageURL
    }

    var isEmpty: Bool {
        title == nil && description == nil && assignedTo == nil && status == nil && dueDate == nil && imageURL == nil
    }
}

/// A photo ready to upload: already validated as an image, converted to a widely
/// displayable format, and given a sanitized file name.
nonisolated struct PhotoUpload: Sendable, Equatable, Identifiable {
    let id: UUID
    var data: Data
    var fileName: String
    var mimeType: String

    init(id: UUID = UUID(), data: Data, fileName: String, mimeType: String) {
        self.id = id
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
    }
}

/// The result of a successful Storage upload.
nonisolated struct UploadedFile: Sendable, Equatable {
    var storagePath: String
    var publicURL: URL
    var fileName: String
    var mimeType: String
}

/// An attachment row to insert. The creator is taken from the signed-in session by the
/// repository, never supplied by the caller.
nonisolated struct NewAttachment: Sendable, Equatable {
    var storagePath: String
    var publicURL: URL
    var fileName: String
    var mimeType: String
    var sortOrder: Int
}
