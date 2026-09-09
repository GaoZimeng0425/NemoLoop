import Testing
@testable import NemoLoop

@MainActor
struct SettingsChromeTests {
    @Test func inspectorToggleNotifiesSubscriber() {
        let chrome = SettingsChrome()
        var seen: [Bool] = []
        chrome.inspectorDidChange = { seen.append($0) }
        chrome.inspectorVisible = true
        chrome.inspectorVisible = false
        #expect(seen == [true, false])
    }

    @Test func inspectorVisibleStartsFalse() {
        #expect(SettingsChrome().inspectorVisible == false)
    }
}
