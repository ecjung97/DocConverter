import AppKit
import ImageIO
import PDFKit

// Compile with ConverterEngine.swift. Tests actual exported pixels and physical page size.
@main
struct ConversionQualityRegression {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for rotation in [0, 90, 180, 270] {
            let source = root.appendingPathComponent("page-\(rotation).pdf")
            var bounds = CGRect(x: 20, y: 30, width: 144, height: 216)
            let context = CGContext(source as CFURL, mediaBox: &bounds, nil)!
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 20, y: 30, width: 72, height: 216))
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 92, y: 30, width: 72, height: 216))
            context.endPDFPage()
            context.closePDF()
            let document = PDFDocument(url: source)!
            document.page(at: 0)!.rotation = rotation
            precondition(document.write(to: source))

            let imageURL = try ConverterEngine.convertPDFtoJPG(pdfURL: source, outputDirectory: root)[0]
            let bitmap = NSBitmapImageRep(data: try Data(contentsOf: imageURL))!
            let expectedSize = rotation % 180 == 0 ? CGSize(width: 600, height: 900) : CGSize(width: 900, height: 600)
            precondition(bitmap.pixelsWide == Int(expectedSize.width))
            precondition(bitmap.pixelsHigh == Int(expectedSize.height), "Export must render at 300 dpi")
            let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil)!
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)! as NSDictionary
            precondition((properties[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue == 300)
            precondition((properties[kCGImagePropertyDPIHeight] as? NSNumber)?.intValue == 300)

            let sampleX = rotation == 0 ? bitmap.pixelsWide / 4 : rotation == 180 ? bitmap.pixelsWide * 3 / 4 : bitmap.pixelsWide / 2
            let sampleY = rotation == 90 ? bitmap.pixelsHigh / 4 : rotation == 270 ? bitmap.pixelsHigh * 3 / 4 : bitmap.pixelsHigh / 2
            let red = bitmap.colorAt(x: sampleX, y: sampleY)!.usingColorSpace(.deviceRGB)!
            precondition(red.redComponent > 0.8 && red.blueComponent < 0.2, "Page rotation and nonzero origin must be respected")

            let roundTrip = root.appendingPathComponent("roundtrip-\(rotation).pdf")
            try ConverterEngine.convertImagesToPDF(imageURLs: [imageURL], outputURL: roundTrip)
            let restored = PDFDocument(url: roundTrip)!.page(at: 0)!
            let restoredSize = restored.bounds(for: .mediaBox).size
            precondition(abs(restoredSize.width - expectedSize.width * 72 / 300) < 0.01)
            precondition(abs(restoredSize.height - expectedSize.height * 72 / 300) < 0.01,
                         "JPG to PDF must retain the physical page size")
            print("PASS: 300 dpi, page size, offset origin, rotation \(rotation)")
        }

        // EXIF rotation must not shrink images, including images exceeding the old 8,000 px cap.
        let largeImage = root.appendingPathComponent("wide.jpg")
        let pixels = CGContext(data: nil, width: 9001, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        pixels.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        pixels.fill(CGRect(x: 0, y: 0, width: 9001, height: 12))
        let destination = CGImageDestinationCreateWithURL(largeImage as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, pixels.makeImage()!, [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyDPIWidth: 300,
            kCGImagePropertyDPIHeight: 150
        ] as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        let output = root.appendingPathComponent("wide.pdf")
        try ConverterEngine.convertImagesToPDF(imageURLs: [largeImage], outputURL: output)
        let size = PDFDocument(url: output)!.page(at: 0)!.bounds(for: .mediaBox).size
        precondition(abs(size.width - 12 * 72 / 150) < 0.01)
        precondition(abs(size.height - 9001 * 72 / 300) < 0.01, "Full-resolution images must not be reduced to 8,000 pixels")
        print("PASS: full-resolution image import, EXIF rotation, and unequal X/Y DPI")

        // Compare every EXIF rotation/mirror against ImageIO's orientation handling.
        let pattern = CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let colors: [CGColor] = [CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                                 CGColor(red: 0, green: 1, blue: 0, alpha: 1),
                                 CGColor(red: 0, green: 0, blue: 1, alpha: 1),
                                 CGColor(red: 1, green: 1, blue: 0, alpha: 1)]
        for i in 0..<4 {
            pattern.setFillColor(colors[i])
            pattern.fill(CGRect(x: (i % 2) * 60, y: (i / 2) * 40, width: 60, height: 40))
        }
        for orientation in 1...8 {
            let input = root.appendingPathComponent("orientation-\(orientation).jpg")
            let destination = CGImageDestinationCreateWithURL(input as CFURL, "public.jpeg" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, pattern.makeImage()!, [
                kCGImagePropertyOrientation: orientation,
                kCGImagePropertyDPIWidth: 72,
                kCGImagePropertyDPIHeight: 72,
                kCGImageDestinationLossyCompressionQuality: 1.0
            ] as CFDictionary)
            precondition(CGImageDestinationFinalize(destination))
            let source = CGImageSourceCreateWithURL(input as CFURL, nil)!
            let reference = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 120
            ] as CFDictionary)!
            let expected = NSBitmapImageRep(cgImage: reference)
            let pdf = root.appendingPathComponent("orientation-\(orientation).pdf")
            try ConverterEngine.convertImagesToPDF(imageURLs: [input], outputURL: pdf)
            let verificationDocument = PDFDocument(url: pdf)!
            let rendered = withExtendedLifetime(verificationDocument) {
                verificationDocument.page(at: 0)!.thumbnail(of: CGSize(width: reference.width, height: reference.height), for: .mediaBox)
            }
            let actual = NSBitmapImageRep(data: rendered.tiffRepresentation!)!
            for y in [1, 3] {
                for x in [1, 3] {
                    let expectedColor = expected.colorAt(x: reference.width * x / 4, y: reference.height * y / 4)!.usingColorSpace(.deviceRGB)!
                    let actualColor = actual.colorAt(x: actual.pixelsWide * x / 4, y: actual.pixelsHigh * y / 4)!.usingColorSpace(.deviceRGB)!
                    precondition(abs(expectedColor.redComponent - actualColor.redComponent) < 0.15)
                    precondition(abs(expectedColor.greenComponent - actualColor.greenComponent) < 0.15)
                    precondition(abs(expectedColor.blueComponent - actualColor.blueComponent) < 0.15)
                }
            }
        }
        print("PASS: all eight EXIF orientations preserve image content")
    }
}
