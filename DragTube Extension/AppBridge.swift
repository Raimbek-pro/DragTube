//
//  AppBridge.swift
//  DragTube Extension
//
//  Talks to the DragTube app, which owns the SwiftUI saved-videos sheet
//  (Safari extensions can't show their own floating windows):
//    extension → app: "show the sheet"            (dragtube://saved)
//    app → extension: "open this video in the current tab"   (OpenRequest)
//

import AppKit
import SafariServices
import notify

enum AppBridge {

    static func openSheet() {
        listenForOpenRequests()             // so a click in the sheet can come back to this tab

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false            // Safari stays the active app; the sheet floats above it

        NSWorkspace.shared.open(URL(string: "dragtube://saved")!, configuration: config) { _, error in
            trace(error.map { "open sheet failed: \($0.localizedDescription)" } ?? "opened sheet")
        }
    }

    // MARK: - Video clicked in the sheet → open in the current Safari tab

    private static var listenToken: Int32 = 0
    private static var isListening = false
    private static let queue = DispatchQueue(label: "org.raiymbek.DragTube.openRequests")

    private static func listenForOpenRequests() {
        guard !isListening else { return }
        isListening = true
        notify_register_dispatch(OpenRequest.notification, &listenToken, queue) { _ in
            guard let id = OpenRequest.take() else { return }
            openInCurrentTab(SavedVideo.watchURL(for: id))
        }
    }

    private static func openInCurrentTab(_ url: URL) {
        SFSafariApplication.getActiveWindow { window in
            guard let window else { return trace("no Safari window") }
            window.getActiveTab { tab in
                if let tab {
                    tab.navigate(to: url)
                    trace("opened in current tab")
                } else {
                    window.openTab(with: url, makeActiveIfPossible: true)
                    trace("opened in new tab (no active tab)")
                }
            }
        }
    }

    // MARK: - Debugging

    /// Last result, readable from Terminal while developing:
    /// defaults read ~/Library/Group\ Containers/5BK3H6Y47F.org.raiymbek.DragTube/Library/Preferences/5BK3H6Y47F.org.raiymbek.DragTube.plist debugBridge
    private static func trace(_ message: String) {
        AppGroup.defaults.set("\(Date()) \(message)", forKey: "debugBridge")
    }
}
