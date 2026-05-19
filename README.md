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
- Convert the first page of a PDF to a JPG image.
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

DocConverter currently converts the first page of the PDF to JPG.

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

- Image-to-PDF conversion preserves image orientation metadata by creating a transformed image thumbnail before inserting it into the PDF.
- PDF merging preserves page order based on the order shown in the app.
- Mixed PDF and image selections are not merged together; use image-to-PDF and PDF merge as separate workflows.
