// NemoLoop/Settings/SettingsView.swift
import AppKit
import KeyboardShortcuts
import Luminare
import SwiftUI
import UniformTypeIdentifiers

/// Sidebar tabs for the settings window (Loop-style left-right layout).
enum SettingsTab: LuminareTabItem, CaseIterable, Identifiable {
    case general, ring, plugins, appearance, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .ring: "Ring"
        case .plugins: "Plugins"
        case .appearance: "Appearance"
        case .about: "About"
        }
    }

    var image: Image {
        switch self {
        case .general: Image(systemName: "gearshape")
        case .ring: Image(systemName: "circle.grid.cross")
        case .plugins: Image(systemName: "puzzlepiece.extension")
        case .appearance: Image(systemName: "paintpalette")
        case .about: Image(systemName: "info.circle")
        }
    }
}

/// Which slot a picker popover is configuring. `popover(item:)` needs a
/// single optional Identifiable anchor shared by the main slot rows and the
/// sub-slot "+" buttons, so both collapse into this one target type.
private enum PickerTarget: Identifiable {
    case main(Int)
    case sub(Int)

    /// String ids ("main-3"/"sub-3") keep main and sub on the same slot from
    /// colliding — a value change re-presents the popover at the new target.
    var id: String {
        switch self {
        case .main(let i): "main-\(i)"
        case .sub(let i): "sub-\(i)"
        }
    }

    var context: PickerContext {
        switch self {
        case .main: .mainSlot
        case .sub: .subSlot
        }
    }

    var index: Int {
        switch self {
        case .main(let i), .sub(let i): i
        }
    }
}

struct SettingsView: View {
    @Bindable var store: SliceStore
    @Bindable var chrome: SettingsChrome
    @Bindable var appearance: AppearanceStore
    /// The tab the window opens on. Static so the window controller can size
    /// the initial frame for it (Ring opens with the inspector column).
    static let initialTab: SettingsTab = .ring
    @State private var tab: SettingsTab = SettingsView.initialTab
    /// Which slot groups have their sub-action rows unfolded.
    @State private var expandedSlots: Set<Int> = []
    /// The slot the picker popover is configuring, if open. One optional for
    /// both main rows and sub "+" buttons so `popover(item:)` presents a
    /// single popover app-wide.
    @State private var pickerSlot: PickerTarget?
    /// The selected wedge — shared by the slot list (row highlight) and the
    /// inspector's mini-ring (blade highlight), so selection syncs both ways.
    @State private var selectedSlot: Int?

    init(store: SliceStore, chrome: SettingsChrome, appearance: AppearanceStore) {
        self._store = Bindable(store)
        self._chrome = Bindable(chrome)
        self._appearance = Bindable(appearance)
    }

    var body: some View {
        HStack(spacing: 0) {
            if chrome.sidebarVisible {
                // Flush left sidebar, the way LuminareSidebar is meant to sit
                // (see its own preview: sidebar | Divider | pane) — no floating
                // card, no shadow, no inset.
                sidebar
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }
            LuminarePane {
                paneContent
            } header: {
                // Leading-aligned tab title: the pane's plain-Text header gets
                // centered by the button wrapper, which reads as a toolbar title.
                Text(tab.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .luminarePaneLayout(.stacked)
            // Third column, Ring tab only: the live mini-ring inspector.
            // Gated on the CHROME flag (kept in lockstep with `tab` by the
            // onChange/onAppear below) rather than `tab` itself, so the
            // column's insertion/removal lands in the same transaction as the
            // `inspectorVisible` change the .animation below keys on — gating
            // on `tab` would pop the column instantly while the window still
            // animates.
            if chrome.inspectorVisible {
                Divider()
                RingTabInspector(store: store,
                                 selectedSlot: $selectedSlot,
                                 // Empty-blade click configures directly: the
                                 // SAME picker popover the list rows use.
                                 configureSlot: { index in pickerSlot = .main(index) })
                    .frame(width: 280)
                    .padding(.vertical, 12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: chrome.sidebarVisible)
        .animation(.smooth(duration: 0.25), value: chrome.inspectorVisible)
        .luminareTint(overridingWith: .accentColor)
        // Rise into the titlebar strip: the pane header (tab name) then occupies
        // the full-size-content titlebar as the single top bar, instead of
        // stacking under the system title.
        .ignoresSafeArea(.container, edges: .top)
        // The inspector column exists exactly while the Ring tab is showing;
        // the chrome flag relays that to the window controller's resize.
        .onChange(of: tab) { chrome.inspectorVisible = ($0 == .ring) }
        .onAppear { chrome.inspectorVisible = (tab == .ring) }
    }

    /// Edge-to-edge sidebar column: full window height, square to the window
    /// edges; the hairline Divider in `body` separates it from the pane. The
    /// extra top margin keeps the first tab clear of the traffic lights and the
    /// titlebar toggle, which now share the strip the sidebar rises into.
    private var sidebar: some View {
        LuminareSidebar {
            LuminareSidebarSection(selection: $tab, items: SettingsTab.allCases)
                .padding(.vertical, 12)
        }
        .environment(\.luminareContentMarginsTop, 16)
        .frame(width: 200)
    }

    // MARK: - Panes

    @ViewBuilder private var paneContent: some View {
        switch tab {
        case .ring: ringSettings
        case .plugins: PluginsTab(registry: PluginRegistry.shared)
        case .general: placeholder("General settings coming soon.")
        case .appearance: appearanceSettings
        case .about: aboutSettings
        }
    }

    @ViewBuilder private var appearanceSettings: some View {
        LuminareSection(
            "Theme",
            "Ring card colours. Auto follows your system appearance; the next summon picks it up."
        ) {
            LuminarePicker(compactElements: RingAppearance.allCases, selection: $appearance.appearance) { option in
                VStack(spacing: 6) {
                    Image(systemName: option.iconName)
                        .font(.system(size: 16))
                    Text(option.label)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder private var ringSettings: some View {
        LuminareSection(
            "Hotkey",
            "Hold this hotkey anywhere to summon the ring; release over a wedge to launch."
        ) {
            LuminareCompose("Summon ring (hold):") {
                KeyboardShortcuts.Recorder("", name: .summonRing)
            }
            LuminareCompose("Open apps (hold):") {
                KeyboardShortcuts.Recorder("", name: .summonRunningApps)
            }
        }

        LuminareSection("Wedges") {
            ForEach(0..<SliceConfig.wedgeCount, id: \.self) { i in
                wedgeRow(i)
            }
        }
        // ONE popover attachment for the whole section: every row shares the
        // same optional binding, and per-row `.popover(item:)` modifiers would
        // each present their own popover when it goes non-nil.
        .popover(item: $pickerSlot) { target in
            ActionPickerPopover(context: target.context,
                                store: store,
                                slot: target.index,
                                onDismiss: { pickerSlot = nil })
        }
        // Whole-plugin mounts auto-expand their chip row: the point of the
        // mount is the plugin's op fan-out, so it unfolds the moment the pick
        // lands. The popover's init is pinned (no callback for this), so
        // react to the config transition instead — any slot whose action just
        // BECAME a whole-plugin mount expands; re-mounting the same plugin
        // (no transition) leaves the fold state alone.
        .onChange(of: store.config) { oldConfig, newConfig in
            for (i, entry) in newConfig.slots.enumerated()
            where oldConfig.slots.indices.contains(i) {
                if case .plugin = entry.action, oldConfig.slots[i].action != entry.action {
                    // _ = : Set.insert returns (inserted, memberAfter) —
                    // withAnimation would surface it as an unused result.
                    withAnimation(.smooth(duration: 0.2)) { _ = expandedSlots.insert(i) }
                }
            }
        }
    }

    @ViewBuilder
    private func wedgeRow(_ i: Int) -> some View {
        let entry = store.config.slots[i]
        // One collapsible group: the slot row, and when expanded its sub-slot
        // rows beneath (indented), ending with the add row.
        VStack(spacing: 0) {
            LuminareCompose(alignment: .center) {
                HStack(spacing: 6) {
                    slotPickerButton(i, entry: entry)
                    Button("Clear") {
                        withAnimation(.smooth(duration: 0.2)) {
                            store.setAction(nil, at: i)
                            expandedSlots.remove(i)
                            // The blade this selection pointed at is now empty —
                            // drop the list↔ring link instead of leaving the
                            // highlight parked on a blank blade.
                            selectedSlot = nil
                        }
                    }
                    .buttonStyle(.luminareCompact)
                    .disabled(entry.action == nil && entry.children.isEmpty)
                }
            } label: {
                HStack(spacing: 8) {
                    // Only configured slots unfold — sub-slots hang off a
                    // configured slot, so an empty slot has nothing to expand.
                    // (Legacy children without an action stay manageable.)
                    if entry.action != nil || !entry.children.isEmpty {
                        Button {
                            withAnimation(.smooth(duration: 0.2)) {
                                if expandedSlots.contains(i) {
                                    expandedSlots.remove(i)
                                } else {
                                    expandedSlots.insert(i)
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .rotationEffect(.degrees(expandedSlots.contains(i) ? 90 : 0))
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Group {
                        if let icon = store.icon(at: i) {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                        } else {
                            Image(systemName: "app.dashed")
                                .resizable()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 22, height: 22)
                    Text(label(for: i))
                }
            }

            if expandedSlots.contains(i) {
                subRows(i, entry: entry)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // Selection highlight (list side of the list↔ring link): a faint
        // accent wash plus a stroke, the same rounded-8 card language as the
        // rest of the pane.
        .background(selectedSlot == i ? Color.accentColor.opacity(0.08) : .clear)
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(selectedSlot == i ? Color.accentColor.opacity(0.4) : .clear))
        // Tap anywhere on the row EXCEPT its buttons (Choose/Clear/chevron
        // keep their own actions) selects the slot; the row's label area is
        // otherwise inert. Buttons win over this gesture, so they still work.
        .contentShape(Rectangle())
        .onTapGesture { selectedSlot = i }
    }

    /// The slot's action chip — click to (re)configure it in the picker
    /// popover (replaces the old nested Configure menu). Shows the current
    /// action as icon + resolved name; the link glyph marks plugin-backed
    /// slots as references to live plugin config; the name dims when the
    /// backing plugin is disconnected (same rule as the ring's dark state).
    /// An empty slot shows an add affordance instead.
    private func slotPickerButton(_ i: Int, entry: SlotEntry) -> some View {
        Button {
            pickerSlot = .main(i)
        } label: {
            HStack(spacing: 6) {
                if let icon = store.icon(at: i) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "plus.circle.dashed")
                        .foregroundStyle(.secondary)
                }
                if entry.action?.isPluginBacked == true {
                    // Reference semantics: this slot mirrors live plugin
                    // config, not a frozen copy of a pick.
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(entry.action.map { ActionResolver.name(for: $0) } ?? "Choose…")
                    .foregroundStyle(entry.action.map { store.isEnabled($0) ? Color.primary : Color.secondary }
                                     ?? .secondary)
            }
        }
        .buttonStyle(.luminareCompact)
    }

    /// The sub-slot controls of one slot, indented under it: a right-aligned
    /// strip of rounded icon buttons — one per sub-action (click removes, hover
    /// shows the minus badge) — with the add button at the end. Adding stays
    /// gated on a configured slot; an empty expanded slot explains why.
    @ViewBuilder
    private func subRows(_ i: Int, entry: SlotEntry) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            // childLimit (not the manual cap): a whole-plugin slot widens to
            // 8 sub-actions, and the add affordance must reflect that headroom.
            if !entry.children.isEmpty
                || (entry.action != nil
                    && entry.children.count < SlotEntry.childLimit(for: entry.action)) {
                HStack(spacing: 8) {
                    ForEach(entry.children.indices, id: \.self) { j in
                        // ActionResolver, not SlotAction.displayName: the model
                        // layer's plugin fallback is the raw "pluginID/opID",
                        // which must never reach the remove tooltip.
                        SubSlotChip(icon: SliceStore.icon(for: entry.children[j]),
                                    name: ActionResolver.name(for: entry.children[j])) {
                            withAnimation(.smooth(duration: 0.2)) {
                                store.removeChild(at: i, offset: j)
                            }
                        }
                    }

                    if entry.action != nil,
                       entry.children.count < SlotEntry.childLimit(for: entry.action) {
                        // Opens the same picker popover as the main slot, in
                        // sub-slot context (ops only — a sub-slot mounts
                        // single operations, never a whole plugin).
                        Button {
                            pickerSlot = .sub(i)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // The chip card wraps the BUTTON (as it did the old
                        // borderless menu) so the card chrome survives the
                        // plain button style.
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.quinary.opacity(0.6)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                        .help("Add Sub-action")
                    }
                }
                .padding(.vertical, 4)
            }

        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder private func placeholder(_ text: String) -> some View {
        LuminareSection {
            Text(text)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder private var aboutSettings: some View {
        LuminareSection("About") {
            LuminareCompose("Name") {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "NemoLoop")
                    .foregroundStyle(.secondary)
            }
            LuminareCompose("Version") {
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    // MARK: - Helpers

    /// Slots are numbered by ring order — blade 0 at 12 o'clock running
    /// clockwise — not by compass position: the fan's wrap gap means half the
    /// old "Upper-left"-style names pointed at nonexistent geometry.
    private func slotName(_ i: Int) -> String { "Slot \(i + 1)" }

    private func label(for i: Int) -> String {
        let entry = store.config.slots[i]
        // Resolve through the registry so plugin actions read their display
        // names ("Lock Screen"), never raw ids ("system/lockScreen").
        let base = entry.action.map { "\(slotName(i)): \(ActionResolver.name(for: $0))" }
            ?? "\(slotName(i)): (empty)"
        return entry.children.isEmpty ? base : "\(base) · \(entry.children.count) subs"
    }

    /// The shared modal file panel behind every manual pick. Static and
    /// module-visible: ActionPickerPopover's Browse rows call the same helper
    /// (one source of truth for the app/folder panel semantics) instead of
    /// carrying a second NSOpenPanel copy.
    static func runOpenPanel(contentTypes: [UTType],
                             directory: URL,
                             canChooseDirectories: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = contentTypes
        panel.directoryURL = directory
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = canChooseDirectories
        panel.canChooseFiles = !canChooseDirectories
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Theme picker presentation (UI strings live here, not on the model).
extension RingAppearance {
    var label: String {
        switch self {
        case .auto: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var iconName: String {
        switch self {
        case .auto: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

/// The 36pt rounded card frame shared by the sub-slot chip buttons.
private struct SubSlotChipFrame: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 8).fill(.quinary.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// One sub-slot chip: the action's icon; hovering reveals the minus badge and
/// clicking removes it (settings only configures — the ring runs these).
private struct SubSlotChip: View {
    let icon: NSImage
    let name: String
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onRemove) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .frame(width: 36, height: 36)
                .modifier(SubSlotChipFrame())
                .overlay(alignment: .topTrailing) {
                    if hovering {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Remove \(name)")
    }
}
