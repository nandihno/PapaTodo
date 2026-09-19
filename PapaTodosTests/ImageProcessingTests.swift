import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PapaTodos

struct ImageProcessingTests {
    /// Encodes a solid-color test image, optionally tagging an EXIF orientation and GPS data.
    private func makeImage(width: Int, height: Int, type: UTType, orientation: Int? = nil, withGPS: Bool = false) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        if withGPS { properties[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: -37.8, kCGImagePropertyGPSLongitude: 144.9] }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func aLargeJPEGIsScaledDownAndStaysAJPEG() throws {
        let photo = try ImageProcessing.prepare(data: makeImage(width: 4000, height: 3000, type: .jpeg), suggestedName: "IMG 0001.JPG")
        let size = try #require(ImageProcessing.pixelSize(of: photo.data))
        #expect(max(size.width, size.height) == ImageProcessing.maxDimension)
        #expect(size.width == 2048 && size.height == 1536)   // aspect ratio preserved
        #expect(photo.mimeType == "image/jpeg")
        #expect(photo.fileName == "img-0001.jpg")
    }

    @Test func aSmallPhotoIsNotEnlarged() throws {
        let photo = try ImageProcessing.prepare(data: makeImage(width: 640, height: 480, type: .jpeg))
        let size = try #require(ImageProcessing.pixelSize(of: photo.data))
        #expect(size.width == 640 && size.height == 480)
    }

    @Test func aPNGStaysAPNG() throws {
        let photo = try ImageProcessing.prepare(data: makeImage(width: 300, height: 200, type: .png), suggestedName: "pasted-photo.png")
        #expect(photo.mimeType == "image/png")
        #expect(photo.fileName == "pasted-photo.png")
    }

    @Test func aHEICPhotoBecomesAJPEGSoBrowsersCanShowIt() throws {
        let heic: Data
        do { heic = try makeImage(width: 800, height: 600, type: .heic) } catch { return }   // encoder unavailable on this runtime
        let photo = try ImageProcessing.prepare(data: heic, suggestedName: "IMG_1.HEIC")
        #expect(photo.mimeType == "image/jpeg")
        #expect(photo.fileName == "img_1.jpg")
        let reread = CGImageSourceCreateWithData(photo.data as CFData, nil)
        #expect((reread.flatMap { CGImageSourceGetType($0) as String? }) == UTType.jpeg.identifier)
    }

    @Test func exifOrientationIsAppliedToThePixels() throws {
        // Orientation 6 = rotated 90 degrees: a stored 200x100 image must display as 100x200.
        let photo = try ImageProcessing.prepare(data: makeImage(width: 200, height: 100, type: .jpeg, orientation: 6))
        let size = try #require(ImageProcessing.pixelSize(of: photo.data))
        #expect(size.width == 100 && size.height == 200)
    }

    @Test func locationMetadataIsNotCarriedOver() throws {
        let original = try makeImage(width: 200, height: 100, type: .jpeg, withGPS: true)
        let originalSource = try #require(CGImageSourceCreateWithData(original as CFData, nil))
        let originalProps = try #require(CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil) as? [CFString: Any])
        #expect(originalProps[kCGImagePropertyGPSDictionary] != nil)   // the fixture really has it

        let photo = try ImageProcessing.prepare(data: original)
        let source = try #require(CGImageSourceCreateWithData(photo.data as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func nonImagesAreRejected() {
        #expect(throws: ImageProcessing.Failure.notAnImage) { try ImageProcessing.prepare(data: Data("just text".utf8)) }
        #expect(throws: ImageProcessing.Failure.notAnImage) { try ImageProcessing.prepare(data: Data()) }
        #expect(throws: ImageProcessing.Failure.notAnImage) { try ImageProcessing.prepare(data: Data([0x25, 0x50, 0x44, 0x46])) }   // "%PDF"
    }

    @Test(arguments: [
        ("My Photo (1).JPG", "my-photo-1-.jpg"), ("a  b", "a-b"), ("ünï.png", "-n-.png"), ("ok_name-1.jpeg", "ok_name-1.jpeg"), ("///", "-"),
    ])
    func filenamesAreSanitizedLikeTheWeb(input: String, expected: String) {
        #expect(ImageProcessing.sanitize(input) == expected)
    }
}
