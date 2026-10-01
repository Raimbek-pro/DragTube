//
//  AppDelegate.swift
//  DragTube
//
//  Created by Райымбек Омаров on 01.10.2026.
//
//  Two roles:
//  • Opened by you (Xcode, Finder, Dock): a normal app showing the "enable the extension" window.
//  • Opened by the extension (dragtube://saved, keys 4/5/6): a background helper with no Dock icon
//    that shows the saved-videos sheet and stays running so the next press is instant.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var setupWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Development hook: add -debugPresentSheet to the scheme's launch arguments
        // to open the sheet right away while working on its SwiftUI design
        if ProcessInfo.processInfo.arguments.contains("-debugPresentSheet") {
            SheetPanel.shared.present()
            return
        }
        #endif

        let launchedByUser = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        if launchedByUser {
            showSetupWindow()
        }
    }

    /// dragtube://saved — sent by the Safari extension (keys 4/5/6 or the toolbar button)
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "dragtube" }) else { return }
        SheetPanel.shared.present()
    }

    /// Opening the app again while it runs in the background shows the setup window
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSetupWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Quit when the setup window closes; as a background helper keep running
        return NSApp.activationPolicy() == .regular
    }

    private func showSetupWindow() {
        NSApp.setActivationPolicy(.regular)     // Dock icon + menu bar (Info.plist starts as LSUIElement)
        if setupWindowController == nil {
            setupWindowController = NSStoryboard(name: "Main", bundle: nil)
                .instantiateController(withIdentifier: "SetupWindow") as? NSWindowController
        }
        setupWindowController?.showWindow(nil)
        setupWindowController?.window?.orderFrontRegardless()   // still a UIElement this instant
        NSApp.activate()
    }
}
