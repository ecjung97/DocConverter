# DocConverter

DocConverter is a macOS SwiftUI app for previewing, converting, and merging PDF and image files. It supports drag and drop, Finder open-with behavior, multi-file selection, thumbnail previews, reorderable merge order, and PDF preview before export.

## Features

- Open PDF and image files from Finder, drag and drop, or the in-app file picker.
- Preview single PDFs and images.
- Convert JPG, JPEG, and PNG images into PDF files.
- Combine multiple images into one multi-page PDF.
- Merge multiple PDFs into one PDF.
- Preview PDFs before merging.
- Reorder images or PDFs by dragging thumbnails/list rows before export.
- Convert every page of a PDF to a separate JPG image.
- Navigate image previews with on-screen controls and keyboard shortcuts.

## Supported Formats

Input:

- PDF
- JPG / JPEG
- PNG

Output:

- PDF
- JPG

## Requirements

- macOS
- Xcode
- SwiftUI
- PDFKit
- AppKit

The app is built as a sandboxed macOS application. To use save panels and write converted files, the target needs the `User Selected File` sandbox entitlement set to `Read/Write`.

In Xcode:

1. Select the project in the sidebar.
2. Select the `DocConverter` target.
3. Open `Signing & Capabilities`.
4. Under `App Sandbox`, set `User Selected File` to `Read/Write`.

## Build and Run

1. Open `DocConverter.xcodeproj` in Xcode.
2. Select the `DocConverter` scheme.
3. Press `Command + R` to build and run.

After running once, macOS can register the app as a viewer for supported document types.

## Usage

### Open Files

Use `Open Files...`, drag files into the window, or double-click supported files in Finder if DocConverter is registered as their default app.

### Convert Images to PDF

1. Open one or more JPG, JPEG, or PNG files.
2. Reorder the images by dragging thumbnails if needed.
3. Click `Convert to PDF` for one image or `Merge into PDF` for multiple images.
4. Choose the output location.

### Merge PDFs

1. Open or drop multiple PDF files.
2. Select a PDF in the left list to preview it.
3. Drag PDFs in the list to arrange the merge order.
4. Click `Merge PDFs`.
5. Choose the output location.

### Convert PDF to JPG

1. Open a single PDF.
2. Click `Convert to JPG`.
3. Choose an output folder.

DocConverter creates a folder named after the PDF inside the selected output folder. Every page is saved inside it in order as `<PDF name>_Page_01.jpg`, `<PDF name>_Page_02.jpg`, and so on. If that folder name already exists, a new folder such as `<PDF name> (2)` is created to preserve existing files. The completion dialog reports the number of pages saved and the actual folder path; conversion failures are shown in an error dialog.

JPG export renders at 300 dpi with maximum JPEG quality, instead of using PDF points as pixels (approximately 72 dpi). The JPEG stores its resolution so converting it back to PDF preserves the physical page size. Image import uses full-resolution pixels, respects EXIF rotation/mirroring, and uses maximum PDF image compression quality. JPEG is still lossy: use the original PDFs and `Merge PDFs` when no image editing is needed. Increasing resolution cannot recover detail already lost in an earlier conversion. Higher-quality exports take more storage; pages exceeding 100 megapixels at 300 dpi report an error instead of silently reducing resolution.

Rebuild the app after changing the source. Older app bundles can still export only the first page. The release build can be generated with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project DocConverter.xcodeproj -scheme DocConverter -configuration Release \
  -derivedDataPath /tmp/DocConverter-DerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
```

Run the freshly built `/tmp/DocConverter-DerivedData/Build/Products/Release/DocConverter.app`.

Alternatively, build a locally signed app for the current Mac using the installed Swift command-line tools and the bundled app resources:

```sh
bash scripts/build-local.sh
open build/Release/DocConverter.app
```

The local build script preserves the app's sandbox entitlements. With newer SwiftUI SDKs, it also uses Xcode's SwiftUI compiler plugin.

### PDF export regression check

```sh
mkdir -p /tmp/DocConverter-tests
xcrun swiftc -module-cache-path /tmp/DocConverter-tests/ModuleCache \
  DocConverter/ConverterEngine.swift Tests/PDFToJPGRegression.swift \
  -o /tmp/DocConverter-tests/pdf-to-jpg
/tmp/DocConverter-tests/pdf-to-jpg
xcrun swiftc -module-cache-path /tmp/DocConverter-tests/ModuleCache \
  DocConverter/ConverterEngine.swift Tests/ConversionQualityRegression.swift \
  -o /tmp/DocConverter-tests/quality
/tmp/DocConverter-tests/quality
```

## Project Structure

```text
DocConverter/
  Assets.xcassets
  ContentView.swift
  ConverterEngine.swift
  DocConverterApp.swift
  Info.plist
  PDFKitView.swift
```

Key files:

- `ContentView.swift`: Main SwiftUI interface, drag and drop, previews, file selection, merge ordering, and user controls.
- `ConverterEngine.swift`: PDF/image conversion and PDF merge logic.
- `PDFKitView.swift`: SwiftUI bridge for displaying PDFs with PDFKit.
- `DocConverterApp.swift`: App entry point and Finder open URL handling.
- `Info.plist`: Document type registration for PDFs and images.

## Notes

- Image-to-PDF conversion applies EXIF orientation to full-resolution pixels and preserves the image's DPI when sizing the PDF page.
- PDF merging preserves page order based on the order shown in the app.
- Mixed PDF and image selections are not merged together; use image-to-PDF and PDF merge as separate workflows.
