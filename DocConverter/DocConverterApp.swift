import SwiftUI

@main
struct DocConverterApp: App {
    // Change this from a single URL to an array of URLs
    @State private var openedFileURLs: [URL] = []

    var body: some Scene {
        WindowGroup {
            ContentView(fileURLs: $openedFileURLs)
                .onOpenURL { url in
                    // If a file is double-clicked, add it to our list
                    if !openedFileURLs.contains(url) {
                        openedFileURLs.append(url)
                    }
                }
        }
    }
}
