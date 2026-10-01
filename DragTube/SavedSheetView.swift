//
//  SavedSheetView.swift
//  DragTube
//
//  The saved-videos sheet docked to the bottom edge of the screen (keys 4/5/6 on YouTube).
//  Pure SwiftUI with Liquid Glass; SheetPanel only provides the window around it.
//

import SwiftUI
import AppKit
import Combine

/// Drives the slide-up / slide-down animation
@MainActor
final class SheetState: ObservableObject {
    @Published var isPresented = false
}

struct SavedSheetView: View {
    @ObservedObject var store = VideoStore.shared
    @ObservedObject var state: SheetState
    var onOpen: (SavedVideo) -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            if state.isPresented {
                sheet
                    .transition(.move(edge: .bottom))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .environment(\.colorScheme, .dark)
    }

    private static let cornerRadius: CGFloat = 28

    private var sheet: some View {
        // Docked to the screen's bottom edge: only the top corners are rounded
        let shape = UnevenRoundedRectangle(topLeadingRadius: Self.cornerRadius,
                                           topTrailingRadius: Self.cornerRadius,
                                           style: .continuous)

        return VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            header
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 14)

            if store.videos.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(shape)
        .glassEffect(.regular.tint(.black.opacity(0.18)), in: shape)          // Liquid Glass
        .background(BehindWindowBlur(topCornerRadius: Self.cornerRadius))     // blurred YouTube behind it
        .padding(.top, SheetPanel.topMargin)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Saved")
                .font(.system(size: 20, weight: .semibold))
            if !store.videos.isEmpty {
                Text("\(store.videos.count)")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !store.videos.isEmpty {
                Button("Clear All") {
                    withAnimation(.snappy) { store.clear() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.trailing, 6)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut(.cancelAction)        // Esc
            .help("Close (Esc)")
        }
    }

    // MARK: - Content

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 18, alignment: .top)],
                      alignment: .leading,
                      spacing: 22) {
                ForEach(store.videos) { video in
                    VideoCard(video: video,
                              onOpen: { onOpen(video) },
                              onRemove: { withAnimation(.snappy) { store.remove(video) } })
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing saved yet")
                .font(.system(size: 15, weight: .medium))
            Text("On YouTube, drag any video onto the drop zone.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
    }
}

// MARK: - Card

struct VideoCard: View {
    let video: SavedVideo
    var onOpen: () -> Void
    var onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                Text(video.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(video.addedAt, format: .relative(presentation: .named))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.15)) { hovering = isHovering }
        }
        .onTapGesture(perform: onOpen)          // opens in your current Safari tab
        .pointerStyle(.link)
    }

    private var thumbnail: some View {
        Color.white.opacity(0.06)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: video.thumbnail) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 22, height: 22)
                            .background(.black.opacity(0.65), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(8)
                    .help("Remove")
                    .transition(.opacity)
                }
            }
            .scaleEffect(hovering ? 1.025 : 1)
    }
}

// MARK: - Blur of what's behind the window

/// Frosted blur of the windows behind the sheet (YouTube in Safari), so the glass
/// stays readable. Masked to the sheet's shape: rounded top corners, square bottom.
struct BehindWindowBlur: NSViewRepresentable {
    var topCornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.maskImage = Self.mask(radius: topCornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    /// Stretchable mask: the corners keep their shape, the middle stretches
    private static func mask(radius r: CGFloat) -> NSImage {
        let side = r * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
            path.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: 0, endAngle: 90)
            path.appendArc(withCenter: NSPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: 90, endAngle: 180)
            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }
}
