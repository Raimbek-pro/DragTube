//
//  OpenRequest.swift
//  DragTube (shared by the app and the extension)
//
//  Clicking a video in the sheet opens it in the Safari tab you're using.
//  Only the extension can control Safari tabs, so the app (which owns the sheet)
//  leaves the video ID in a shared file and pings the extension with a Darwin
//  notification; the extension picks it up and navigates the current tab.
//

import Foundation
import notify

enum OpenRequest {
    static let notification = "org.raiymbek.DragTube.openInCurrentTab"

    private static var file: URL? {
        AppGroup.folder?.appendingPathComponent("open-request.txt")
    }

    // MARK: App side

    static func send(videoID: String) {
        guard let file else { return }
        try? Data(videoID.utf8).write(to: file, options: .atomic)
        notify_post(notification)
    }

    /// Withdraws the request if the extension hasn't taken it yet; true if it was still waiting
    static func cancelIfPending(videoID: String) -> Bool {
        guard let file, pendingID(in: file) == videoID else { return false }
        try? FileManager.default.removeItem(at: file)
        return true
    }

    // MARK: Extension side

    /// Returns the requested video ID (once) and clears the request
    static func take() -> String? {
        guard let file, let id = pendingID(in: file) else { return nil }
        try? FileManager.default.removeItem(at: file)
        return id
    }

    private static func pendingID(in file: URL) -> String? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let id = String(decoding: data, as: UTF8.self)
        return id.isEmpty ? nil : id
    }
}
