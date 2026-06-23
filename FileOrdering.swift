import Foundation

enum FileOrdering {
    static func sorted(_ urls: [URL]) -> [URL] {
        urls.sorted { lhs, rhs in
            lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }

    static func sortedUnique(_ urls: [URL]) -> [URL] {
        var seenURLs = Set<URL>()
        return sorted(urls).filter { url in
            seenURLs.insert(url).inserted
        }
    }

    static func appendingUnique(_ newURLs: [URL], to existingURLs: [URL]) -> [URL] {
        var seenURLs = Set(existingURLs)
        let additions = sorted(newURLs).filter { url in
            seenURLs.insert(url).inserted
        }
        return existingURLs + additions
    }
}
