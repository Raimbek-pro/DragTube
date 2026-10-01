//
//  SheetPanel.swift
//  DragTube
//
//  Borderless window docked to the bottom edge of the screen that hosts SavedSheetView.
//  It's a non-activating panel: Safari stays the active app, yet the sheet still
//  gets clicks. Pressing 4/5/6 again, Esc, or clicking anywhere else closes it.
//

import Cocoa
import SwiftUI

final class SheetPanel: NSPanel {

    static let shared = SheetPanel()

    /// Transparent space above the sheet so the glass edge highlight isn't clipped
    static let topMargin: CGFloat = 16

    private let state = SheetState()
    private var clickMonitor: Any?
    private var isClosing = false
    private var closingStartedAt = Date.distantPast

    private init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)   // above the Dock
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                   // the glass draws its own edges
        isReleasedWhenClosed = false
        animationBehavior = .none           // SwiftUI does the slide animation
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]   // works over full-screen Safari too

        contentView = NSHostingView(rootView: SavedSheetView(
            state: state,
            onOpen: { [weak self] video in self?.open(video) },
            onClose: { [weak self] in self?.dismiss() }
        ))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Show / hide

    func present() {
        trace("present: visible=\(isVisible) closing=\(isClosing) appActive=\(NSApp.isActive) policy=\(NSApp.activationPolicy().rawValue)")
        // Pressing the key again while the sheet is open closes it (toggle)
        if isVisible && !isClosing {
            dismiss("toggle")
            return
        }
        // That key press goes to Safari, which already pulled focus and started closing
        // the sheet a moment ago — don't bounce it back open
        if isClosing && Date().timeIntervalSince(closingStartedAt) < 0.6 {
            trace("ignored: already closing from the same key press")
            return
        }

        VideoStore.shared.reload()

        isClosing = false
        state.isPresented = false
        setFrame(Self.frameOnActiveScreen(), display: false)
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        trace("ordered front: key=\(isKeyWindow) onScreen=\(occlusionState.contains(.visible)) frame=\(frame)")
        startClickMonitor()

        // Next run-loop turn, so SwiftUI animates the sheet in from the bottom
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.4)) {        // no bounce: it stays flush with the edge
                self.state.isPresented = true
            }
        }
    }

    func dismiss(_ reason: String = "close") {
        trace("dismiss(\(reason)): visible=\(isVisible) closing=\(isClosing)")
        guard isVisible, !isClosing else { return }
        isClosing = true
        closingStartedAt = Date()
        stopClickMonitor()

        withAnimation(.easeIn(duration: 0.2)) {
            state.isPresented = false
        } completion: { [weak self] in
            guard let self, self.isClosing else { return }
            self.trace("ordered out")
            self.orderOut(nil)
            self.isClosing = false
        }
    }

    /// Flush with the bottom edge of the screen the mouse is on (covers the Dock while open)
    private static func frameOnActiveScreen() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.frame

        let width = min(area.width - 80, 1280)
        let sheetHeight = min(max(area.height * 0.5, 380), 620)

        return NSRect(x: area.midX - width / 2, y: area.minY, width: width, height: sheetHeight + topMargin)
    }

    // MARK: - Closing triggers

    override func becomeKey() {
        super.becomeKey()
        trace("became key")
    }

    override func resignKey() {
        super.resignKey()
        dismiss("resignKey")
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss("Esc")
    }

    /// 4, 5, 6 on the number row or keypad (physical keys, any layout)
    private static let sheetKeyCodes: Set<UInt16> = [21, 23, 22, 86, 87, 88]

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])

        if event.keyCode == 53 || (Self.sheetKeyCodes.contains(event.keyCode) && mods.isEmpty) {   // Esc, or 4/5/6 again
            dismiss("key")
        } else {
            super.keyDown(with: event)
        }
    }

    /// Clicks in other apps (e.g. back in Safari) close the sheet
    private func startClickMonitor() {
        stopClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.dismiss("click outside")
        }
    }

    private func stopClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    // MARK: - Opening a video

    /// Opens the video in the Safari tab you're using (the extension does the navigating)
    private func open(_ video: SavedVideo) {
        dismiss()
        OpenRequest.send(videoID: video.id)

        // Extension didn't pick it up (e.g. Safari restarted it) → open in a new Safari tab instead
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if OpenRequest.cancelIfPending(videoID: video.id) {
                Self.openInNewSafariTab(video.url)
            }
        }
    }

    private static func openInNewSafariTab(_ url: URL) {
        let workspace = NSWorkspace.shared
        if let safari = workspace.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
            workspace.open([url], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.open(url)
        }
    }

    // MARK: - Debugging

    /// Recent panel events while developing: ~/Library/Group Containers/5BK3H6Y47F.org.raiymbek.DragTube/sheet-debug.log
    private func trace(_ event: String) {
        #if DEBUG
        guard let file = AppGroup.folder?.appendingPathComponent("sheet-debug.log") else { return }
        let time = Date().formatted(.dateTime.hour().minute().second().secondFraction(.fractional(2)))
        let line = Data("\(time) [\(ProcessInfo.processInfo.processIdentifier)] \(event)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: file)
        }
        #endif
    }
}
