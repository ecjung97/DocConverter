import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GridDropDelegate: DropDelegate {
    let item: URL
    @Binding var items: [URL]
    @Binding var draggedItem: URL?

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem, draggedItem != item,
              let from = items.firstIndex(of: draggedItem),
              let to = items.firstIndex(of: item) else { return }
        
        withAnimation(.default) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }
}

struct ContentView: View {
    @Binding var fileURLs: [URL]
    @State private var isTargeted: Bool = false
    @State private var draggedItem: URL? = nil
    @State private var selectedPDFURL: URL? = nil
    
    // NEW: State variable to track which image is currently being previewed
    @State private var previewIndex: Int? = nil
    
    let gridColumns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20)]
    let allowedExtensions = ["pdf", "jpg", "jpeg", "png"]

    var body: some View {
        // NEW: Wrapped everything in a ZStack to layer the preview overlay on top
        ZStack {
            // --- MAIN INTERFACE LAYER ---
            VStack {
                if fileURLs.isEmpty {
                    VStack(spacing: 15) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 50))
                        
                        Text("Drag and drop images or PDFs here,\nor double-click files in Finder.")
                            .font(.title2)
                            .multilineTextAlignment(.center)
                        
                        Button("Open Files...") {
                            selectFiles()
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 10)
                    }
                    .foregroundColor(isTargeted ? .accentColor : .secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                } else if fileURLs.count == 1, let url = fileURLs.first {
                    // Single File View
                    if isPDF(url) {
                        PDFKitView(url: url)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if isImage(url) {
                        if let image = NSImage(contentsOf: url) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                        }
                    }
                } else if allPDFs {
                    HSplitView {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(fileURLs.enumerated()), id: \.element) { index, url in
                                    pdfMergeRow(for: url, index: index)
                                        .onTapGesture {
                                            selectedPDFURL = url
                                        }
                                        .onDrag {
                                            draggedItem = url
                                            return NSItemProvider(object: url as NSURL)
                                        }
                                        .onDrop(of: [.fileURL], delegate: GridDropDelegate(item: url, items: $fileURLs, draggedItem: $draggedItem))
                                }
                            }
                            .padding()
                        }
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

                        Group {
                            if let previewURL = currentPDFPreviewURL {
                                PDFKitView(url: previewURL)
                            } else {
                                ContentUnavailableView(
                                    "No PDF Selected",
                                    systemImage: "doc.viewfinder",
                                    description: Text("Select a PDF from the list to preview it before merging.")
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Multiple Files View (Thumbnail Grid)
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 20) {
                            // UPDATED: Now loops through indices so we know which image was clicked
                            ForEach(Array(fileURLs.enumerated()), id: \.element) { index, url in
                                if let image = NSImage(contentsOf: url) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 150, height: 150)
                                        .clipped()
                                        .cornerRadius(8)
                                        .shadow(radius: draggedItem == url ? 10 : 2)
                                        .opacity(draggedItem == url ? 0.5 : 1.0)
                                        
                                        // NEW: Click to open preview
                                        .onTapGesture {
                                            withAnimation {
                                                previewIndex = index
                                            }
                                        }
                                        .onDrag {
                                            self.draggedItem = url
                                            return NSItemProvider(object: url as NSURL)
                                        }
                                        .onDrop(of: [.fileURL], delegate: GridDropDelegate(item: url, items: $fileURLs, draggedItem: $draggedItem))
                                }
                            }
                        }
                        .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                Divider()
                
                // Bottom Controls
                HStack {
                    if !fileURLs.isEmpty {
                        Button("Add More...") { selectFiles() }
                        Button("Clear All") {
                            fileURLs.removeAll()
                            previewIndex = nil
                            selectedPDFURL = nil
                        }
                            .foregroundColor(.red)
                        Spacer()
                    }
                    
                    Button(pdfActionTitle) {
                        let savePanel = NSSavePanel()
                        savePanel.allowedContentTypes = [.pdf]
                        savePanel.nameFieldStringValue = defaultPDFOutputName
                        savePanel.begin { response in
                            if response == .OK, let outURL = savePanel.url {
                                do {
                                    if allPDFs {
                                        try ConverterEngine.mergePDFs(pdfURLs: fileURLs, outputURL: outURL)
                                    } else {
                                        try ConverterEngine.convertImagesToPDF(imageURLs: fileURLs, outputURL: outURL)
                                    }
                                } catch {
                                    print("Conversion failed: \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                    .disabled(!canCreatePDF)
                    
                    Button("Convert to JPG") {
                        if let url = fileURLs.first {
                            let openPanel = NSOpenPanel()
                            openPanel.canChooseDirectories = true
                            openPanel.canChooseFiles = false
                            openPanel.prompt = "Select Save Folder"
                            openPanel.begin { response in
                                if response == .OK, let outDir = openPanel.url {
                                    do {
                                        _ = try ConverterEngine.convertPDFtoJPG(pdfURL: url, outputDirectory: outDir)
                                    } catch {
                                        print("Conversion failed: \(error.localizedDescription)")
                                    }
                                }
                            }
                        }
                    }
                    .disabled(fileURLs.count != 1 || !isPDF(fileURLs[0]))
                }
                .padding()
            }
            // Blur the background interface when the preview is open
            .blur(radius: previewIndex != nil ? 10 : 0)
            
            // --- LIGHTBOX PREVIEW LAYER ---
            if let index = previewIndex {
                ZStack {
                    // Dark background
                    Color.black.opacity(0.85)
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            withAnimation { previewIndex = nil }
                        }
                    
                    // The Full Size Image
                    if let image = NSImage(contentsOf: fileURLs[index]) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(40)
                            .id(index) // Forces SwiftUI to refresh the image during transitions
                    }
                    
                    // Navigation UI (Chevrons & Close Button)
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: { withAnimation { previewIndex = nil } }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding()
                        }
                        Spacer()
                    }
                    
                    HStack {
                        if index > 0 {
                            Button(action: { previousImage() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding()
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Spacer()
                        
                        if index < fileURLs.count - 1 {
                            Button(action: { nextImage() }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding()
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    // INVISIBLE KEYBOARD SHORTCUTS
                    Button("") { previousImage() }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .opacity(0)
                    
                    Button("") { nextImage() }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .opacity(0)
                        
                    Button("") { withAnimation { previewIndex = nil } }
                        .keyboardShortcut(.escape, modifiers: [])
                        .opacity(0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(100) // Ensures it sits completely on top
                .transition(.opacity) // Smooth fade in/out
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .dropDestination(for: URL.self) { items, location in
            applySelection(from: items)
        } isTargeted: { targeted in
            if draggedItem == nil {
                withAnimation { isTargeted = targeted }
            }
        }
    }
    
    // Helper function for navigating backward
    private func previousImage() {
        if let current = previewIndex, current > 0 {
            withAnimation(.easeInOut(duration: 0.2)) {
                previewIndex = current - 1
            }
        }
    }
    
    // Helper function for navigating forward
    private func nextImage() {
        if let current = previewIndex, current < fileURLs.count - 1 {
            withAnimation(.easeInOut(duration: 0.2)) {
                previewIndex = current + 1
            }
        }
    }
    
    private func selectFiles() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = true
        openPanel.allowedContentTypes = [.pdf, .jpeg, .png]
        openPanel.prompt = "Open"
        
        openPanel.begin { response in
            if response == .OK {
                _ = applySelection(from: openPanel.urls)
            }
        }
    }

    private var allPDFs: Bool {
        !fileURLs.isEmpty && fileURLs.allSatisfy(isPDF)
    }

    private var allImages: Bool {
        !fileURLs.isEmpty && fileURLs.allSatisfy(isImage)
    }

    private var canCreatePDF: Bool {
        allPDFs || allImages
    }

    private var pdfActionTitle: String {
        if allPDFs {
            return fileURLs.count > 1 ? "Merge PDFs" : "Copy PDF"
        }
        return fileURLs.count > 1 ? "Merge into PDF" : "Convert to PDF"
    }

    private var defaultPDFOutputName: String {
        if allPDFs {
            return fileURLs.count > 1 ? "Merged_PDFs.pdf" : fileURLs[0].lastPathComponent
        }
        return fileURLs.count > 1 ? "Merged_Document.pdf" : "Converted_Document.pdf"
    }

    private func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    private func isImage(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased())
    }

    private var currentPDFPreviewURL: URL? {
        guard allPDFs else { return nil }
        if let selectedPDFURL, fileURLs.contains(selectedPDFURL) {
            return selectedPDFURL
        }
        return fileURLs.first
    }

    @discardableResult
    private func applySelection(from urls: [URL]) -> Bool {
        let validURLs = urls.filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
        guard !validURLs.isEmpty else { return false }

        let pdfURLs = validURLs.filter(isPDF)
        let imageURLs = validURLs.filter(isImage)

        if !pdfURLs.isEmpty && imageURLs.isEmpty {
            fileURLs.append(contentsOf: pdfURLs)
            fileURLs = Array(NSOrderedSet(array: fileURLs.filter(isPDF))) as! [URL]
            previewIndex = nil
            if let selectedPDFURL, fileURLs.contains(selectedPDFURL) {
                self.selectedPDFURL = selectedPDFURL
            } else {
                selectedPDFURL = fileURLs.first
            }
            return true
        }

        if !imageURLs.isEmpty && pdfURLs.isEmpty {
            if allImages || fileURLs.isEmpty {
                fileURLs.append(contentsOf: imageURLs)
            } else {
                fileURLs = imageURLs
            }
            fileURLs = Array(NSOrderedSet(array: fileURLs.filter(isImage))) as! [URL]
            selectedPDFURL = nil
            return true
        }

        return false
    }

    private func pdfMergeRow(for url: URL, index: Int) -> some View {
        let isSelected = currentPDFPreviewURL == url

        return HStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 24))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Text("Merge order \(index + 1)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? Color.accentColor : Color.clear,
                    lineWidth: 2
                )
        }
    }
}
