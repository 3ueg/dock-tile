//
//  NativeBackgroundViews.swift
//  DockTile
//
//  Shared NSViewRepresentable wrappers for native AppKit background colors.
//  Uses layer-backed NSViews for reliable color rendering in SwiftUI.
//  Swift 6 - Strict Concurrency
//

import AppKit
import SwiftUI

/// Generic NSColor background view using layer-backed NSView.
///
/// **Why NSViewRepresentable instead of SwiftUI `Color(nsColor:)`?**
/// SwiftUI's `Color(nsColor:)` initializer doesn't reliably bridge all AppKit dynamic colors
/// (e.g., `.windowBackgroundColor`, `.quaternarySystemFill`). These colors adapt to appearance
/// changes (light/dark mode) at the AppKit layer, but SwiftUI may not pick up the change.
/// Using a layer-backed NSView with direct `cgColor` assignment ensures correct rendering.
struct NSColorBackgroundView: NSViewRepresentable {
    let color: () -> NSColor

    init(_ color: @escaping @autoclosure () -> NSColor) {
        self.color = color
    }

    func makeNSView(context: Context) -> AppearanceColorView {
        AppearanceColorView(color: color())
    }

    func updateNSView(_ nsView: AppearanceColorView, context: Context) {
        nsView.color = color()
    }
}

/// A layer-backed view whose background is a DYNAMIC `NSColor`, re-resolved for the view's own
/// effective appearance on every appearance change. `NSColor.cgColor` resolves a dynamic colour
/// once, for whatever appearance is current at that moment; assigning it to `layer.backgroundColor`
/// in `makeNSView` / `updateNSView` froze it — a view built in Dark Mode stayed dark after the
/// system switched to Light, because SwiftUI does not call `updateNSView` for an appearance change
/// (the Customise Tile inspector, 2026-10-21). Guarded by `AppearanceColorViewTests`.
final class AppearanceColorView: NSView {
    var color: NSColor {
        didSet { needsDisplay = true }
    }

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = color.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - Convenience Initializers

extension NSColorBackgroundView {
    /// Form group background using quaternarySystemFill
    static var formGroup: NSColorBackgroundView {
        NSColorBackgroundView(NSColor.quaternarySystemFill)
    }

    /// Window background color
    static var windowBackground: NSColorBackgroundView {
        NSColorBackgroundView(NSColor.windowBackgroundColor)
    }

    /// A card ON the sidebar glass (the Customise Tile inspector): translucent white, 50% in Light
    /// and 8% in Dark, so the card sits a step LIGHTER than the glass in both appearances and the
    /// glass's desktop tint still shows through. `formGroup` (quaternarySystemFill) is for cards on
    /// an opaque page: on the glass it read darker than the surface in Light and lighter in Dark
    /// (compared on the real inspector glass, macOS 27, 2026-10-21).
    static var inspectorCard: NSColorBackgroundView {
        NSColorBackgroundView(inspectorCardColor)
    }

    static let inspectorCardColor = NSColor(name: "inspectorCard") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.white.withAlphaComponent(0.5)
    }
}

// MARK: - Studio Canvas Background

/// The "studio canvas" backdrop used behind a live preview hero — a vibrant, semi-transparent
/// frosted surface (`underWindowBackground`). Shared by the Customise-Tile icon studio and the
/// Popover Appearance preview so both hero previews sit on the identical treatment.
///
/// `behindWindow` lets the desktop bleed through for the Liquid Glass look; `active` keeps the
/// vibrancy alive even when the app isn't frontmost (otherwise it flattens to grey).
struct StudioCanvasBackgroundView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
