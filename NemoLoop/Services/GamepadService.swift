// NemoLoop/Services/GamepadService.swift
import AppKit
import GameController
import Observation

/// Bridges a connected game controller to ring summons.
///
/// Interaction: pushing a thumbstick out of the dead zone opens a ring — left stick shows the
/// running apps, right stick shows the launcher slots. The stick direction picks the wedge, and
/// letting the stick return to center opens the selected one. Whichever stick opened the ring
/// owns it until released; the other stick is ignored meanwhile.
@MainActor
@Observable
final class GamepadService {
    /// Stick magnitude below which the direction counts as "centered" (verified against real
    /// hardware: full deflection reads ~1.00, resting jitter stays under 0.2).
    static let deadZone: CGFloat = 0.35

    private enum Stick {
        case left   // running-apps ring
        case right  // launcher ring
    }

    private(set) var isConnected = false

    /// Latest stick directions, y-up, magnitude 0...~1. `.zero` when centered.
    /// Read by the ring's sampling timer via `RingInput.vector`.
    @ObservationIgnored private var leftDirection: CGPoint = .zero
    @ObservationIgnored private var rightDirection: CGPoint = .zero

    /// The stick that summoned the visible ring, or nil when no stick is engaged.
    @ObservationIgnored private var activeStick: Stick?

    private let summoner: RingSummoner

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(summoner: RingSummoner) {
        self.summoner = summoner
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func start() {
        // NemoLoop runs as an .accessory app and is never frontmost. Since macOS 11.3 this
        // defaults to NO, and without it the system drops every controller event on the floor.
        GCController.shouldMonitorBackgroundEvents = true

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let controller = note.object as? GCController else { return }
                self?.attach(controller)
            }
        })
        observers.append(center.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleDisconnect(note) }
        })

        GCController.controllers().forEach(attach)
        GCController.startWirelessControllerDiscovery {
            NSLog("NemoLoop gamepad wireless discovery finished")
        }
        NSLog("NemoLoop gamepad monitoring started, \(GCController.controllers().count) connected")
    }

    // MARK: - Connection

    private func attach(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else {
            NSLog("NemoLoop gamepad \(controller.vendorName ?? "?") has no extended profile, ignored")
            return
        }
        controller.handlerQueue = .main   // handlers below assume the main actor
        isConnected = true
        NSLog("NemoLoop gamepad connected: \(controller.vendorName ?? "?") (\(controller.productCategory))")

        pad.valueChangedHandler = { [weak self] pad, element in
            MainActor.assumeIsolated { self?.handle(element, on: pad) }
        }
    }

    private func handleDisconnect(_ note: Notification) {
        let name = (note.object as? GCController)?.vendorName ?? "?"
        isConnected = !GCController.controllers().isEmpty
        NSLog("NemoLoop gamepad disconnected: \(name), \(GCController.controllers().count) remaining")
        if !isConnected {
            leftDirection = .zero
            rightDirection = .zero
            activeStick = nil
            summoner.cancel()   // don't act on an aim the user can no longer see or change
        }
    }

    // MARK: - Input

    private func handle(_ element: GCControllerElement, on pad: GCExtendedGamepad) {
        if element === pad.leftThumbstick {
            leftDirection = Self.vector(of: pad.leftThumbstick)
            track(.left, direction: leftDirection)
        } else if element === pad.rightThumbstick {
            rightDirection = Self.vector(of: pad.rightThumbstick)
            track(.right, direction: rightDirection)
        }
    }

    private func track(_ stick: Stick, direction: CGPoint) {
        if Self.magnitude(direction) >= Self.deadZone {
            guard activeStick == nil else { return }   // another stick already owns the ring
            activeStick = stick
            summon(stick)
        } else if activeStick == stick {
            // Released: the ring kept its last aim through the dead zone, so commit it.
            activeStick = nil
            summoner.commit()
        }
    }

    private func summon(_ stick: Stick) {
        NSLog("NemoLoop gamepad summon \(stick == .left ? "running-apps" : "launcher") ring")
        let input = RingInput.vector(deadZone: Self.deadZone) { [weak self] in
            guard let self else { return .zero }
            return stick == .left ? self.leftDirection : self.rightDirection
        }
        switch stick {
        case .left: summoner.summonRunningApps(input: input)
        case .right: summoner.summonLauncher(input: input)
        }
    }

    private static func vector(of stick: GCControllerDirectionPad) -> CGPoint {
        CGPoint(x: CGFloat(stick.xAxis.value), y: CGFloat(stick.yAxis.value))
    }

    private static func magnitude(_ point: CGPoint) -> CGFloat {
        (point.x * point.x + point.y * point.y).squareRoot()
    }
}
