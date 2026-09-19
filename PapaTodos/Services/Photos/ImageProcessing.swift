import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns whatever the photo picker or clipboard hands over into a `PhotoUpload` that both
/// this app and the web app can display.
///
/// - Rejects anything that isn't an image.
/// - JPEG and PNG are kept in their format; HEIC/HEIF and other formats become JPEG,
///   because browsers can't display HEIC and PapaBoard shows these photos in `<img>` tags.
/// - GIF and WebP pass through untouched so animation survives.
/// - Photos are scaled so the longest side is at most `maxDimension` (family photos straight
///   from a modern phone are tens of megabytes).
/// - Orientation is applied to the pixels and the rest of the metadata, including any
///   location, is not carried over.
nonisolated enum ImageProcessing {
    static let maxDimension = 2048
    static let jpegQuality = 0.85

    enum Failure: Error, Equatable {
        case notAnImage
        case encodingFailed
    }

    static func prepare(data: Data, suggestedName: String? = nil) throws -> PhotoUpload {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let type = UTType(typeIdentifier), type.conforms(to: .image)
        else { throw Failure.notAnImage }

        let base = baseName(from: suggestedName)

        if type == .gif || type == .webP {
            return PhotoUpload(data: data, fileName: sanitize(base + "." + (type.preferredFilenameExtension ?? "img")), mimeType: type.preferredMIMEType ?? "image/*")
        }

        let keepsPNG = type == .png
        let output = keepsPNG ? UTType.png : UTType.jpeg
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure.notAnImage
        }

        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, output.identifier as CFString, 1, nil) else {
            throw Failure.encodingFailed
        }
        let properties: [CFString: Any] = keepsPNG ? [:] : [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }

        return PhotoUpload(
            data: encoded as Data,
            // `UTType.jpeg` prefers ".jpeg"; keep the ".jpg" the web app and cameras use.
            fileName: sanitize(base + "." + (keepsPNG ? "png" : "jpg")),
            mimeType: output.preferredMIMEType ?? "image/jpeg"
        )
    }

    /// Ported from `sanitizeFilename` in PapaBoard's `attachments.js`: lower-case, anything
    /// outside `a-z 0-9 . _ -` becomes `-`, and runs of `-` collapse.
    static func sanitize(_ fileName: String) -> String {
        let lowered = fileName.lowercased()
        let replaced = String(lowered.unicodeScalars.map { scalar -> Character in
            switch scalar {
            case "a"..."z", "0"..."9", ".", "_", "-": Character(scalar)
            default: "-"
            }
        })
        return replaced.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
    }

    private static func baseName(from suggestedName: String?) -> String {
        guard let suggestedName, !suggestedName.isEmpty else { return "photo" }
        let stem = (suggestedName as NSString).deletingPathExtension
        return stem.isEmpty ? "photo" : stem
    }

    /// Pixel size of an encoded image, for tests and previews.
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }
}
