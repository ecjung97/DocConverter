import AppKit
import CoreGraphics
import ImageIO
import PDFKit

struct ConverterEngine {
    private static let maximumRasterDimension: CGFloat = 2_000

    enum ConversionError: LocalizedError {
        case imageLoadFailed
        case pdfPageCreationFailed
        case pdfLoadFailed
        case pdfPageMissing
        case pdfMergeFailed
        case jpegEncodingFailed
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .imageLoadFailed: return "The image could not be loaded."
            case .pdfPageCreationFailed: return "The PDF page could not be created from the image."
            case .pdfLoadFailed: return "The PDF could not be opened."
            case .pdfPageMissing: return "The PDF does not contain a first page."
            case .pdfMergeFailed: return "The PDF pages could not be merged."
            case .jpegEncodingFailed: return "The JPEG output could not be encoded."
            case .writeFailed: return "The converted file could not be written to disk."
            }
        }
    }

    static func convertImagesToPDF(imageURLs: [URL], outputURL: URL) throws {
            // 1. Create an empty PDF document using Apple's high-level framework
            let pdfDocument = PDFDocument()

            for imageURL in imageURLs {
                guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else {
                    throw ConversionError.imageLoadFailed
                }

                // 2. Force CoreGraphics to natively bake the EXIF rotation into the raw pixels
                let options: [CFString: Any] = [
                    kCGImageSourceShouldCache: false,
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true, // Natively fixes rotation
                    kCGImageSourceThumbnailMaxPixelSize: 8000
                ]

                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                    throw ConversionError.imageLoadFailed
                }

                // 3. Wrap the perfectly oriented pixel data back into an NSImage
                let correctSize = CGSize(width: cgImage.width, height: cgImage.height)
                let nsImage = NSImage(cgImage: cgImage, size: correctSize)

                // 4. Let PDFKit handle all the geometry, scaling, and page generation natively!
                if let pdfPage = PDFPage(image: nsImage) {
                    // Insert the page at the end of the document
                    pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
                } else {
                    throw ConversionError.pdfPageCreationFailed
                }
            }

            // 5. Save the final multi-page document
            if !pdfDocument.write(to: outputURL) {
                throw ConversionError.writeFailed
            }
        }

    static func convertPDFtoJPG(pdfURL: URL, outputDirectory: URL) throws -> URL {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            throw ConversionError.pdfLoadFailed
        }
        guard let page = pdfDocument.page(at: 0) else {
            throw ConversionError.pdfPageMissing
        }

        let pageRect = page.bounds(for: .mediaBox)
        let targetSize = scaledSize(for: pageRect.size)
        let image = page.thumbnail(of: targetSize, for: .mediaBox)

        guard
            let tiffData = image.tiffRepresentation,
            let bitmapImage = NSBitmapImageRep(data: tiffData),
            let jpegData = bitmapImage.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.82]
            )
        else {
            throw ConversionError.jpegEncodingFailed
        }

        let outputURL = outputDirectory.appendingPathComponent("Converted_Page.jpg")
        do {
            try jpegData.write(to: outputURL, options: .atomic)
        } catch {
            throw ConversionError.writeFailed
        }
        return outputURL
    }

    static func mergePDFs(pdfURLs: [URL], outputURL: URL) throws {
        let mergedDocument = PDFDocument()

        for pdfURL in pdfURLs {
            guard let sourceDocument = PDFDocument(url: pdfURL) else {
                throw ConversionError.pdfLoadFailed
            }

            for pageIndex in 0..<sourceDocument.pageCount {
                guard let page = sourceDocument.page(at: pageIndex)?.copy() as? PDFPage else {
                    throw ConversionError.pdfMergeFailed
                }
                mergedDocument.insert(page, at: mergedDocument.pageCount)
            }
        }

        if !mergedDocument.write(to: outputURL) {
            throw ConversionError.writeFailed
        }
    }

    private static func scaledSize(for originalSize: CGSize) -> CGSize {
        let maxDimension = max(originalSize.width, originalSize.height)
        guard maxDimension > maximumRasterDimension else { return originalSize }

        let scale = maximumRasterDimension / maxDimension
        return CGSize(
            width: max(1, floor(originalSize.width * scale)),
            height: max(1, floor(originalSize.height * scale))
        )
    }
}
