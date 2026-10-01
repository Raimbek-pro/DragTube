//
//  SafariExtensionHandler.swift
//  DragTube Extension
//
//  Receives messages from script.js:
//    "save"      → save the video (shared storage, the app reads the same list)
//    "openSheet" → show the SwiftUI saved-videos sheet (keys 4/5/6)
//  The toolbar button opens the same sheet.
//

import SafariServices

class SafariExtensionHandler: SFSafariExtensionHandler {

    override func messageReceived(withName messageName: String,
                                  from page: SFSafariPage,
                                  userInfo: [String: Any]?) {
        switch messageName {

        case "save":
            guard let id = userInfo?["id"] as? String, !id.isEmpty else { return }
            let title = userInfo?["title"] as? String
            Task { @MainActor in
                VideoStore.shared.add(id: id, title: title)
            }

        case "openSheet":
            Task { @MainActor in
                _ = VideoStore.shared   // moves pre-App-Group saves into shared storage first
                AppBridge.openSheet()
            }

        default:
            break
        }
    }

    override func toolbarItemClicked(in window: SFSafariWindow) {
        Task { @MainActor in
            AppBridge.openSheet()
        }
    }

    override func validateToolbarItem(in window: SFSafariWindow,
                                      validationHandler: @escaping ((Bool, String) -> Void)) {
        validationHandler(true, "")
    }
}
