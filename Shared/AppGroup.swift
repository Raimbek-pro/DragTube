//
//  AppGroup.swift
//  DragTube (shared by the app and the extension)
//
//  Storage both the DragTube app and the Safari extension can read and write.
//

import Foundation

enum AppGroup {
    static let id = "5BK3H6Y47F.org.raiymbek.DragTube"

    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }

    /// Shared folder (~/Library/Group Containers/<id>)
    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }
}
