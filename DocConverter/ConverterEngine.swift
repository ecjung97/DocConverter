import AppKit
import CoreGraphics
import ImageIO
import PDFKit

struct ConverterEngine {
    private static let exportDPI: CGFloat = 300

    enum ConversionError: LocalizedError {
        case imageLoadFailed
        case pdfPageCreationFailed
        case pdfLoadFailed
        case pdfPageMissing
        case pdfMergeFailed
        case pageTooLarge
        case jpegEncodingFailed
        case outputDirectoryCreationFailed
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .imageLoadFailed: return "The image could not be loaded."
            case .pdfPageCreationFailed: return "The PDF page could not be created from the image."
            case .pdfLoadFailed: return "The PDF could not be opened."
            case .pdfPageMissing: return "The PDF is empty or a page could not be read."
            case .pdfMergeFailed: return "The PDF pages could not be merged."
            case .pageTooLarge: return "The PDF page is too large to render at 300 dpi (100 megapixel limit)."
            case .jpegEncodingFailed: return "The JPEG output could not be encoded."
            case .outputDirectoryCreationFailed: return "The folder for the JPG images could not be created."
            case .writeFailed: return "The converted file could not be written to disk."
            }
        }
    }

    static func convertImagesToPDF(imageURLs: [URL], outputURL: URL) throws {
        let pdfDocument = PDFDocument()
        for imageURL in imageURLs {
            try autoreleasepool {
                guard
                    let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                    let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                    let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
                else {
                    throw ConversionError.imageLoadFailed
                }

                // Decode full-resolution pixels; thumbnails can also resample images with unequal X/Y DPI.
                let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
                let cgImage = try orientedImage(sourceImage, orientation: orientation)

                // Image pixels and PDF points are different units. Respect the image's resolution.
                var dpiX = imageDPI(properties[kCGImagePropertyDPIWidth])
                var dpiY = imageDPI(properties[kCGImagePropertyDPIHeight])
                if (5...8).contains(orientation) { swap(&dpiX, &dpiY) }
                let pageSize = CGSize(width: CGFloat(cgImage.width) * 72 / dpiX,
                                      height: CGFloat(cgImage.height) * 72 / dpiY)
                let image = NSImage(cgImage: cgImage, size: pageSize)
                guard let page = PDFPage(image: image, options: [
                    .mediaBox: NSValue(rect: CGRect(origin: .zero, size: pageSize)),
                    .compressionQuality: 1.0
                ]) else {
                    throw ConversionError.pdfPageCreationFailed
                }
                pdfDocument.insert(page, at: pdfDocument.pageCount)
            }
        }
        if !pdfDocument.write(to: outputURL) {
            throw ConversionError.writeFailed
        }
    }

    private static func imageDPI(_ value: Any?) -> CGFloat {
        guard let number = value as? NSNumber,
              number.doubleValue.isFinite, number.doubleValue > 0 else { return 72 }
        return CGFloat(number.doubleValue)
    }

    private static func orientedImage(_ image: CGImage, orientation: Int) throws -> CGImage {
        guard (2...8).contains(orientation) else { return image }
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let swapsAxes = (5...8).contains(orientation)
        guard let context = CGContext(data: nil,
                                      width: swapsAxes ? image.height : image.width,
                                      height: swapsAxes ? image.width : image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ConversionError.imageLoadFailed
        }
        // EXIF transforms expressed in Core Graphics' bottom-left coordinate system.
        let transform: CGAffineTransform
        switch orientation {
        case 2: transform = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
        case 3: transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case 4: transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        case 5: transform = CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w)
        case 6: transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        case 7: transform = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        default: transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        }
        context.concatenate(transform)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let result = context.makeImage() else { throw ConversionError.imageLoadFailed }
        return result
    }

    static func convertPDFtoJPG(pdfURL: URL, outputDirectory: URL) throws -> [URL] {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            throw ConversionError.pdfLoadFailed
        }
        guard pdfDocument.pageCount > 0 else {
            throw ConversionError.pdfPageMissing
        }

        let outputBaseName = pdfURL.deletingPathExtension().lastPathComponent
        let exportDirectory = try createExportDirectory(named: outputBaseName, in: outputDirectory)
        let pageNumberWidth = max(2, String(pdfDocument.pageCount).count)
        var outputURLs: [URL] = []

        for pageIndex in 0..<pdfDocument.pageCount {
            let outputURL = try autoreleasepool {
                guard let page = pdfDocument.page(at: pageIndex) else {
                    throw ConversionError.pdfPageMissing
                }
                var pageSize = page.bounds(for: .mediaBox).size
                if abs(page.rotation % 180) == 90 {
                    pageSize = CGSize(width: pageSize.height, height: pageSize.width)
                }
                let targetSize = CGSize(width: ceil(pageSize.width * exportDPI / 72),
                                        height: ceil(pageSize.height * exportDPI / 72))
                guard targetSize.width > 0, targetSize.height > 0,
                      targetSize.width.isFinite, targetSize.height.isFinite,
                      targetSize.width * targetSize.height <= 100_000_000 else {
                    throw ConversionError.pageTooLarge
                }
                let image = page.thumbnail(of: targetSize, for: .mediaBox)
                guard let tiffData = image.tiffRepresentation,
                      let bitmapImage = NSBitmapImageRep(data: tiffData) else {
                    throw ConversionError.jpegEncodingFailed
                }
                // Store 300 dpi in the JPEG so importing it restores the physical page size.
                bitmapImage.size = CGSize(width: CGFloat(bitmapImage.pixelsWide) * 72 / exportDPI,
                                          height: CGFloat(bitmapImage.pixelsHigh) * 72 / exportDPI)
                guard let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 1.0]) else {
                    throw ConversionError.jpegEncodingFailed
                }
                let pageNumber = String(format: "%0*d", pageNumberWidth, pageIndex + 1)
                let outputURL = exportDirectory.appendingPathComponent("\(outputBaseName)_Page_\(pageNumber).jpg")
                do {
                    try jpegData.write(to: outputURL, options: .atomic)
                } catch {
                    throw ConversionError.writeFailed
                }
                return outputURL
            }
            outputURLs.append(outputURL)
        }

        return outputURLs
    }

    private static func createExportDirectory(named name: String, in parentDirectory: URL) throws -> URL {
        let fileManager = FileManager.default
        var directory = parentDirectory.appendingPathComponent(name, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: directory.path) {
            directory = parentDirectory.appendingPathComponent("\(name) (\(suffix))", isDirectory: true)
            suffix += 1
        }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        } catch {
            throw ConversionError.outputDirectoryCreationFailed
        }
        return directory
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

}
