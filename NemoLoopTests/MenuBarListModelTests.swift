import Foundation
import Testing
@testable import NemoLoop

struct MenuBarListModelTests {
    // MARK: - Running section

    @Test func runningRowsKeepInputOrderAndFlagFrontmost() {
        // Input arrives MRU-first (RunningAppsService.snapshot contract).
        let apps = [
            MenuBarListModel.AppEntry(id: 100, name: "Safari"),
            MenuBarListModel.AppEntry(id: 200, name: "WeChat"),
            MenuBarListModel.AppEntry(id: 300, name: "Terminal"),
        ]
        let rows = MenuBarListModel.runningRows(apps, frontmostPID: 200)
        #expect(rows.map(\.name) == ["Safari", "WeChat", "Terminal"])
        #expect(rows.map(\.isFrontmost) == [false, true, false])
    }

    @Test func runningRowsWithoutFrontmostFlagNothing() {
        let apps = [MenuBarListModel.AppEntry(id: 100, name: "Safari")]
        #expect(MenuBarListModel.runningRows(apps, frontmostPID: nil).allSatisfy { !$0.isFrontmost })
        // A frontmost pid that is not in the list highlights nothing.
        #expect(MenuBarListModel.runningRows(apps, frontmostPID: 999).allSatisfy { !$0.isFrontmost })
    }

    @Test func runningRowIdsAreStablePerPid() {
        let apps = [MenuBarListModel.AppEntry(id: 42, name: "Safari")]
        #expect(MenuBarListModel.runningRows(apps, frontmostPID: nil).first?.id == "42")
    }

    // MARK: - Pinned section

    @Test func pinnedRowsDropEmptySlotsAndKeepSlotOrder() {
        let a = URL(fileURLWithPath: "/Applications/Safari.app")
        let b = URL(fileURLWithPath: "/Applications/Figma.app")
        let rows = MenuBarListModel.pinnedRows([a, nil, b, nil, nil, nil])
        #expect(rows.map(\.name) == ["Safari", "Figma"])
        // iconIndex points at the ORIGINAL slot, so the view can fetch the cached icon.
        #expect(rows.map(\.iconIndex) == [0, 2])
    }

    @Test func pinnedRowNameDropsExtension() {
        let sketch = URL(fileURLWithPath: "/Users/x/Desktop/design.sketch")
        let rows = MenuBarListModel.pinnedRows([sketch])
        #expect(rows.first?.name == "design")
    }

    @Test func pinnedRowIdIsTheFilePath() {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        #expect(MenuBarListModel.pinnedRows([url]).first?.id == url.path)
    }

    @Test func emptySectionsGiveEmptyRows() {
        #expect(MenuBarListModel.runningRows([], frontmostPID: 1).isEmpty)
        #expect(MenuBarListModel.pinnedRows([]).isEmpty)
        #expect(MenuBarListModel.pinnedRows([nil, nil]).isEmpty)
    }
}
