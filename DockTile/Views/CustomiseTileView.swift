//
//  CustomiseTileView.swift
//  DockTile
//
//  Customise Tile: a live canvas beside a 260 pt inspector. The inspector opens with the Style
//  picker (App Grid · Symbol · Emoji); Symbol and Emoji carry the Background, Colour, Icon Size
//  and picker controls, App Grid has none. Design: docs/design_handoff_customise_tile/.
//  Swift 6 - Strict Concurrency
//

import SwiftUI
import AppKit

struct CustomiseTileView: View {
    @EnvironmentObject private var configManager: ConfigurationManager
    let config: DockTileConfiguration
    let onBack: () -> Void

    @State private var editedConfig: DockTileConfiguration
    @State private var customColor: Color = .blue
    @State private var searchText: String = ""
    @State private var showWeightInfo: Bool = false
    /// Monotonic edit counter — the `.task(id:)` identity for the debounced save (same pattern as
    /// DockTileDetailView), so each edit CANCELS the previous pending save.
    @State private var saveGeneration: Int = 0
    @State private var hasPendingSave = false

    init(config: DockTileConfiguration, onBack: @escaping () -> Void) {
        self.config = config
        self.onBack = onBack
        self._editedConfig = State(initialValue: config)
    }

    var body: some View {
        // One gutter on both sides of the canvas: sidebar→canvas and canvas→inspector are both 10 pt.
        HStack(alignment: .top, spacing: Self.paneGutter) {
            canvas
            inspector
        }
        .padding(.leading, Self.paneGutter)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NSColorBackgroundView.windowBackground)
        .onChange(of: editedConfig) { oldValue, newValue in
            // Mark as edited immediately (enables + button)
            // Defer to avoid "Publishing changes from within view updates" warning
            DispatchQueue.main.async {
                configManager.markSelectedConfigAsEdited()
            }

            // Only save if the config actually changed (prevent infinite loop)
            if oldValue.id == newValue.id {
                hasPendingSave = true
                saveGeneration += 1
            }
        }
        .task(id: saveGeneration) {
            guard saveGeneration > 0 else { return }
            guard await SaveDebounce.waitedFullInterval(nanoseconds: 300_000_000) else { return }
            persistEdits()
        }
        .onDisappear {
            // Back within the debounce window cancels the task above; flush so the edit survives.
            if hasPendingSave {
                persistEdits()
            }
        }
        // Per-control diagnostics. Colour and size change continuously (colour-panel drag /
        // stepper repeat) so they're verbose; icon selection is a discrete click.
        .onChange(of: editedConfig.tintColor) { _, newValue in
            DiagnosticsLog.shared.log("tile", "Colour changed for \(editedConfig.diagnosticName) → \(newValue)", verbose: true)
        }
        .onChange(of: editedConfig.background) { _, newValue in
            DiagnosticsLog.shared.ui("Customise → Background \(newValue.rawValue) for '\(editedConfig.name)'")
        }
        .onChange(of: editedConfig.iconScale) { _, newValue in
            DiagnosticsLog.shared.log("tile", "Icon size changed to \(newValue) for \(editedConfig.diagnosticName)", verbose: true)
        }
        .onChange(of: editedConfig.iconValue) { _, newValue in
            DiagnosticsLog.shared.log("tile", "Icon changed to \(editedConfig.iconType == .emoji ? "emoji" : "symbol") '\(newValue)' for \(editedConfig.diagnosticName)")
        }
        .onChange(of: editedConfig.iconWeight) { _, newValue in
            DiagnosticsLog.shared.ui("Customise → Icon weight \(newValue.rawValue) for '\(editedConfig.name)'")
        }
        .onChange(of: editedConfig.iconFace) { _, newValue in
            DiagnosticsLog.shared.log("tile", "Face changed to \(newValue.rawValue) for \(editedConfig.diagnosticName)")
        }
        .onChange(of: selectedStyle) { _, _ in
            // A query typed for symbols means nothing to the emoji grid.
            searchText = ""
        }
    }

    // MARK: - Seams

    /// The three Style cards. The face decides first (App Grid), then the glyph's type.
    enum TileStyle: CaseIterable, Equatable {
        case apps, symbol, emoji

        init(face: IconFace, iconType: IconType) {
            switch face {
            case .apps: self = .apps
            case .glyph: self = iconType == .emoji ? .emoji : .symbol
            }
        }

        var label: String {
            switch self {
            case .apps: return AppStrings.Label.styleAppPreview
            case .symbol: return AppStrings.Tab.symbol
            case .emoji: return AppStrings.Tab.emoji
            }
        }
    }

    /// What a Style card tap does to the tile. App Grid only switches the face, so the glyph
    /// behind it survives a round trip. Symbol/Emoji keep the current glyph when it is already of
    /// that type. Otherwise the outgoing glyph and its settings (size, Colour/Mono background, tile
    /// colour) are saved (`savedSymbol` / `savedEmoji`) and the incoming type's are restored, so
    /// switching never loses a choice; with nothing saved yet the default glyph is seeded and the
    /// settings carry over. `symbolEmoji` (legacy) mirrors `iconValue`.
    nonisolated static func applyStyle(_ style: TileStyle, to config: DockTileConfiguration) -> DockTileConfiguration {
        var result = config
        let outgoing = SavedGlyph(value: config.iconValue, scale: config.iconScale,
                                  background: config.background, tint: config.tintColor)
        switch style {
        case .apps:
            result.iconFace = .apps
            return result
        case .symbol:
            result.iconFace = .glyph
            guard config.iconType != .sfSymbol else { return result }
            result.savedEmoji = outgoing
            result.iconType = .sfSymbol
            restore(config.savedSymbol, orDefault: ConfigurationDefaults.iconValue, into: &result)
        case .emoji:
            result.iconFace = .glyph
            guard config.iconType != .emoji else { return result }
            result.savedSymbol = outgoing
            result.iconType = .emoji
            restore(config.savedEmoji, orDefault: ConfigurationDefaults.symbolEmoji, into: &result)
        }
        return result
    }

    private nonisolated static func restore(_ saved: SavedGlyph?, orDefault value: String,
                                            into config: inout DockTileConfiguration) {
        config.iconValue = saved?.value ?? value
        if let saved { config.iconScale = saved.scale }
        if let background = saved?.background { config.background = background }
        if let tint = saved?.tint { config.tintColor = tint }
        config.symbolEmoji = config.iconValue
    }

    enum InspectorSection: Equatable {
        case stylePicker, apps, background, colour, iconSize, iconWeight, picker
    }

    /// Which inspector groups show, in order. App Grid has no knobs. Mono + Emoji HIDES the
    /// Colour card (an emoji can't take a colour); `tintColor` is kept, so switching back to a
    /// symbol restores it.
    nonisolated static func inspectorSections(face: IconFace, background: TileBackground, iconType: IconType) -> [InspectorSection] {
        guard face == .glyph else { return [.stylePicker, .apps] }
        var sections: [InspectorSection] = [.stylePicker, .background]
        if !colourRowState(background: background, iconType: iconType, fillDeepened: false).isDisabled {
            sections.append(.colour)
        }
        sections.append(.iconSize)
        if iconType == .sfSymbol { sections.append(.iconWeight) }
        sections.append(.picker)
        return sections
    }

    struct AppsSummary: Equatable {
        let shown: String
        let arrangement: String
        let note: String
    }

    /// The Apps card's two values and its caption, for `count` items in the tile.
    nonisolated static func appsSummary(count: Int) -> AppsSummary {
        let shown = AppStrings.Label.appsShownValue(min(count, AppsFaceGrid.maxItems), count)
        guard count > 0 else {
            // An em dash, not copy: nothing is arranged yet.
            return AppsSummary(shown: shown, arrangement: "—", note: AppStrings.Label.appsNoteNone)
        }
        let arrangement: String
        switch AppsFaceGrid.columns(count: count) {
        case 1: arrangement = AppStrings.Label.appsArrangementFills
        case 2: arrangement = AppStrings.Label.appsArrangementTwoByTwo
        default: arrangement = AppStrings.Label.appsArrangementThreeByThree
        }
        let note: String
        switch count {
        case 1: note = AppStrings.Label.appsNoteOne
        case ...AppsFaceGrid.maxItems: note = AppStrings.Label.appsNoteAll(count)
        default: note = AppStrings.Label.appsNoteFirstNine(count)
        }
        return AppsSummary(shown: shown, arrangement: arrangement, note: note)
    }

    /// The Apps card for the items the face actually draws: missing items are skipped, exactly as
    /// `AppsFaceGrid.select` skips them for the preview and the helper bake.
    nonisolated static func appsSummary(items: [AppItem], isInstalled: (AppItem) -> Bool) -> AppsSummary {
        appsSummary(count: items.count - AppsFaceGrid.select(items: items, isInstalled: isInstalled).skipped)
    }

    enum ColourRowState: Equatable {
        case fillsTile, deepened, toned, emojiLocked
        var isDisabled: Bool { self == .emojiLocked }
        var usesSymbolLabel: Bool { self == .toned || self == .emojiLocked }
    }

    /// Colour card copy. Mono + emoji is the locked state (the card is hidden — see
    /// `inspectorSections`) but never resets `tintColor`.
    nonisolated static func colourRowState(background: TileBackground, iconType: IconType, fillDeepened: Bool) -> ColourRowState {
        switch background {
        case .mono: return iconType == .emoji ? .emojiLocked : .toned
        // The "Deepened … so the symbol stays clear" copy names a symbol; an emoji tile has none.
        case .colour: return (fillDeepened && iconType == .sfSymbol) ? .deepened : .fillsTile
        }
    }

    /// Which hero previews Customise shows. The Apps face is one live hero. A Mono glyph follows
    /// Light/Dark only where the tile's icon is compiled per appearance (macOS 26+,
    /// `IconPipeline.isDeclarative`); the macOS 15 legacy bake always shows the light variant
    /// (there is no icon-style setting to follow), so the screen must not promise a black tile
    /// there. `nil` = follow the live style.
    nonisolated static func heroStyles(background: TileBackground, followsAppearance: Bool, iconFace: IconFace) -> [IconStyle?] {
        guard iconFace == .glyph else { return [nil] }
        switch background {
        case .colour: return [nil]
        case .mono: return followsAppearance ? [.defaultStyle, .dark] : [.defaultStyle]
        }
    }

    /// The one place the Mono presentation forks on OS: true where Mono really is white-or-black.
    private var monoFollowsAppearance: Bool { IconPipeline.isDeclarative }

    private var selectedStyle: TileStyle {
        TileStyle(face: editedConfig.iconFace, iconType: editedConfig.iconType)
    }

    private var colourRow: ColourRowState {
        Self.colourRowState(background: editedConfig.background, iconType: editedConfig.iconType,
                            fillDeepened: TilePalette.fillWasDeepened(tint: editedConfig.tintColor))
    }

    // MARK: - Actions

    /// Persist the customiser's content edits (tint, icon, scale, weight). Visibility is owned
    /// EXCLUSIVELY by `DockTileDetailView.performDockAction()`, so this saves through
    /// `preservingStoredVisibility` — the same seam Tile Detail uses. Writing the raw snapshot
    /// re-asserted whatever `isVisibleInDock` / `lastDockIndex` were when Customise opened, which
    /// silently reverts a `syncDockVisibility()` that landed meanwhile (the user dragging the tile
    /// out of the Dock mid-session) and leaves the config claiming visible with nothing pinned.
    private func persistEdits() {
        configManager.updateConfiguration(ConfigurationManager.preservingStoredVisibility(
            editedConfig, stored: configManager.configuration(for: editedConfig.id)))
        hasPendingSave = false
    }

    private func selectIcon(_ value: String, type: IconType) {
        editedConfig.iconType = type
        editedConfig.iconValue = value
        editedConfig.symbolEmoji = value  // Keep legacy field in sync
    }

    // MARK: - Canvas

    /// Top inset shared by the canvas and the inspector, so both columns start on one line under
    /// the transparent toolbar strip (they run up into it, using that space).
    private static let paneTopInset: CGFloat = 10
    /// The gap on each side of the canvas (sidebar→canvas and canvas→inspector).
    private static let paneGutter: CGFloat = 10

    /// Inset of the "Select Apps" pill from the canvas card's top and leading edges.
    private static let pillInset: CGFloat = 12

    private var canvas: some View {
        let styles = Self.heroStyles(background: editedConfig.background, followsAppearance: monoFollowsAppearance,
                                     iconFace: editedConfig.iconFace)
        return canvasSurface(styles)
            .overlay(alignment: .topLeading) {
                selectAppsPill
                    .padding(Self.pillInset)
            }
            .padding(.top, Self.paneTopInset)
            .ignoresSafeArea(edges: .top)
            // 200, not the handoff's 250: a 280 pt sidebar in a 782 pt window leaves ~502 pt for the pane.
            .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectAppsPill: some View {
        Button {
            DiagnosticsLog.shared.ui("Customise → Select Apps (back to Tile Detail)")
            onBack()
        } label: {
            Label(AppStrings.Button.selectApps, systemImage: "chevron.left")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(GlassCapsule())
    }

    private func canvasSurface(_ styles: [IconStyle?]) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Group {
            if styles.count > 1 {
                VStack(spacing: 0) {
                    ForEach(Array(styles.enumerated()), id: \.offset) { _, style in
                        pairHalf(style: style)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    heroTile(style: styles.first ?? nil, size: 100)
                    Text(configManager.displayName(for: editedConfig.id))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StudioCanvasBackgroundView())
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color(nsColor: .quinaryLabel), lineWidth: 0.5))
    }

    /// One half of the Mono Light / Dark pair. The style is forced (canonical Default/Dark,
    /// whatever the user's system icon style) so the pair always explains what Mono means.
    @ViewBuilder
    private func pairHalf(style: IconStyle?) -> some View {
        if style == .dark {
            VStack(spacing: 10) {
                heroTile(style: style, size: 88)
                pairCaption(AppStrings.Label.previewDark, symbol: "moon")
                    .environment(\.colorScheme, .dark)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.11)],
                                       startPoint: .top, endPoint: .bottom))
        } else {
            VStack(spacing: 10) {
                heroTile(style: style, size: 88)
                pairCaption(AppStrings.Label.previewLight, symbol: "sun.max")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StudioCanvasBackgroundView())
        }
    }

    private func pairCaption(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
    }

    /// The tile as it will look; the icon-grid overlay guides glyph placement only, so it never
    /// draws on the Apps face.
    private func heroTile(style: IconStyle?, size: CGFloat) -> some View {
        ZStack {
            DockTileIconPreview.fromConfig(editedConfig, size: size)
                .forcing(style)
            if editedConfig.iconFace == .glyph {
                if editedConfig.background == .mono {
                    IconGridOverlay(size: size, lineColor: style == .dark ? .white.opacity(0.25) : .black.opacity(0.15))
                } else {
                    IconGridOverlay(size: size, backgroundColor: editedConfig.tintColor)
                }
            }
        }
    }

    // MARK: - Inspector

    /// The inspector itself never scrolls: it starts at the top of the window (the Style cards use
    /// the band beside the toolbar's "Select Apps") and only the symbol/emoji grid scrolls, inside
    /// its own card, so the controls above it stay put.
    private var inspector: some View {
        let sections = Self.inspectorSections(face: editedConfig.iconFace, background: editedConfig.background,
                                              iconType: editedConfig.iconType)
        return VStack(alignment: .leading, spacing: 16) {
            if sections.contains(.stylePicker) { stylePicker }
            if sections.contains(.apps) { appsSection }
            if sections.contains(.background) { backgroundSection }
            if sections.contains(.colour) { colourSection }
            if sections.contains(.iconSize) { iconSizeCard(showsWeight: sections.contains(.iconWeight)) }
            if sections.contains(.picker) {
                pickerSection
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.top, Self.paneTopInset)
        .padding(.trailing, 12)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }

    // Inspector metrics follow Icon Composer's inspector (measured from a 2× screenshot,
    // 2026-10-19): 11 pt semibold secondary section headers ~10 pt in from the card edge and ~6 pt
    // above it; 36 pt rows with a 13 pt label (no leading symbol); outline-less cards whose
    // dividers are inset 10 pt from both edges.
    private static let headerInset: CGFloat = 10
    private static let headerToCard: CGFloat = 6
    private static let rowHeight: CGFloat = 36
    private static let rowPadding: CGFloat = 14

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Self.headerInset)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Self.headerInset)
    }

    private var cardHairline: some View {
        Rectangle()
            .fill(Color(nsColor: .quinaryLabel))
            .frame(height: 0.5)
            .padding(.horizontal, Self.headerInset)
    }

    /// One inspector row: the 13 pt label, then `content` — which places its own `Spacer` so a row
    /// can keep an accessory beside the label. No leading symbol (owner's call, 2026-10-19).
    private func inspectorRow<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)   // the label wins over a wide control (Icon Weight truncated)
            content()
        }
        .padding(.horizontal, Self.rowPadding)
        .frame(minHeight: Self.rowHeight)
    }

    // MARK: Style picker

    private var stylePicker: some View {
        HStack(spacing: 10) {
            ForEach(TileStyle.allCases, id: \.self) { style in
                styleCard(style)
            }
        }
    }

    /// One Style card: a mini tile rendered in that style from the tile's CURRENT settings.
    private func styleCard(_ style: TileStyle) -> some View {
        let isSelected = selectedStyle == style
        let styled = Self.applyStyle(style, to: editedConfig)
        return Button {
            DiagnosticsLog.shared.ui("Customise → Style '\(style)'")
            editedConfig = styled
        } label: {
            VStack(spacing: 7) {
                DockTileIconPreview(
                    tintColor: styled.tintColor,
                    iconType: styled.iconType,
                    iconValue: styled.iconValue,
                    iconScale: styled.iconScale,
                    iconWeight: styled.iconWeight,
                    background: styled.background,
                    size: 32,
                    appsFaceItems: style == .apps ? editedConfig.appItems : []
                )
                Text(style.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .padding(.horizontal, 2)
            .modifier(InspectorCard(isSelected: isSelected))
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.system(size: 16))
                        .padding(6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Apps

    private var appsSection: some View {
        let summary = Self.appsSummary(items: editedConfig.appItems) { AppInstallChecker.isInstalled($0) }
        return VStack(alignment: .leading, spacing: Self.headerToCard) {
            groupHeader(AppStrings.Label.appsHeader)
            VStack(spacing: 0) {
                valueRow(AppStrings.Label.appsShown, value: summary.shown)
                cardHairline
                valueRow(AppStrings.Label.appsArrangement, value: summary.arrangement)
            }
            .modifier(InspectorCard())
            caption(Self.appsCaption(note: summary.note, followsAppearance: monoFollowsAppearance))
        }
    }

    /// The glass sentence promises Light/Dark, so it is shown only where the compiled icon follows
    /// the appearance (macOS 15's legacy bake is always the light variant).
    nonisolated static func appsCaption(note: String, followsAppearance: Bool) -> String {
        followsAppearance ? note + " " + AppStrings.Label.appsGlass : note
    }

    private func valueRow(_ title: String, value: String) -> some View {
        inspectorRow(title) {
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: Background

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: Self.headerToCard) {
            groupHeader(AppStrings.Label.background)
            HStack(spacing: 8) {
                ForEach(TileBackground.allCases, id: \.self) { option in
                    BackgroundChip(option: option, config: editedConfig, isSelected: editedConfig.background == option,
                                   followsAppearance: monoFollowsAppearance) {
                        editedConfig.background = option
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                caption(backgroundHint)
                // Mono + Emoji: says why the Colour card is gone. Its own line — the Mono hint
                // carries no full stop, so appending would run the two sentences together.
                if editedConfig.background == .mono && editedConfig.iconType == .emoji {
                    caption(AppStrings.Label.backgroundHintEmojiColours)
                }
            }
        }
    }

    private var backgroundHint: String {
        switch editedConfig.background {
        case .colour: return AppStrings.Label.backgroundHintColour
        case .mono: return monoFollowsAppearance ? AppStrings.Label.backgroundHintMono : AppStrings.Label.backgroundHintMonoStatic
        }
    }

    // MARK: Colour

    private var colourSection: some View {
        let state = colourRow
        return VStack(alignment: .leading, spacing: Self.headerToCard) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                groupHeader(state.usesSymbolLabel ? AppStrings.Label.symbolColour : AppStrings.Label.tileColour)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                // Trailing header note, like Icon Composer's "All" scope control beside its headers.
                Text(colourCaption(state))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .padding(.trailing, Self.headerInset)
            }
            colourPickerStrip
                .padding(.horizontal, Self.rowPadding)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(InspectorCard())
        }
    }

    private func colourCaption(_ state: ColourRowState) -> String {
        switch state {
        case .fillsTile: return AppStrings.Label.colourHintFills
        case .deepened: return AppStrings.Label.colourHintDeepened
        case .toned, .emojiLocked: return AppStrings.Label.colourHintTints
        }
    }

    private var colourPickerStrip: some View {
        HStack(spacing: 6) {
            // Preset colors
            ForEach(TintColor.PresetColor.allCases, id: \.self) { preset in
                ColorSwatchButton(
                    color: preset.colorBottom,
                    isSelected: isPresetSelected(preset),
                    size: 20
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        editedConfig.tintColor = .preset(preset)
                    }
                }
            }

            // Custom color picker styled as "+" button
            CustomColorPickerButton(
                selectedColor: $customColor,
                isSelected: isCustomColorSelected,
                size: 20
            ) { newColor in
                let hexString = newColor.toHexString()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    editedConfig.tintColor = .custom(hexString)
                }
            }
        }
    }

    private var isCustomColorSelected: Bool {
        if case .custom = editedConfig.tintColor {
            return true
        }
        return false
    }

    private func isPresetSelected(_ preset: TintColor.PresetColor) -> Bool {
        if case .preset(let currentPreset) = editedConfig.tintColor {
            return currentPreset == preset
        }
        return false
    }

    // MARK: Icon Size / Icon Weight

    /// Maximum allowed scale value (keeps icon within its type's safe area)
    private var maxIconScale: Int {
        // Symbols step to 19 (clamped at IconDepthMetrics.maxSafeRatio, 0.60). Emoji step to
        // their own bound under their own ceiling (emojiMaxSafeRatio) — and because emoji are
        // ink-normalised (emojiInkFit), the ratio bounds the measured artwork, so every emoji
        // stays inside the tile shape at every step.
        editedConfig.iconType == .emoji ? IconDepthMetrics.emojiScaleMax : 19
    }

    private func iconSizeCard(showsWeight: Bool) -> some View {
        VStack(spacing: 0) {
            inspectorRow(AppStrings.Label.iconSize) {
                Spacer(minLength: 8)
                Stepper(value: $editedConfig.iconScale, in: 10...maxIconScale) {
                    Text("\(editedConfig.iconScale)")
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if showsWeight {
                cardHairline
                inspectorRow(AppStrings.Label.iconWeight) {
                    // Its own tight stack: with the row's 8 pt gaps around the info button and a
                    // spacer, the label truncated to "Icon We…" in the 260 pt inspector.
                    HStack(spacing: 4) {
                        iconWeightInfoButton
                        Spacer(minLength: 0)
                        iconWeightPicker
                    }
                }
            }
        }
        .modifier(InspectorCard())
    }

    /// Small info affordance next to the Icon Weight label. Click reveals a popover
    /// explaining the setting's scope (Apple's pattern for a note too minor for a
    /// persistent subtitle); hover shows the same text as a help tag for accessibility.
    private var iconWeightInfoButton: some View {
        Button {
            showWeightInfo.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(AppStrings.Label.iconWeightInfo)
        .accessibilityLabel(AppStrings.Label.iconWeightInfoAccessibility)
        .popover(isPresented: $showWeightInfo, arrowEdge: .bottom) {
            Text(AppStrings.Label.iconWeightInfo)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 220, alignment: .leading)
                .padding(12)
        }
    }

    /// Native macOS pull-down (pop-up button) for choosing the SF Symbol weight.
    private var iconWeightPicker: some View {
        Picker("", selection: $editedConfig.iconWeight) {
            ForEach(IconWeight.allCases, id: \.self) { weight in
                Text(weight.displayName).tag(weight)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)   // compact pop-up, as in Icon Composer's inspector
        .fixedSize()
    }

    // MARK: Picker

    private var pickerSection: some View {
        let isEmoji = editedConfig.iconType == .emoji
        return VStack(alignment: .leading, spacing: Self.headerToCard) {
            groupHeader(isEmoji ? AppStrings.Tab.emoji : AppStrings.Tab.symbol)
            VStack(spacing: 8) {
                // The search field stays fixed; only the grid below it scrolls.
                iconSearchField
                    .padding(.horizontal, 4)
                ScrollView(.vertical) {
                    if isEmoji {
                        EmojiPickerGrid(
                            selectedEmoji: Binding(
                                get: { editedConfig.iconValue },
                                set: { selectIcon($0, type: .emoji) }
                            ),
                            searchText: $searchText,
                            onSelect: { selectIcon($0, type: .emoji) }
                        )
                    } else {
                        SymbolPickerGrid(
                            selectedSymbol: Binding(
                                get: { editedConfig.iconValue },
                                set: { selectIcon($0, type: .sfSymbol) }
                            ),
                            searchText: $searchText,
                            iconWeight: editedConfig.iconWeight,
                            onSelect: { selectIcon($0, type: .sfSymbol) }
                        )
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.top, 10)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .frame(maxHeight: .infinity)
            .modifier(InspectorCard())
        }
        .frame(maxHeight: .infinity)
    }

    private var iconSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            TextField(
                editedConfig.iconType == .emoji ? AppStrings.Search.emojis : AppStrings.Search.symbols,
                text: $searchText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .quaternarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Inspector card surface

/// The inspector's card: the form-group surface with 12 pt continuous corners and no outline
/// (Icon Composer's inspector cards are fill-only) — or a 2 pt accent ring when the card is the
/// selected choice.
private struct InspectorCard: ViewModifier {
    var isSelected = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .background(NSColorBackgroundView.formGroup)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.accentColor, lineWidth: 2).opacity(isSelected ? 1 : 0))
    }
}

/// Liquid Glass capsule on macOS 26+, a material capsule before it.
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

// MARK: - Native Background Views

// Studio Canvas background now lives in NativeBackgroundViews.swift as the shared
// `StudioCanvasBackgroundView`, reused by the Popover Appearance preview hero.

// WindowBackgroundView, ControlBackgroundView, FormGroupBackgroundView
// replaced by shared NSColorBackgroundView in NativeBackgroundViews.swift

// MARK: - Color Swatch Button

private struct ColorSwatchButton: View {
    let color: Color
    let isSelected: Bool
    let size: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)

                if isSelected {
                    // White inner ring + white check (the handoff's selected swatch).
                    Circle()
                        .strokeBorder(Color.white.opacity(0.95), lineWidth: 2)
                        .frame(width: size, height: size)

                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Custom Color Picker Button

private struct CustomColorPickerButton: View {
    @Binding var selectedColor: Color
    let isSelected: Bool
    let size: CGFloat
    let onColorChange: (Color) -> Void

    var body: some View {
        Button {
            openColorPanel()
        } label: {
            ZStack {
                // Background circle with rainbow gradient border
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                .red, .yellow, .green, .cyan, .blue, .purple, .red
                            ]),
                            center: .center
                        )
                    )
                    .frame(width: size, height: size)

                // Inner circle (white or selected color)
                Circle()
                    .fill(isSelected ? selectedColor : Color.white)
                    .frame(width: size * 0.75, height: size * 0.75)

                // Plus icon when not selected, checkmark when selected
                if !isSelected {
                    Image(systemName: "plus")
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundColor(.gray)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }

    private func openColorPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(selectedColor)
        panel.setTarget(nil)
        panel.setAction(nil)

        // Use a delegate to capture color changes
        let delegate = ColorPanelDelegate(onColorChange: { nsColor in
            let newColor = Color(nsColor: nsColor)
            selectedColor = newColor
            onColorChange(newColor)
        })

        // Store delegate to keep it alive
        objc_setAssociatedObject(panel, &ColorPanelDelegate.associatedKey, delegate, .OBJC_ASSOCIATION_RETAIN)

        panel.setTarget(delegate)
        panel.setAction(#selector(ColorPanelDelegate.colorChanged(_:)))
        panel.orderFront(nil)
    }
}

// MARK: - Color Panel Delegate

@MainActor
private class ColorPanelDelegate: NSObject {
    nonisolated(unsafe) static var associatedKey: UInt8 = 0
    let onColorChange: (NSColor) -> Void

    init(onColorChange: @escaping (NSColor) -> Void) {
        self.onColorChange = onColorChange
    }

    @objc func colorChanged(_ sender: NSColorPanel) {
        onColorChange(sender.color)
    }
}

// MARK: - Color Extension for Hex Conversion

extension Color {
    func toHexString() -> String {
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.deviceRGB) else {
            return "#007AFF"  // Default to blue
        }

        let red = Int(rgbColor.redComponent * 255)
        let green = Int(rgbColor.greenComponent * 255)
        let blue = Int(rgbColor.blueComponent * 255)

        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

// MARK: - Preview

#Preview {
    CustomiseTileView(
        config: DockTileConfiguration(
            name: "AI Tile",
            tintColor: .blue,
            iconType: .sfSymbol,
            iconValue: "sparkles"
        ),
        onBack: {}
    )
    .environmentObject(ConfigurationManager())
    .frame(width: 620, height: 700)
}

/// A card for the Background choice: a 32 pt tile thumbnail and the label. Colour shows the tile
/// filled; Mono is split on the diagonal into its Light and Dark renders, so the one card explains
/// "follows the system".
private struct BackgroundChip: View {
    let option: TileBackground
    let config: DockTileConfiguration
    let isSelected: Bool
    /// False on macOS 15, where Mono is always the light render (see `CustomiseTileView.heroStyles`).
    let followsAppearance: Bool
    let action: () -> Void

    private let side: CGFloat = 32

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                thumbnail
                    .frame(width: side, height: side)
                Text(option == .colour ? AppStrings.Label.backgroundColour : AppStrings.Label.backgroundMono)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(InspectorCard(isSelected: isSelected))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityText: String {
        switch option {
        case .colour: return AppStrings.Label.backgroundColourAccessibility
        case .mono: return followsAppearance ? AppStrings.Label.backgroundMonoAccessibility : AppStrings.Label.backgroundMonoStaticAccessibility
        }
    }

    private func preview(_ style: IconStyle) -> some View {
        DockTileIconPreview(
            tintColor: config.tintColor, iconType: config.iconType, iconValue: config.iconValue,
            iconScale: config.iconScale, iconWeight: config.iconWeight, background: option, size: side
        )
        .forcing(style)
    }

    /// Canonical styles (forced), never the live system style: under a fixed Clear/Tinted system
    /// style the two chips would otherwise be indistinguishable.
    @ViewBuilder
    private var thumbnail: some View {
        switch option {
        case .colour:
            preview(.defaultStyle)
        case .mono where followsAppearance:
            ZStack {
                preview(.defaultStyle).clipShape(DiagonalHalf(upperLeading: true))
                preview(.dark).clipShape(DiagonalHalf(upperLeading: false))
            }
        case .mono:
            preview(.defaultStyle)
        }
    }
}

/// The triangle above (or below) the top-trailing → bottom-leading diagonal.
private struct DiagonalHalf: Shape {
    let upperLeading: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if upperLeading {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}
