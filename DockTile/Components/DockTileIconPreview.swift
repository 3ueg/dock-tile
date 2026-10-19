//
//  DockTileIconPreview.swift
//  DockTile
//
//  Icon preview component with gradient background and symbol/emoji
//  Supports SF Symbols and Emojis with multiple sizes
//  Matches IconGenerator output exactly (no system effects like shadows)
//  Supports icon style-aware rendering (Default/Dark/Clear/Tinted)
//
//  Uses @ObservedObject with IconStyleManager for efficient updates
//  (single source of truth, no per-view polling)
//
//  Swift 6 - Strict Concurrency
//

import SwiftUI
import AppKit

struct DockTileIconPreview: View {
    let tintColor: TintColor
    let iconType: IconType
    let iconValue: String
    let iconScale: Int  // 10–19 symbols / 10–22 emoji, default 14
    let iconWeight: IconWeight  // SF Symbol stroke weight (ignored for emojis)
    /// Named `tileBackground`, not `background`: a stored `background` on a `View` collides with
    /// SwiftUI's `.background(_:)` modifier.
    let tileBackground: TileBackground
    let size: CGFloat

    /// Test-only override for the raw icon-style token. Production call sites never set this —
    /// they always fall through to the live `IconStyleManager.shared.rawStyle`. It exists because
    /// a render test needs to force the Automatic case (`.value("RegularAutomatic")`) regardless
    /// of whatever this machine's `AppleIconAppearanceTheme` key actually holds: only Automatic
    /// makes Light vs. Dark colorScheme produce different renders — an explicit style like
    /// ClearDark would legitimately render identically in both, discriminating nothing.
    var rawStyleOverride: RawStyleToken? = nil

    /// Pins the style (Customise's canonical Light/Dark previews); `nil` follows the live style.
    var forcedStyle: IconStyle? = nil

    /// Apps-face items (`[]` = glyph face). Only installed ones draw; none installed falls back
    /// to the glyph face.
    let appsFaceItems: [AppItem]

    @Environment(\.displayScale) private var displayScale

    // Observe IconStyleManager for icon style changes (single source of truth)
    @ObservedObject private var iconStyleManager = IconStyleManager.shared

    /// Light/Dark comes from the environment (live, system-driven); only the explicit
    /// Default/Dark/Clear/Tinted choice comes from the published raw token.
    @Environment(\.colorScheme) private var colorScheme

    /// Current icon style, resolved for display. `.defaultStyle` fallback: an unresolved raw
    /// token is an edge case with no established prior render to fall back to here.
    private var iconStyle: IconStyle {
        Self.displayStyle(forced: forcedStyle, raw: rawStyleOverride ?? iconStyleManager.rawStyle, colorScheme: colorScheme)
    }

    /// A forced style (Customise's canonical Light/Dark previews) wins; otherwise the live
    /// system style resolved against this view's colour scheme.
    nonisolated static func displayStyle(forced: IconStyle?, raw: RawStyleToken, colorScheme: ColorScheme) -> IconStyle {
        forced ?? IconStyle.forDisplay(raw: raw, colorScheme: colorScheme, fallback: .defaultStyle)
    }

    /// Copy of this preview pinned to `style` (`nil` = follow the live system style).
    func forcing(_ style: IconStyle?) -> Self {
        var copy = self
        copy.forcedStyle = style
        return copy
    }

    /// Whether we're in dark icon style
    private var isDarkStyle: Bool {
        iconStyle == .dark
    }

    // Legacy initializer for backward compatibility
    init(tintColor: TintColor, symbol: String, size: CGFloat) {
        self.tintColor = tintColor
        self.iconType = .emoji
        self.iconValue = symbol
        self.iconScale = ConfigurationDefaults.iconScale
        self.iconWeight = ConfigurationDefaults.iconWeight
        self.tileBackground = .colour
        self.size = size
        self.appsFaceItems = []
    }

    // New initializer with explicit icon type (legacy without scale)
    init(tintColor: TintColor, iconType: IconType, iconValue: String, size: CGFloat) {
        self.tintColor = tintColor
        self.iconType = iconType
        self.iconValue = iconValue
        self.iconScale = ConfigurationDefaults.iconScale
        self.iconWeight = ConfigurationDefaults.iconWeight
        self.tileBackground = .colour
        self.size = size
        self.appsFaceItems = []
    }

    // Full initializer with icon scale and weight
    init(
        tintColor: TintColor,
        iconType: IconType,
        iconValue: String,
        iconScale: Int,
        iconWeight: IconWeight = ConfigurationDefaults.iconWeight,
        background: TileBackground,
        size: CGFloat,
        appsFaceItems: [AppItem] = []
    ) {
        self.tintColor = tintColor
        self.iconType = iconType
        self.iconValue = iconValue
        self.iconScale = iconScale
        self.iconWeight = iconWeight
        self.tileBackground = background
        self.size = size
        self.appsFaceItems = appsFaceItems
    }

    /// Side of the drawn squircle — the FULL canvas, not the icon-grid-margined shape the
    /// compiled `.icon`/fallback `.icns` draw. Reversed 2026-09-02 (Task 6,
    /// docs/superpowers/plans/2026-09-02-appearance-environment.md): the icon-grid margin
    /// describes how the Dock composes an icon among its NEIGHBOURS — a UI slot (sidebar row,
    /// this hero preview, the editor canvas) has none, so the margin read as "shrunk" and sat
    /// inconsistently beside full-bleed `SettingsBadgeIcon` rows in the same sidebar list. The
    /// margin stays true where it IS true — the compiled car's own geometry and
    /// `IconGenerator.generateFallbackIcns` — this view just stops applying it.
    private var contentSide: CGFloat {
        size
    }

    private var cornerRadius: CGFloat {
        contentSide * 0.225  // same 22.5% of the SHAPE the baked renderer uses
    }

    private var symbolSize: CGFloat {
        // Shared seam handles the brand curve + SF-Symbol safe-area cap, so the preview and
        // the baked .icns pick identical glyph sizes (the inline copy here used to omit the cap).
        size * IconDepthMetrics.glyphSizeRatio(iconScale: iconScale, iconType: iconType, iconValue: iconValue)
    }

    /// Colors for the current icon style, from `TilePalette` via
    /// `colors(for:iconType:background:)` — the same seam the baked renderers use, so the preview
    /// and the Dock icon cannot drift. `iconType` and the tile's background both shape the result.
    private var styleColors: (backgroundTop: Color, backgroundBottom: Color, foreground: Color) {
        tintColor.colors(for: iconStyle, iconType: iconType, background: tileBackground)
    }

    // MARK: Depth treatment (mirrors IconGenerator via the shared seam)

    private var glyphShadow: IconDepthMetrics.GlyphShadow? {
        IconDepthMetrics.glyphShadow(style: iconStyle, iconType: iconType, nominalSize: size)
    }

    private var glyphBottomDarken: CGFloat? {
        IconDepthMetrics.glyphBottomDarken(style: iconStyle, iconType: iconType, nominalSize: size)
    }

    private var surfaceSheenAlpha: CGFloat {
        IconDepthMetrics.surfaceSheenAlpha(style: iconStyle, nominalSize: size)
    }

    /// Stroke width for the drawn shape. Measured against the frame-filling canvas (`contentSide`
    /// == `size` in this view — see its doc comment): the stroke is drawn ON the shape, and the
    /// baked renderer scales it by the size of what it strokes. (Glyph magnitudes stay
    /// canvas-relative — that is what both renderers use.)
    private var strokeLineWidth: CGFloat {
        IconDepthMetrics.strokeLineWidth(nominalSize: contentSide)
    }

    /// Liquid-Glass specular sheen for SF Symbols / brand glyph (nil for emoji / too small).
    private var glyphSheen: IconDepthMetrics.GlyphSheen? {
        IconDepthMetrics.glyphSheen(style: iconStyle, iconType: iconType, nominalSize: size)
    }

    /// Top→bottom shading fill for SF Symbols / brand glyph; flat foreground when suppressed.
    private var glyphForeground: AnyShapeStyle {
        if let darken = glyphBottomDarken {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [styleColors.foreground, styleColors.foreground.darkened(by: darken)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(styleColors.foreground)
    }

    /// Installed Apps-face items in tile order; empty means the glyph face draws.
    private var appsFaceMinis: [AppItem] {
        AppsFaceGrid.select(items: appsFaceItems) { AppInstallChecker.isInstalled($0) }.selected
    }

    @ViewBuilder
    var body: some View {
        let minis = appsFaceMinis
        if !minis.isEmpty {
            appsFaceBody(minis)
        } else {
            glyphFaceBody
        }
    }

    /// The Apps face: the app grid on the system glass grays. Light/Dark keys on `iconStyle`
    /// (`IconStyle.forDisplay`, like Mono), never raw `colorScheme`. The full frame is the shape
    /// (UI slots apply no icon-grid inset). Minis are `TileIconRasterCache` bitmaps, never the
    /// IconServices `NSImage`. The gray pair is the compiler's resolution of the system fills.
    private func appsFaceBody(_ minis: [AppItem]) -> some View {
        let grays = AppsFaceGrid.fillGrays(style: iconStyle)
        let desaturate = AppsFaceGrid.desaturatesMinis(style: iconStyle)
        let shadow = AppsFaceGrid.miniShadow(nominalSize: size)
        let frame = CGRect(x: 0, y: 0, width: size, height: size)
        let cells = AppsFaceGrid.cells(count: minis.count)
        let token = TileIconRasterCache.liveAppearanceToken(isDark: colorScheme == .dark)
        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(white: grays.top), Color(white: grays.bottom)],
                    startPoint: .top, endPoint: .bottom))
            ForEach(Array(minis.enumerated()), id: \.offset) { index, item in
                let box = AppsFaceGrid.rect(
                    AppsFaceGrid.drawBox(for: cells[index], isFolder: item.isFolder),
                    in: frame, yUp: false)
                if let cg = TileIconRasterCache.shared.image(
                    for: item, pointSize: box.width, scale: displayScale, appearanceToken: token,
                    contentStamp: TileIconRasterCache.contentStamp(
                        for: item, resolvedPath: AppInstallChecker.resolve(item).resolvedPath)
                ) {
                    Image(decorative: cg, scale: displayScale)
                        .resizable()
                        .saturation(desaturate ? 0 : 1)
                        .frame(width: box.width, height: box.height)
                        .shadow(color: shadow.map { Color.black.opacity($0.blackAlpha) } ?? .clear,
                                radius: shadow?.blur ?? 0, y: shadow?.offset ?? 0)
                        .position(x: box.midX, y: box.midY)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppStrings.Label.appsFaceAccessibility(minis.count))
    }

    private var glyphFaceBody: some View {
        ZStack {
            // The tile shape fills the frame (see `contentSide`'s doc comment) — no margin is
            // applied here. The GLYPH was already measured against the full canvas in both
            // renderers, so its geometry is unaffected by the shape now filling that same canvas.

            // Gradient background with squircle shape (icon style-aware)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [styleColors.backgroundTop, styleColors.backgroundBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Beveled glass effect (inner stroke) — opacity + width from the shared seam.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(IconDepthMetrics.strokeOpacity(style: iconStyle)),
                    lineWidth: strokeLineWidth
                )

            // Liquid-Glass surface sheen: soft top specular gloss, clipped to the squircle.
            // Kept as a stand-in for the system's Liquid Glass pass, which nothing outside the
            // real Dock can reproduce.
            if surfaceSheenAlpha > 0 {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(surfaceSheenAlpha), location: 0),
                                .init(color: .clear, location: IconDepthMetrics.surfaceSheenHeightFraction)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            // Icon content (SF Symbol or Emoji)
            iconContent
        }
        .frame(width: size, height: size)
        // NOTE: No outer drop shadow — the Dock adds that. The glyph's contact shadow below is
        // an inner lift effect (mirrors the baked .icns), not the tile's system shadow.
    }

    /// The bare glyph (brand image or SF Symbol) at the current size, filled with `style`.
    /// Reused for both the visible fill and as the mask for the specular sheen so the two
    /// can't diverge.
    @ViewBuilder
    private func glyphShape<S: ShapeStyle>(_ style: S) -> some View {
        if iconValue == SFSymbolCatalog.brandSymbolName, let logo = SFSymbolCatalog.brandGlyph {
            // The DockTile brand logo is a bundled template image, not a system symbol.
            Image(nsImage: logo)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: symbolSize, height: symbolSize)
                .foregroundStyle(style)
        } else {
            Image(systemName: iconValue)
                .font(.system(size: symbolSize, weight: iconWeight.fontWeight))
                .foregroundStyle(style)
        }
    }

    @ViewBuilder
    private var iconContent: some View {
        switch iconType {
        case .sfSymbol:
            // SF Symbol with icon style-aware fill + soft contact shadow (raised-on-glass),
            // topped by a Liquid-Glass specular sheen clipped to the glyph shape.
            glyphShape(glyphForeground)
                .overlay {
                    if let sheen = glyphSheen {
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(sheen.alpha), location: 0),
                                .init(color: .clear, location: sheen.heightFraction)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        // Mask the gloss to the glyph's own shape (colour is irrelevant to a mask).
                        .mask(glyphShape(Color.white))
                    }
                }
                .shadow(
                    color: glyphShadow.map { Color.black.opacity($0.blackAlpha) } ?? .clear,
                    radius: glyphShadow?.blur ?? 0,
                    y: glyphShadow?.offset ?? 0
                )

        case .emoji:
            // Emojis: "Sticker on Glass" metaphor — full colour + a subtle contact shadow in
            // every style (seam-driven), topped by a gentle glossy-sticker specular sheen.
            // Ink-normalised via the shared measurement + seam so the ARTWORK fills the
            // seam ratio and is optically centred — identical to the baked `.icns`.
            let fit = emojiInkFit
            let emojiFontSize = fit?.fontSize ?? symbolSize
            Text(iconValue)
                .font(.system(size: emojiFontSize))
                .overlay {
                    if let sheen = glyphSheen {
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(sheen.alpha), location: 0),
                                .init(color: .clear, location: sheen.heightFraction)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        // Mask the gloss to the emoji's silhouette (its rendered alpha).
                        .mask(Text(iconValue).font(.system(size: emojiFontSize)))
                    }
                }
                .shadow(
                    color: glyphShadow.map { Color.black.opacity($0.blackAlpha) } ?? .clear,
                    radius: glyphShadow?.blur ?? 0,
                    y: glyphShadow?.offset ?? 0
                )
                // Seam offset is y-up (AppKit drawing space); SwiftUI is y-down, so flip y.
                .offset(
                    x: -(fit?.inkCenterOffset.x ?? 0),
                    y: fit?.inkCenterOffset.y ?? 0
                )
        }
    }

    /// Ink-normalised emoji fit — the same measurement (`IconGenerator.emojiInkMetrics`) and
    /// seam arithmetic (`IconDepthMetrics.emojiInkFit`) the baked renderer uses, so the
    /// preview and the `.icns` cannot drift. Nil for non-emoji or unmeasurable glyphs.
    private var emojiInkFit: IconDepthMetrics.EmojiInkFit? {
        guard iconType == .emoji,
              let metrics = IconGenerator.emojiInkMetrics(for: iconValue) else { return nil }
        return IconDepthMetrics.emojiInkFit(
            tileSize: size,
            targetRatio: IconDepthMetrics.glyphSizeRatio(
                iconScale: iconScale, iconType: iconType, iconValue: iconValue
            ),
            inkPerPoint: metrics.ink,
            typographicSizePerPoint: metrics.typographicSize
        )
    }
}

// MARK: - Convenience Initializers

extension DockTileIconPreview {
    /// Create preview for Screen 3 (80×80pt) - Legacy emoji support
    static func small(tintColor: TintColor, symbol: String) -> DockTileIconPreview {
        DockTileIconPreview(tintColor: tintColor, symbol: symbol, size: 80)
    }

    /// Create preview for Screen 4 (160×160pt) - Legacy emoji support
    static func large(tintColor: TintColor, symbol: String) -> DockTileIconPreview {
        DockTileIconPreview(tintColor: tintColor, symbol: symbol, size: 160)
    }

    /// Create preview for Screen 3 (80×80pt)
    static func small(tintColor: TintColor, iconType: IconType, iconValue: String) -> DockTileIconPreview {
        DockTileIconPreview(tintColor: tintColor, iconType: iconType, iconValue: iconValue, size: 80)
    }

    /// Create preview for Screen 4 (160×160pt)
    static func large(tintColor: TintColor, iconType: IconType, iconValue: String) -> DockTileIconPreview {
        DockTileIconPreview(tintColor: tintColor, iconType: iconType, iconValue: iconValue, size: 160)
    }

    /// Create from a full configuration
    static func fromConfig(_ config: DockTileConfiguration, size: CGFloat) -> DockTileIconPreview {
        DockTileIconPreview(
            tintColor: config.tintColor,
            iconType: config.iconType,
            iconValue: config.iconValue,
            iconScale: config.iconScale,
            iconWeight: config.iconWeight,
            background: config.background,
            size: size,
            appsFaceItems: config.iconFace == .apps ? config.appItems : []
        )
    }
}

// MARK: - Tile Face (sidebar row, Tile Detail hero)

/// A tile as the app shows the tile itself. Under the Tinted icon style macOS recolours every
/// icon with a colour no public API exposes (it is not `controlAccentColor`), so our own drawing
/// can only show a grey stand-in (issue #22). Clear is the same case: macOS draws the tile as
/// light or dark glass with each layer remapped, which our grey stand-in does not match (an App
/// Grid tile showed a white plate in the app beside dark glass in the Dock). When the tile's
/// helper on disk was built from exactly this look, show the icon macOS renders for that helper
/// instead — the Dock's own render. Otherwise (Default/Dark, edits not yet applied with Update,
/// never added) draw it.
struct TileFace: View {
    let config: DockTileConfiguration
    let size: CGFloat

    @ObservedObject private var iconStyleManager = IconStyleManager.shared
    @Environment(\.colorScheme) private var colorScheme

    nonisolated static func showsSystemIcon(style: IconStyle, helperSignature: String?, tileSignature: String) -> Bool {
        (style == .tinted || style == .clear) && helperSignature == tileSignature
    }

    var body: some View {
        if let icon = systemIcon {
            // The system render carries the icon-grid margin; the tile drawing fills its frame,
            // so enlarge the render until its shape fills the same slot.
            let canvas = size / (1 - 2 * IconDepthMetrics.contentInsetRatio)
            Image(nsImage: icon)
                .resizable()
                .frame(width: canvas, height: canvas)
                .frame(width: size, height: size)
        } else {
            DockTileIconPreview.fromConfig(config, size: size)
        }
    }

    private var systemIcon: NSImage? {
        let style = IconStyle.forDisplay(raw: iconStyleManager.rawStyle, colorScheme: colorScheme, fallback: .defaultStyle)
        guard style == .tinted || style == .clear,   // the helper lookup scans a folder — only pay for it here
              let built = HelperBundleManager.shared.builtIconSignature(for: config),
              Self.showsSystemIcon(style: style, helperSignature: built.signature, tileSignature: config.iconSignature)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: built.path.path)
    }
}

// MARK: - Previews

#Preview("Default Style") {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            DockTileIconPreview(
                tintColor: .blue,
                iconType: .sfSymbol,
                iconValue: "star.fill",
                iconScale: 14,
                background: .colour,
                size: 80
            )
            DockTileIconPreview(
                tintColor: .orange,
                iconType: .sfSymbol,
                iconValue: "folder.fill",
                iconScale: 14,
                background: .colour,
                size: 80
            )
            DockTileIconPreview(
                tintColor: .purple,
                iconType: .emoji,
                iconValue: "🚀",
                iconScale: 14,
                background: .colour,
                size: 80
            )
        }

        HStack(spacing: 20) {
            DockTileIconPreview.small(tintColor: .orange, symbol: "🎨")
            DockTileIconPreview.small(tintColor: .red, symbol: "❤️")
            DockTileIconPreview.small(tintColor: .gray, symbol: "⚙️")
        }

        HStack(spacing: 20) {
            DockTileIconPreview.large(
                tintColor: .green,
                iconType: .sfSymbol,
                iconValue: "leaf.fill"
            )
            DockTileIconPreview.large(tintColor: .pink, symbol: "🚀")
        }

        DockTileIconPreview(
            tintColor: .blue,
            iconType: .sfSymbol,
            iconValue: "star.fill",
            iconScale: 18,
            background: .colour,
            size: 160
        )
    }
    .padding(60)
    .background(Color(hex: "#F5F5F7"))
}

#Preview("Dark Style Simulation") {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            DockTileIconPreview(
                tintColor: .blue,
                iconType: .sfSymbol,
                iconValue: "star.fill",
                iconScale: 14,
                background: .colour,
                size: 80
            )
            DockTileIconPreview(
                tintColor: .orange,
                iconType: .sfSymbol,
                iconValue: "folder.fill",
                iconScale: 14,
                background: .colour,
                size: 80
            )
            DockTileIconPreview(
                tintColor: .purple,
                iconType: .emoji,
                iconValue: "🚀",
                iconScale: 14,
                background: .colour,
                size: 80
            )
        }

        HStack(spacing: 20) {
            DockTileIconPreview.small(tintColor: .orange, symbol: "🎨")
            DockTileIconPreview.small(tintColor: .red, symbol: "❤️")
            DockTileIconPreview.small(tintColor: .gray, symbol: "⚙️")
        }

        HStack(spacing: 20) {
            DockTileIconPreview.large(
                tintColor: .green,
                iconType: .sfSymbol,
                iconValue: "leaf.fill"
            )
            DockTileIconPreview.large(tintColor: .pink, symbol: "🚀")
        }
    }
    .padding(60)
    .background(Color(hex: "#1C1C1E"))
    .preferredColorScheme(.dark)
}

#Preview("Mono") {
    HStack(spacing: 20) {
        ForEach([TileBackground.colour, .mono], id: \.self) { background in
            DockTileIconPreview(
                tintColor: .blue,
                iconType: .sfSymbol,
                iconValue: "star.fill",
                iconScale: 14,
                background: background,
                size: 80
            )
        }
    }
    .padding(60)
}
