// NemoLoop/MenuBar/MenuBarPanelView.swift
import AppKit
import SwiftUI

/// The pop-up panel content: section pills up top, launcher rows in the middle,
/// and the summon-ring / settings / quit footer. Colors come from `RingPalette`
/// via the color scheme — the panel's `appearance` decides the scheme, exactly
/// like the ring panel, so the three-tier theme choice drives this panel too.
struct MenuBarPanelView: View {
    enum Section: String, CaseIterable, Identifiable {
        case running, pinned
        var id: Self { self }
        var title: String { self == .running ? "Running" : "Pinned" }
    }

    /// Brand accent from the logo's heat gradient (#EB9433) — frontmost dot and
    /// the summon-ring pill. Fixed across schemes like NotchTheme's accent.
    private static let accent = Color(red: 0.922, green: 0.580, blue: 0.200)

    private static let rowHeight: CGFloat = 40
    private static let rowSpacing: CGFloat = 6
    private static let visibleRowCap = 8

    static let width: CGFloat = 300

    /// Panel height for a section with `rowCount` rows. Lives here so the
    /// controller and the view can't drift apart; blocks sum to exactly this.
    static func contentHeight(rowCount: Int) -> CGFloat {
        let listHeight = rowCount == 0
            ? CGFloat(28)
            : CGFloat(min(rowCount, visibleRowCap)) * rowHeight
                + CGFloat(min(rowCount, visibleRowCap) - 1) * rowSpacing
        // 12*2 vertical padding + 30 header + 10 spacing + hairline + 10 spacing
        // + list + 10 spacing + hairline + 10 spacing + 36 footer
        return listHeight + 132
    }

    @State private var section: Section = .running
    @State private var hoveredRowID: String?
    @Environment(\.colorScheme) private var scheme

    // Snapshot taken when the panel opens (same contract as the ring: data is
    // captured at summon, so rows don't reshuffle mid-interaction).
    let running: [RunningApp]
    let frontmostPID: pid_t?
    let sliceStore: SliceStore
    // The summon-ring footer button is a radial gesture: press pops the ring at
    // the pointer, drag into a blade, release picks it (same release path as the
    // hotkey — a plain click could never "release" the hold-style ring).
    let isRingVisible: () -> Bool
    let onRingPress: () -> Void
    let onRingRelease: () -> Void
    let onOpenApp: (RunningApp) -> Void
    let onRunPinned: (SlotAction) -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        let palette = RingPalette.palette(for: scheme)
        VStack(spacing: 10) {
            header(palette)
            Rectangle().fill(palette.dividerColor).frame(height: 1)
            list(palette)
            Rectangle().fill(palette.dividerColor).frame(height: 1)
            footer(palette)
        }
        .padding(12)
        .frame(width: Self.width, height: Self.contentHeight(rowCount: rows.count))
        .background(RoundedRectangle(cornerRadius: 14).fill(palette.glassTint))
        .onChange(of: section) { onHeightChange(Self.contentHeight(rowCount: rows.count)) }
    }

    // MARK: - Header

    private func header(_ palette: RingPalette) -> some View {
        HStack(spacing: 2) {
            ForEach(Section.allCases) { s in
                Text(s.title)
                    .font(.system(size: 12, weight: section == s ? .semibold : .regular))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(section == s ? palette.highlightEmpty : .clear))
                    .contentShape(Capsule())
                    .onTapGesture { section = s }
            }
            Spacer()
        }
        .padding(2)
        .background(Capsule().fill(palette.emptyFill))
        .frame(height: 30)
    }

    // MARK: - Rows

    private var rows: [MenuBarListModel.Row] {
        switch section {
        case .running:
            let entries = running.map { MenuBarListModel.AppEntry(id: $0.id, name: $0.name) }
            return MenuBarListModel.runningRows(entries, frontmostPID: frontmostPID)
        case .pinned:
            return MenuBarListModel.pinnedRows(sliceStore.config.actions)
        }
    }

    private func icon(for row: MenuBarListModel.Row) -> NSImage? {
        switch section {
        case .running:
            return running.indices.contains(row.iconIndex) ? running[row.iconIndex].icon : nil
        case .pinned:
            return sliceStore.icons.indices.contains(row.iconIndex) ? sliceStore.icons[row.iconIndex] : nil
        }
    }

    private func list(_ palette: RingPalette) -> some View {
        let content = VStack(spacing: Self.rowSpacing) {
            if rows.isEmpty {
                Text(section == .running ? "No apps running" : "Pin apps in Settings → Ring slots")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                ForEach(rows, id: \.id) { row in
                    rowView(row, palette: palette)
                }
            }
        }
        if rows.count > Self.visibleRowCap {
            return AnyView(ScrollView { content }
                .scrollIndicators(.hidden)
                .frame(height: Self.heightForVisibleRows()))
        }
        return AnyView(content)
    }

    private static func heightForVisibleRows() -> CGFloat {
        CGFloat(visibleRowCap) * rowHeight + CGFloat(visibleRowCap - 1) * rowSpacing
    }

    private func rowView(_ row: MenuBarListModel.Row, palette: RingPalette) -> some View {
        Button {
            switch section {
            case .running:
                if running.indices.contains(row.iconIndex) { onOpenApp(running[row.iconIndex]) }
            case .pinned:
                if sliceStore.config.actions.indices.contains(row.iconIndex),
                   let action = sliceStore.config.actions[row.iconIndex] {
                    onRunPinned(action)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let image = icon(for: row) {
                        Image(nsImage: image).resizable().interpolation(.high)
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(palette.emptyFill)
                    }
                }
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(row.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if row.isFrontmost {
                    Circle().fill(Self.accent).frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: Self.rowHeight)
            .background(RoundedRectangle(cornerRadius: 9)
                .fill(hoveredRowID == row.id ? palette.baseFill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredRowID = $0 ? row.id : nil }
    }

    // MARK: - Footer

    private func footer(_ palette: RingPalette) -> some View {
        HStack(spacing: 8) {
            Button {} label: {
                HStack(spacing: 6) {
                    Image("MenubarLogo")
                        .resizable().renderingMode(.template)
                        .frame(width: 14, height: 14)
                    Text("Summon Ring")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Self.accent))
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isRingVisible() { onRingPress() }
                    }
                    .onEnded { _ in onRingRelease() })

            Spacer(minLength: 0)

            iconButton("gearshape", palette: palette) { onOpenSettings() }
            iconButton("power", palette: palette) { onQuit() }
        }
        .frame(height: 36)
    }

    private func iconButton(_ systemName: String, palette: RingPalette,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(palette.emptyFill))
        }
        .buttonStyle(.plain)
    }
}
