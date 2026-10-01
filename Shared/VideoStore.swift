//
//  VideoStore.swift
//  DragTube (shared by the app and the extension)
//
//  The list of saved videos, shared by the Safari extension (saves) and the app (shows the sheet).
//  Gets the real title from YouTube if the page didn't provide one.
//

import Foundation
import Combine

struct SavedVideo: Codable, Identifiable, Hashable {
    let id: String          // YouTube video ID, e.g. "dQw4w9WgXcQ"
    var title: String
    var addedAt: Date

    var url: URL { Self.watchURL(for: id) }
    var thumbnail: URL { URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")! }

    static func watchURL(for id: String) -> URL {
        URL(string: "https://www.youtube.com/watch?v=\(id)")!
    }
}

@MainActor
final class VideoStore: ObservableObject {
    static let shared = VideoStore()

    @Published var videos: [SavedVideo] = [] {
        didSet { save() }
    }

    private let storageKey = "savedVideos"
    private static let placeholderTitle = "YouTube video"

    private let defaults = AppGroup.defaults

    private init() {
        migrateFromStandardDefaults()
        reload()
    }

    /// Videos saved before the App Group existed live in the extension's own defaults
    private func migrateFromStandardDefaults() {
        guard defaults !== UserDefaults.standard,
              defaults.data(forKey: storageKey) == nil,
              let old = UserDefaults.standard.data(forKey: storageKey)
        else { return }
        defaults.set(old, forKey: storageKey)
    }

    /// Re-reads the saved list (the other process may have changed it)
    func reload() {
        if let data = defaults.data(forKey: storageKey),
           let list = try? JSONDecoder().decode([SavedVideo].self, from: data),
           list != videos {
            videos = list
        }
    }

    // Every change re-reads first: the app and the extension both write this list.

    func add(id: String, title: String?) {
        reload()
        let pageTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let oldTitle = videos.first(where: { $0.id == id })?.title
        let bestTitle = !pageTitle.isEmpty ? pageTitle : (oldTitle ?? Self.placeholderTitle)

        videos.removeAll { $0.id == id }
        videos.insert(SavedVideo(id: id, title: bestTitle, addedAt: Date()), at: 0)

        if bestTitle == Self.placeholderTitle {
            Task { await fetchTitle(for: id) }
        }
    }

    func remove(_ video: SavedVideo) {
        reload()
        videos.removeAll { $0.id == video.id }
    }

    func clear() {
        reload()
        videos.removeAll()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(videos) {
            defaults.set(data, forKey: storageKey)
        }
    }

    /// YouTube's public oEmbed endpoint gives the title without an API key.
    private func fetchTitle(for id: String) async {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(id)"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let requestURL = components.url,
              let result = try? await URLSession.shared.data(from: requestURL),
              let json = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let title = json["title"] as? String
        else { return }

        reload()
        guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
        videos[index].title = title
    }
}
