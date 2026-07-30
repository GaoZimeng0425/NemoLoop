// NemoLoop/App/AppDelegate.swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sliceStore = SliceStore()
    let runningAppsService = RunningAppsService()
    let ringController = RingWindowController()
    let ringViewModel = RingViewModel()
    let settingsWindowController = SettingsWindowController()
    private var hotkeyService: HotkeyService?
    private var gamepadService: GamepadService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let summoner = RingSummoner(store: sliceStore,
                                    runningApps: runningAppsService,
                                    controller: ringController,
                                    viewModel: ringViewModel)

        let hotkeys = HotkeyService(summoner: summoner)
        hotkeys.register()
        self.hotkeyService = hotkeys

        let gamepad = GamepadService(summoner: summoner)
        gamepad.start()
        self.gamepadService = gamepad
    }
}
