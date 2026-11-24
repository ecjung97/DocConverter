import AppKit
import PDFKit

// Standalone integration check: compile this with ConverterEngine.swift.
@main
struct PDFToJPGRegression {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocConverter-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for pageCount in [1, 3, 12] {
            let directory = root.appendingPathComponent("\(pageCount)-pages")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let pdfURL = directory.appendingPathComponent("테스트 문서.pdf")
            var bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
            let context = CGContext(pdfURL as CFURL, mediaBox: &bounds, nil)!
            let colors: [CGColor] = [
                CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                CGColor(red: 0, green: 1, blue: 0, alpha: 1),
                CGColor(red: 0, green: 0, blue: 1, alpha: 1)
            ]
            for index in 0..<pageCount {
                context.beginPDFPage(nil)
                context.setFillColor(colors[index % colors.count])
                context.fill(bounds)
                context.endPDFPage()
            }
            context.closePDF()

            let outputs = try ConverterEngine.convertPDFtoJPG(pdfURL: pdfURL, outputDirectory: directory)
            precondition(outputs.count == pageCount, "Every PDF page must be exported")
            let exportDirectory = directory.appendingPathComponent("테스트 문서", isDirectory: true)
            let jpgs = try FileManager.default.contentsOfDirectory(at: exportDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "jpg" }
            precondition(jpgs.count == pageCount, "Expected one file on disk per page")
            let looseJPGs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "jpg" }
            precondition(looseJPGs.isEmpty, "JPG files must be inside the new PDF folder")

            for (index, output) in outputs.enumerated() {
                precondition(output.deletingLastPathComponent().path == exportDirectory.path)
                let expectedName = String(format: "테스트 문서_Page_%02d.jpg", index + 1)
                precondition(output.lastPathComponent == expectedName, "Page filenames must sort in order")
                let bitmap = NSBitmapImageRep(data: try Data(contentsOf: output))!
                precondition(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
                let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!
                    .usingColorSpace(.deviceRGB)!
                let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                for channel in 0..<3 {
                    // Allow color-profile conversion and JPEG compression while checking page identity.
                    let matches = channel == index % 3 ? channels[channel] > 0.8 : channels[channel] < 0.5
                    precondition(matches,
                                 "Each JPG must contain its own page, not a copy of the first page")
                }
            }
            // A repeated export must create another folder without touching the previous results.
            let originalData = try outputs.map { try Data(contentsOf: $0) }
            let repeatedOutputs = try ConverterEngine.convertPDFtoJPG(pdfURL: pdfURL, outputDirectory: directory)
            precondition(repeatedOutputs.count == pageCount)
            for (index, output) in repeatedOutputs.enumerated() {
                precondition(output.deletingLastPathComponent().lastPathComponent == "테스트 문서 (2)")
                let previousData = try Data(contentsOf: outputs[index])
                precondition(previousData == originalData[index], "Previous exports must be preserved")
                precondition(FileManager.default.fileExists(atPath: output.path))
            }
            // A file occupying the next folder name must also be preserved and skipped.
            let occupiedName = directory.appendingPathComponent("테스트 문서 (3)")
            let sentinel = Data("Keep this file".utf8)
            try sentinel.write(to: occupiedName)
            let thirdOutputs = try ConverterEngine.convertPDFtoJPG(pdfURL: pdfURL, outputDirectory: directory)
            precondition(thirdOutputs.count == pageCount)
            precondition(thirdOutputs.allSatisfy {
                $0.deletingLastPathComponent().lastPathComponent == "테스트 문서 (4)"
            })
            let preservedFile = try Data(contentsOf: occupiedName)
            precondition(preservedFile == sentinel)
            print("PASS: \(pageCount)-page PDF — folder, JPG content, and repeated-export preservation verified")
        }
    }
}
