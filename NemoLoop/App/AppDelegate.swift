// NemoLoop/App/AppDelegate.swift
import AppKit

/// Owns the long-lived stores and wires the user surfaces — the summon ring
/// (hotkey / game controller driven) and the menu-bar panel (status item +
/// pop-up panel). Both ring entrances share one `RingSummoner`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sliceStore = SliceStore()
    let appearanceStore = AppearanceStore()
    let runningAppsService = RunningAppsService()
    let ringController = RingWindowController()
    let ringViewModel = RingViewModel()
    let settingsWindowController = SettingsWindowController()
    private var hotkeyService: HotkeyService?
    private var gamepadService: GamepadService?
    private var menuBarController: MenuBarPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let summoner = RingSummoner(store: sliceStore,
                                    runningApps: runningAppsService,
                                    controller: ringController,
                                    viewModel: ringViewModel,
                                    appearanceStore: appearanceStore)

        let hotkeys = HotkeyService(summoner: summoner)
        hotkeys.register()
        self.hotkeyService = hotkeys

        let gamepad = GamepadService(summoner: summoner)
        gamepad.start()
        self.gamepadService = gamepad

        let controller = MenuBarPanelController(
            sliceStore: sliceStore,
            runningApps: runningAppsService,
            appearanceStore: appearanceStore,
            isRingVisible: { [weak summoner] in summoner?.isShowing ?? false },
            summonRing: { [weak summoner] in summoner?.summonLauncher() },
            releaseRing: { [weak summoner] in summoner?.commit() },
            openSettings: { [weak self] in
                guard let self else { return }
                self.settingsWindowController.show(store: self.sliceStore,
                                                   appearance: self.appearanceStore)
            })
        controller.install()
        self.menuBarController = controller

        // Verification affordance: `NemoLoop --settings` opens Settings on launch —
        // the status item can be force-hidden when the menu bar is full, leaving
        // no clickable way in.
        if CommandLine.arguments.contains("--settings") {
            settingsWindowController.show(store: sliceStore, appearance: appearanceStore)
        }
        // Verification affordance: auto-start the OCR selection 2s after launch.
        if CommandLine.arguments.contains("--ocr-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                OcrSessionController.shared.handleOcrRequested()
            }
        }
    }
}
