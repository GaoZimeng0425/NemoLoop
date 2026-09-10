# Plugin Self-Managed Config + Chains Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the P0 foundation of the Flick-action port — the plugin self-managed config pattern plus the Chains plugin (action chains with repeat count and inter-step delay).

**Architecture:** `ChainStore` persists user-defined `ChainDefinition`s in UserDefaults; `ChainPlugin` derives its `operations` list from the store at read time (op id = chain UUID); `ChainExecutor` runs a chain's steps sequentially through `PluginRegistry.perform` (plugin ops) and an `AppOpening` seam (apps/folders), failing fast and ignoring reentrancy. The ring, `SlotAction`, `Launcher`, and SliceStore persistence are untouched; the only existing-API change is `PluginRegistry.perform` growing a `@discardableResult Bool` return.

**Tech Stack:** Swift 6 (strict concurrency, everything UI/plugin is `@MainActor`), SwiftUI + Luminare 0.2.0 (settings chrome), Swift Testing (`import Testing` / `@Test` / `#expect`), Xcode 16 file-system-synchronized project.

**Spec:** `docs/superpowers/specs/2026-09-10-plugin-config-chains-design.md` — the plan argues from the spec; executors read both.

## Global Constraints

- Repository: `/Users/gaozimeng/Learn/macOS/NemoLoop`, branch `develop`. Run all commands from the repo root.
- Unit tests MUST use the ad-hoc signing override (the dev certificate is invalid):
  `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet`
  For one suite append another `-only-testing:NemoLoopTests/<SuiteName>` (flags accumulate).
- New source files are picked up by Xcode 16 file-system-synchronized groups automatically — **never edit `project.pbxproj`**. Membership is proven by the tests compiling (they `@testable import NemoLoop` and reference the new types).
- Test conventions: Swift Testing, `@MainActor struct <Subject>Tests`, shared doubles live in `NemoLoopTests/PluginTestDoubles.swift`, throwaway defaults via `makeDefaults()`.
- Code identifiers and comments in English (repo convention); commit messages use conventional prefixes (`feat(chain):`, `test(chain):`, `refactor(settings):` …).
- MUST NOT touch: `SlotAction` cases/codec, `NemoLoop/Ring/*`, `NemoLoop/Services/Launcher.swift`, SliceStore keys (`nemoloop.slotEntries`), `nemoloop.plugin.<id>.enabled` key shape.
- Hard limits from the spec (verbatim): chains ≤ 32 (`ChainStore.maxChains`), steps ≤ 16 (`ChainDefinition.maxSteps`), repeatCount 1…20, interStepDelay 0…5 s, preset icon set exactly `link, bolt, clock, arrow.triangle.2.circlepath, square.stack.3d.up, globe, doc.text, keyboard, paintbrush, terminal`, chain storage key `nemoloop.plugin.chain.chains`.
- Every task: failing test → verify it fails → minimal implementation → verify pass → commit. For a brand-new type the "failing" run is a **compile failure** (`cannot find 'X' in scope`) — that is the expected red state.
- After the final task, launch the app for human inspection: `pkill -x NemoLoop` first, then build ad-hoc and `open` the Debug product (full command in Task 9). The app is a menu-bar accessory; the settings window is reachable via the menu-bar item, or launch argument `--settings`.

---

### Task 1: `PluginRegistry.perform` returns `@discardableResult Bool`

The executor must be able to tell a routed step from a failed one; `perform` is the single funnel, so it grows a return value. All existing callers discard it and stay untouched.

**Files:**
- Modify: `NemoLoop/Services/PluginRegistry.swift:72-82`
- Test: `NemoLoopTests/PluginRegistryTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `@discardableResult func perform(pluginID: String, opID: String) -> Bool` — `true` only when the op existed AND its plugin was enabled AND it was invoked. Tasks 4–5 depend on this signature.

- [ ] **Step 1: Write the failing test**

Append to `PluginRegistryTests.swift` (inside the struct):

```swift
    @Test func performReturnsTrueOnlyWhenRouted() async throws {
        // The chain executor (and any future combinator) needs perform to
        // report routing success so it can fail the sequence fast.
        let op = StubOp("play")
        let plugin = StubPlugin([op])
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [plugin])
        try await registry.setEnabled("stub", true)

        #expect(registry.perform(pluginID: "stub", opID: "play") == true)
        #expect(registry.perform(pluginID: "stub", opID: "nope") == false)   // unknown op
        #expect(registry.perform(pluginID: "ghost", opID: "play") == false)  // unknown plugin

        try await registry.setEnabled("stub", false)
        #expect(registry.perform(pluginID: "stub", opID: "play") == false)   // disabled
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/PluginRegistryTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet`
Expected: FAIL — the two `== false` lines fail because `perform` returns `Void`… actually it will not compile: `caller ignores result of Void` style error on `#expect(registry.perform(...) == true)` ("binary operator '==' cannot be applied to operands of type '()' and 'Bool'"). That compile failure is the red state.

- [ ] **Step 3: Minimal implementation**

In `PluginRegistry.swift`, replace `perform` (lines 72-82) with:

```swift
    /// Single funnel for every trigger. Returns false when the plugin is
    /// disabled or the op is unknown (both still just NSLog — a stale slot
    /// must never crash the ring); true when the op actually ran. The chain
    /// executor uses the result to abort a failing sequence.
    @discardableResult
    func perform(pluginID: String, opID: String) -> Bool {
        guard isEnabled(pluginID) else {
            NSLog("NemoLoop plugin: op \(pluginID).\(opID) skipped — plugin disabled")
            return false
        }
        guard let op = op(pluginID: pluginID, opID: opID) else {
            NSLog("NemoLoop plugin: unknown op \(pluginID).\(opID)")
            return false
        }
        op.perform()
        return true
    }
```

- [ ] **Step 4: Run the suite to verify pass**

Run the Step 2 command.
Expected: PASS (all PluginRegistryTests, including the pre-existing ones that discard the result).

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Services/PluginRegistry.swift NemoLoopTests/PluginRegistryTests.swift
git commit -m "feat(plugin): registry.perform reports routing success as Bool"
```

---

### Task 2: `ChainDefinition` model

**Files:**
- Create: `NemoLoop/Plugins/Chain/ChainDefinition.swift`
- Test: `NemoLoopTests/ChainDefinitionTests.swift`

**Interfaces:**
- Consumes: `SlotAction` (existing, unmodified).
- Produces:

```swift
struct ChainDefinition: Codable, Identifiable, Equatable {
    var id: UUID                          // op id space: ChainPlugin ops use id.uuidString
    var name: String
    var symbolName: String                // default "link"
    var steps: [SlotAction]               // any NON-chain action
    var repeatCount: Int                  // 1...maxRepeatCount
    var interStepDelay: TimeInterval      // 0...maxDelaySeconds, default 0.2
    static let maxSteps: Int              // 16
    static let minRepeatCount: Int        // 1
    static let maxRepeatCount: Int        // 20
    static let maxDelaySeconds: TimeInterval // 5
    static let presetSymbols: [String]    // the 10 spec'd SF Symbols
}
```

- [ ] **Step 1: Write the failing test**

Create `NemoLoopTests/ChainDefinitionTests.swift`:

```swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct ChainDefinitionTests {
    @Test func codableRoundTripKeepsEveryField() throws {
        let chain = ChainDefinition(
            name: "Wrap Up",
            symbolName: "bolt",
            steps: [.app(URL(filePath: "/Applications/Safari.app")),
                    .folder(URL(filePath: "/Users/dev/Work")),
                    .pluginOp(pluginID: "system", opID: "lockScreen")],
            repeatCount: 3,
            interStepDelay: 1.5)

        let data = try JSONEncoder().encode(chain)
        let decoded = try JSONDecoder().decode(ChainDefinition.self, from: data)
        #expect(decoded == chain)
    }

    @Test func freshDefaultsMatchSpec() {
        let chain = ChainDefinition(name: "Empty")
        #expect(chain.symbolName == "link")
        #expect(chain.steps.isEmpty)
        #expect(chain.repeatCount == 1)
        #expect(chain.interStepDelay == 0.2)
        // Spec-pinned constants: 32/16 live on store/definition; builder UI
        // and clamping both read these, so pin them here.
        #expect(ChainDefinition.maxSteps == 16)
        #expect(ChainDefinition.minRepeatCount == 1)
        #expect(ChainDefinition.maxRepeatCount == 20)
        #expect(ChainDefinition.maxDelaySeconds == 5)
        #expect(ChainDefinition.presetSymbols.count == 10)
        #expect(ChainDefinition.presetSymbols.first == "link")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/ChainDefinitionTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet`
Expected: compile failure — `cannot find 'ChainDefinition' in scope`.

- [ ] **Step 3: Minimal implementation**

Create `NemoLoop/Plugins/Chain/ChainDefinition.swift`:

```swift
// NemoLoop/Plugins/Chain/ChainDefinition.swift
import Foundation

/// One user-defined action chain: steps run sequentially, the whole run
/// repeats `repeatCount` times, and every step except the first of the run
/// waits `interStepDelay` seconds. Steps are any NON-chain `SlotAction`
/// (v1 has no nesting). The id doubles as the Chains plugin's op id.
struct ChainDefinition: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var symbolName = "link"
    var steps: [SlotAction] = []
    var repeatCount = 1
    var interStepDelay: TimeInterval = 0.2

    static let maxSteps = 16
    static let minRepeatCount = 1
    static let maxRepeatCount = 20
    static let maxDelaySeconds: TimeInterval = 5

    /// Icon chips offered by the builder — a full SF Symbol browser is out
    /// of scope for v1 (spec).
    static let presetSymbols = [
        "link", "bolt", "clock", "arrow.triangle.2.circlepath", "square.stack.3d.up",
        "globe", "doc.text", "keyboard", "paintbrush", "terminal",
    ]
}
```

- [ ] **Step 4: Run to verify pass**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Plugins/Chain/ChainDefinition.swift NemoLoopTests/ChainDefinitionTests.swift
git commit -m "feat(chain): ChainDefinition model with spec-pinned limits"
```

---

### Task 3: `ChainStore` persistence

UserDefaults JSON under the spec-pinned key, with clamping on every write (the builder clamps too — double enforcement per spec).

**Files:**
- Create: `NemoLoop/Plugins/Chain/ChainStore.swift`
- Test: `NemoLoopTests/ChainStoreTests.swift`

**Interfaces:**
- Consumes: `ChainDefinition` (Task 2).
- Produces:

```swift
@MainActor @Observable final class ChainStore {
    static let storageKey: String            // "nemoloop.plugin.chain.chains"
    static let maxChains: Int                // 32
    init(defaults: UserDefaults = .standard)
    private(set) var chains: [ChainDefinition]
    @discardableResult func add(_ chain: ChainDefinition) -> Bool  // false when full
    func update(_ chain: ChainDefinition)    // clamped; no-op on unknown id
    func remove(id: UUID)
}
```

- [ ] **Step 1: Write the failing test**

Create `NemoLoopTests/ChainStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct ChainStoreTests {
    @Test func persistsUnderDocumentedKeyAndReloads() throws {
        let defaults = makeDefaults()
        let store = ChainStore(defaults: defaults)
        var chain = ChainDefinition(name: "Wrap Up")
        chain.steps = [.pluginOp(pluginID: "system", opID: "lockScreen")]
        chain.repeatCount = 2
        #expect(store.add(chain))

        // Pin the on-disk key contract, not just behavior (spec pins this key).
        let data = try #require(defaults.data(forKey: "nemoloop.plugin.chain.chains"))
        #expect(try JSONDecoder().decode([ChainDefinition].self, from: data) == [chain])

        let reopened = ChainStore(defaults: defaults)
        #expect(reopened.chains == [chain])
    }

    @Test func updateEditsInPlaceAndRemoveDrops() {
        let store = ChainStore(defaults: makeDefaults())
        var chain = ChainDefinition(name: "Draft")
        store.add(chain)

        chain.name = "Shipped"
        store.update(chain)
        #expect(store.chains.map(\.name) == ["Shipped"])

        store.update(ChainDefinition(name: "Unknown"))   // unknown id is a no-op
        #expect(store.chains.count == 1)

        store.remove(id: chain.id)
        #expect(store.chains.isEmpty)
    }

    @Test func addRefusesBeyondMaxChains() {
        let store = ChainStore(defaults: makeDefaults())
        for i in 0..<ChainStore.maxChains {
            #expect(store.add(ChainDefinition(name: "chain \(i)")))
        }
        #expect(!store.add(ChainDefinition(name: "one too many")))
        #expect(store.chains.count == ChainStore.maxChains)
    }

    @Test func updateClampsFieldsToSpecLimits() {
        let store = ChainStore(defaults: makeDefaults())
        var chain = ChainDefinition(name: "clamp")
        chain.steps = (0..<20).map { _ in .app(URL(filePath: "/Applications/Safari.app")) }
        chain.repeatCount = 99
        chain.interStepDelay = 9
        store.add(chain)

        let saved = store.chains[0]
        #expect(saved.steps.count == ChainDefinition.maxSteps)
        #expect(saved.steps.first == .app(URL(filePath: "/Applications/Safari.app")))  // prefix kept
        #expect(saved.repeatCount == ChainDefinition.maxRepeatCount)
        #expect(saved.interStepDelay == ChainDefinition.maxDelaySeconds)

        var under = ChainDefinition(name: "under", repeatCount: 0, interStepDelay: -1)
        under.id = chain.id
        store.update(under)
        #expect(store.chains[0].repeatCount == ChainDefinition.minRepeatCount)
        #expect(store.chains[0].interStepDelay == 0)
    }

    @Test func corruptDataFallsBackToEmpty() {
        let defaults = makeDefaults()
        defaults.set(Data([0xFF, 0xFE]), forKey: ChainStore.storageKey)
        #expect(ChainStore(defaults: defaults).chains.isEmpty)
    }
}
```

Note: `ChainDefinition(name:repeatCount:interStepDelay:)` uses the memberwise init — argument order follows property declaration order (`name`, `repeatCount`, `interStepDelay`), which the Task 2 implementation satisfies.

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/ChainStoreTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet`
Expected: compile failure — `cannot find 'ChainStore' in scope`.

- [ ] **Step 3: Minimal implementation**

Create `NemoLoop/Plugins/Chain/ChainStore.swift`:

```swift
// NemoLoop/Plugins/Chain/ChainStore.swift
import Foundation
import Observation

/// Self-managed plugin config (the P0 foundation pattern): the Chains
/// plugin owns its data, derives `operations` from it at read time, and
/// persists it as JSON under its own UserDefaults key — SliceStore and the
/// slot format know nothing about it. Every write is clamped to the spec's
/// limits; the builder UI clamps too (double enforcement).
@MainActor
@Observable
final class ChainStore {
    /// On-disk key contract — pinned by ChainStoreTests and `defaults read`
    /// debugging; same family as nemoloop.plugin.<id>.enabled.
    static let storageKey = "nemoloop.plugin.chain.chains"
    static let maxChains = 32

    private let defaults: UserDefaults

    private(set) var chains: [ChainDefinition] {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([ChainDefinition].self, from: data) {
            chains = decoded
        } else {
            chains = []
        }
    }

    @discardableResult
    func add(_ chain: ChainDefinition) -> Bool {
        guard chains.count < Self.maxChains else {
            NSLog("NemoLoop chain store: full (\(Self.maxChains)) — add ignored")
            return false
        }
        chains.append(Self.clamped(chain))
        return true
    }

    func update(_ chain: ChainDefinition) {
        guard let index = chains.firstIndex(where: { $0.id == chain.id }) else { return }
        chains[index] = Self.clamped(chain)
    }

    func remove(id: UUID) {
        chains.removeAll { $0.id == id }
    }

    private static func clamped(_ chain: ChainDefinition) -> ChainDefinition {
        var clamped = chain
        clamped.steps = Array(clamped.steps.prefix(ChainDefinition.maxSteps))
        clamped.repeatCount = min(max(clamped.repeatCount, ChainDefinition.minRepeatCount),
                                  ChainDefinition.maxRepeatCount)
        clamped.interStepDelay = min(max(clamped.interStepDelay, 0), ChainDefinition.maxDelaySeconds)
        return clamped
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(chains) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Plugins/Chain/ChainStore.swift NemoLoopTests/ChainStoreTests.swift
git commit -m "feat(chain): ChainStore persists chain defs under plugin-owned key"
```

---

### Task 4: Executor seams + `ChainExecutor`

The core semantics task: order, repeat, delay-before-every-step-except-first, fail-fast abort, reentrancy guard, `.app/.folder` via seam.

**Files:**
- Create: `NemoLoop/Plugins/Chain/ChainExecutor.swift`
- Modify: `NemoLoopTests/PluginTestDoubles.swift` (add `ClosureOp`)
- Test: `NemoLoopTests/ChainExecutorTests.swift`

**Interfaces:**
- Consumes: `ChainDefinition` (Task 2), `PluginRegistry.perform(...) -> Bool` (Task 1), `StubPlugin`/`StubOp`/`makeDefaults()` (existing doubles).
- Produces (all in `ChainExecutor.swift`, all `@MainActor`):

```swift
@MainActor protocol AppOpening: AnyObject { @discardableResult func open(_ url: URL) -> Bool }
@MainActor final class WorkspaceAppOpener: AppOpening          // wraps NSWorkspace.shared.open
@MainActor protocol ChainSleeping: AnyObject { func sleep(seconds: TimeInterval) async throws }
@MainActor final class TaskChainSleeper: ChainSleeping          // wraps Task.sleep
@MainActor protocol ChainExecuting: AnyObject { func run(_ chain: ChainDefinition) async }
@MainActor final class ChainExecutor: ChainExecuting {
    init(registry: @escaping () -> PluginRegistry = { .shared },
         appOpener: any AppOpening = WorkspaceAppOpener(),
         sleeper: any ChainSleeping = TaskChainSleeper())
    func run(_ chain: ChainDefinition) async
}
```

  and in `PluginTestDoubles.swift`: `@MainActor final class ClosureOp: PluginOp` with `init(_ id: String, onPerform: @escaping () -> Void = {})` — Tasks 5's tests reuse it.

- [ ] **Step 1: Add the shared double**

Append to `NemoLoopTests/PluginTestDoubles.swift`:

```swift
/// Op whose perform() runs an injected closure — for tests that need custom
/// observation (ordering logs, gates) beyond StubOp's counter.
@MainActor
final class ClosureOp: PluginOp {
    let id: String
    let displayName: String
    let symbolName: String
    let onPerform: () -> Void

    init(_ id: String, onPerform: @escaping () -> Void = {}) {
        self.id = id
        displayName = id
        symbolName = "circle"
        self.onPerform = onPerform
    }

    func perform() { onPerform() }
}
```

- [ ] **Step 2: Write the failing tests**

Create `NemoLoopTests/ChainExecutorTests.swift`:

```swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct ChainExecutorTests {
    // Doubles: everything records into one ordered log so sequence semantics
    // (order, repeat, abort point) assert on a single timeline.
    @MainActor
    private final class Log {
        var entries: [String] = []
        func record(_ entry: String) { entries.append(entry) }
    }

    @MainActor
    private final class RecordingOpener: AppOpening {
        let log: Log
        var nextResult = true
        init(log: Log) { self.log = log }
        @discardableResult func open(_ url: URL) -> Bool {
            log.record("open:\(url.lastPathComponent)")
            return nextResult
        }
    }

    @MainActor
    private final class RecordingSleeper: ChainSleeping {
        var slept: [TimeInterval] = []
        func sleep(seconds: TimeInterval) async throws { slept.append(seconds) }
    }

    /// Parks each sleep on a continuation so a run can be frozen mid-delay
    /// (the reentrancy test needs a run demonstrably still in flight).
    @MainActor
    private final class BlockingSleeper: ChainSleeping {
        private var parked: [CheckedContinuation<Void, Never>] = []
        private(set) var sleptCount = 0
        func sleep(seconds: TimeInterval) async throws {
            sleptCount += 1
            await withCheckedContinuation { parked.append($0) }
        }
        func releaseAll() {
            parked.forEach { $0.resume() }
            parked.removeAll()
        }
    }

    @Test func runsStepsInOrderAcrossRepeats() async throws {
        let log = Log()
        let opener = RecordingOpener(log: log)
        let a = ClosureOp("a") { log.record("a") }
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin(id: "stub", [a])])
        try await registry.setEnabled("stub", true)

        var chain = ChainDefinition(name: "seq")
        chain.steps = [.pluginOp(pluginID: "stub", opID: "a"),
                       .app(URL(filePath: "/Applications/Safari.app"))]
        chain.repeatCount = 2
        chain.interStepDelay = 0    // determinism: no sleeps in this test

        let executor = ChainExecutor(registry: { registry }, appOpener: opener,
                                      sleeper: RecordingSleeper())
        await executor.run(chain)
        #expect(log.entries == ["a", "open:Safari.app", "a", "open:Safari.app"])
    }

    @Test func delayBeforeEveryStepExceptTheVeryFirst() async throws {
        let log = Log()
        let a = ClosureOp("a") { log.record("a") }
        let b = ClosureOp("b") { log.record("b") }
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin(id: "stub", [a, b])])
        try await registry.setEnabled("stub", true)

        var chain = ChainDefinition(name: "delay")
        chain.steps = [.pluginOp(pluginID: "stub", opID: "a"),
                       .pluginOp(pluginID: "stub", opID: "b")]
        chain.repeatCount = 2
        chain.interStepDelay = 0.25

        let sleeper = RecordingSleeper()
        let executor = ChainExecutor(registry: { registry }, appOpener: RecordingOpener(log: log),
                                     sleeper: sleeper)
        await executor.run(chain)
        // 4 executions → 3 waits (everything except the run's very first
        // step; the iteration boundary counts as a step boundary).
        #expect(sleeper.slept == [0.25, 0.25, 0.25])
        #expect(log.entries == ["a", "b", "a", "b"])
    }

    @Test func zeroDelayNeverSleeps() async throws {
        let a = ClosureOp("a")
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin(id: "stub", [a])])
        try await registry.setEnabled("stub", true)

        var chain = ChainDefinition(name: "fast")
        chain.steps = [.pluginOp(pluginID: "stub", opID: "a"),
                       .pluginOp(pluginID: "stub", opID: "a"),
                       .pluginOp(pluginID: "stub", opID: "a")]
        let sleeper = RecordingSleeper()
        await ChainExecutor(registry: { registry }, appOpener: RecordingOpener(log: Log()),
                            sleeper: sleeper).run(chain)
        #expect(sleeper.slept.isEmpty)
    }

    @Test func unknownOpStepAbortsTheChain() async throws {
        let log = Log()
        let opener = RecordingOpener(log: log)
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin(id: "stub", [ClosureOp("a")])])
        try await registry.setEnabled("stub", true)

        var chain = ChainDefinition(name: "abort")
        chain.steps = [.pluginOp(pluginID: "stub", opID: "ghost"),   // unknown → false
                       .app(URL(filePath: "/Applications/Safari.app"))]
        chain.interStepDelay = 0
        await ChainExecutor(registry: { registry }, appOpener: opener,
                            sleeper: RecordingSleeper()).run(chain)
        #expect(log.entries.isEmpty)   // step 2 never ran
    }

    @Test func disabledPluginStepAbortsTheChain() async throws {
        let log = Log()
        let plugin = StubPlugin(id: "stub", [ClosureOp("a")])
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [plugin])
        try await registry.setEnabled("stub", true)
        try await registry.setEnabled("stub", false)   // enabled then disabled

        var chain = ChainDefinition(name: "disabled")
        chain.steps = [.pluginOp(pluginID: "stub", opID: "a"),
                       .app(URL(filePath: "/Applications/Safari.app"))]
        chain.interStepDelay = 0
        await ChainExecutor(registry: { registry }, appOpener: RecordingOpener(log: log),
                            sleeper: RecordingSleeper()).run(chain)
        #expect(log.entries.isEmpty)
    }

    @Test func openFailureAbortsTheChain() async throws {
        let log = Log()
        let opener = RecordingOpener(log: log)
        opener.nextResult = false
        let a = ClosureOp("a") { log.record("a") }
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin(id: "stub", [a])])
        try await registry.setEnabled("stub", true)

        var chain = ChainDefinition(name: "openfail")
        chain.steps = [.app(URL(filePath: "/Applications/Safari.app")),
                       .pluginOp(pluginID: "stub", opID: "a")]
        chain.interStepDelay = 0
        await ChainExecutor(registry: { registry }, appOpener: opener,
                            sleeper: RecordingSleeper()).run(chain)
        #expect(log.entries == ["open:Safari.app"])   // abort before the op step
    }

    @Test func wholePluginStepFailsDefensively() async throws {
        let log = Log()
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin(id: "stub", [ClosureOp("a")])])
        try await registry.setEnabled("stub", true)

        var chain = ChainDefinition(name: "defensive")
        chain.steps = [.plugin("stub"),
                       .pluginOp(pluginID: "stub", opID: "a")]
        chain.interStepDelay = 0
        await ChainExecutor(registry: { registry }, appOpener: RecordingOpener(log: log),
                            sleeper: RecordingSleeper()).run(chain)
        #expect(log.entries.isEmpty)   // .plugin as a step is filtered by the builder; treated as failure here
    }

    @Test func folderStepsOpenThroughTheSeam() async throws {
        let log = Log()
        let opener = RecordingOpener(log: log)
        let executor = ChainExecutor(registry: { PluginRegistry(defaults: makeDefaults(), plugins: []) },
                                     appOpener: opener, sleeper: RecordingSleeper())
        var chain = ChainDefinition(name: "folders")
        chain.steps = [.folder(URL(filePath: "/Users/dev/Work"))]
        await executor.run(chain)
        #expect(log.entries == ["open:Work"])
    }

    @Test func reentrantRunIsIgnoredWhileRunning() async throws {
        let log = Log()
        let a = ClosureOp("a") { log.record("a") }
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin(id: "stub", [a])])
        try await registry.setEnabled("stub", true)

        var chain = ChainDefinition(name: "double")
        chain.steps = [.pluginOp(pluginID: "stub", opID: "a"),
                       .pluginOp(pluginID: "stub", opID: "a")]
        chain.interStepDelay = 0.1   // parks run #1 between its two steps

        let sleeper = BlockingSleeper()
        let executor = ChainExecutor(registry: { registry }, appOpener: RecordingOpener(log: Log()),
                                     sleeper: sleeper)
        let first = Task { await executor.run(chain) }
        // Single-actor determinism: yield until run #1 has parked in the sleeper
        // (its first step has executed exactly once by then).
        while sleeper.sleptCount < 1 { await Task.yield() }

        await executor.run(chain)          // reentrant trigger — must be a no-op
        #expect(log.entries == ["a"])      // run #1's first step only

        sleeper.releaseAll()
        await first.value
        #expect(log.entries == ["a", "a"]) // run #1 finished; run #2 added nothing
    }
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/ChainExecutorTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet`
Expected: compile failure — `cannot find 'AppOpening' in scope` (and `ChainExecutor`).

- [ ] **Step 4: Minimal implementation**

Create `NemoLoop/Plugins/Chain/ChainExecutor.swift`:

```swift
// NemoLoop/Plugins/Chain/ChainExecutor.swift
import AppKit
import Foundation

/// Testability seam for .app/.folder chain steps (the ShellRunning pattern,
/// but MainActor-confined: NSWorkspace.open is main-thread API and the
/// executor is MainActor, so the seam stays actor-confined and race-free).
@MainActor
protocol AppOpening: AnyObject {
    @discardableResult func open(_ url: URL) -> Bool
}

@MainActor
final class WorkspaceAppOpener: AppOpening {
    @discardableResult func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

/// Testability seam for the inter-step delay — Task.sleep itself cannot be
/// observed from tests. Suspending on the main actor is fine: suspension
/// never blocks the run loop.
@MainActor
protocol ChainSleeping: AnyObject {
    func sleep(seconds: TimeInterval) async throws
}

@MainActor
final class TaskChainSleeper: ChainSleeping {
    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

@MainActor
protocol ChainExecuting: AnyObject {
    func run(_ chain: ChainDefinition) async
}

/// Sequential chain runner, semantics pinned by the spec:
///   - steps run in order; the whole run repeats `repeatCount` times;
///   - every step except the run's very first waits `interStepDelay`;
///   - a failed step ABORTS the chain (order-dependent sequences must not
///     limp on half-executed) — already-run steps are not rolled back;
///   - a reentrant trigger of an already-running chain is ignored.
@MainActor
final class ChainExecutor: ChainExecuting {
    private let registry: () -> PluginRegistry
    private let appOpener: any AppOpening
    private let sleeper: any ChainSleeping
    private var runningIDs: Set<UUID> = []

    /// The registry is resolved lazily (factory, default `.shared`) because
    /// PluginRegistry.shared constructs the plugin that owns this executor —
    /// an eager reference would be an initialization cycle.
    init(registry: @escaping () -> PluginRegistry = { .shared },
         appOpener: any AppOpening = WorkspaceAppOpener(),
         sleeper: any ChainSleeping = TaskChainSleeper()) {
        self.registry = registry
        self.appOpener = appOpener
        self.sleeper = sleeper
    }

    func run(_ chain: ChainDefinition) async {
        guard !runningIDs.contains(chain.id) else {
            NSLog("NemoLoop chain: '\(chain.name)' already running — retrigger ignored")
            return
        }
        runningIDs.insert(chain.id)
        defer { runningIDs.remove(chain.id) }

        for iteration in 0..<max(chain.repeatCount, 1) {
            for (index, step) in chain.steps.enumerated() {
                if !(iteration == 0 && index == 0), chain.interStepDelay > 0 {
                    try? await sleeper.sleep(seconds: chain.interStepDelay)
                }
                guard performStep(step) else {
                    NSLog("NemoLoop chain: step \(index + 1) failed — chain '\(chain.name)' aborted")
                    return
                }
            }
        }
    }

    private func performStep(_ step: SlotAction) -> Bool {
        switch step {
        case .pluginOp(let pluginID, let opID):
            return registry().perform(pluginID: pluginID, opID: opID)
        case .app(let url), .folder(let url):
            if appOpener.open(url) { return true }
            NSLog("NemoLoop chain: open failed for \(url.path)")
            return false
        case .plugin:
            NSLog("NemoLoop chain: whole-plugin mount cannot be a chain step (the builder filters it)")
            return false
        }
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run the Step 3 command. Expected: PASS — 9 tests. If the reentrancy test flakes on `Task.yield()` progress, increase determinism by yielding in a loop `for _ in 0..<100 { await Task.yield() }` before the while-check (single MainActor: the spawned task must reach the sleeper).

- [ ] **Step 6: Commit**

```bash
git add NemoLoop/Plugins/Chain/ChainExecutor.swift NemoLoopTests/PluginTestDoubles.swift NemoLoopTests/ChainExecutorTests.swift
git commit -m "feat(chain): sequential executor with fail-fast, delay, repeat, reentrancy guard"
```

---

### Task 5: `ChainPlugin` + registry wiring + render-harness 4th seam

`configSections` stays `nil` in this task — the builder UI (Task 8) wires it. Adding `ChainPlugin()` to `PluginRegistry.shared` breaks the Ring-tab render harness compile (it links `PluginRegistry.swift` verbatim), so the harness gets a mirrored seam plugin **in the same task**, pinned disabled so its pixel assertions stay valid until Task 9.

**Files:**
- Create: `NemoLoop/Plugins/Chain/ChainPlugin.swift`
- Modify: `NemoLoop/Services/PluginRegistry.swift:12-16` (shared plugin list)
- Modify: `Design/render_check_ring_tab.swift` (4th seam + registry pin)
- Test: `NemoLoopTests/ChainPluginTests.swift`

**Interfaces:**
- Consumes: `ChainStore` (Task 3), `ChainExecuting`/`ChainExecutor` (Task 4), `NemoPlugin` protocol.
- Produces:

```swift
@MainActor final class ChainPlugin: NemoPlugin {
    static let pluginID: String              // "chain"
    init(store: ChainStore = ChainStore(), executor: (any ChainExecuting)? = nil)
    var operations: [any PluginOp]           // store.chains minus empty ones → Op(id: uuidString, …)
    let isEnabledByDefault: Bool             // true — ships connected like System
    var configSections: AnyView?             // nil in this task; Task 8 wires ChainConfigSection
}
```

  `PluginRegistry.shared` now includes `ChainPlugin()` as its 4th plugin. Chains with zero steps yield no op (spec: an empty chain must not be mountable) — they stay in the builder list and become pickable the moment their first step lands.

- [ ] **Step 1: Write the failing tests**

Create `NemoLoopTests/ChainPluginTests.swift`:

```swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct ChainPluginTests {
    /// Executor double: records runs synchronously at entry.
    @MainActor
    final class RecordingExecutor: ChainExecuting {
        var runs: [ChainDefinition] = []
        func run(_ chain: ChainDefinition) async { runs.append(chain) }
    }

    @Test func operationsDeriveFromStoreByIdentity() {
        let store = ChainStore(defaults: makeDefaults())
        var first = ChainDefinition(name: "Wrap Up")
        first.steps = [.pluginOp(pluginID: "system", opID: "lockScreen")]
        var second = ChainDefinition(name: "Morning")
        second.symbolName = "clock"
        second.steps = [.app(URL(filePath: "/Applications/Safari.app"))]   // non-empty → mountable
        store.add(first)
        store.add(second)

        let plugin = ChainPlugin(store: store, executor: RecordingExecutor())
        #expect(plugin.id == "chain")
        #expect(plugin.operations.map(\.id) == [first.id.uuidString, second.id.uuidString])
        #expect(plugin.operations.map(\.displayName) == ["Wrap Up", "Morning"])
        #expect(plugin.operations.map(\.symbolName) == ["link", "clock"])
    }

    @Test func editingAChainFollowsThroughTheOpIdentity() {
        let store = ChainStore(defaults: makeDefaults())
        var chain = ChainDefinition(name: "Draft")
        store.add(chain)

        let plugin = ChainPlugin(store: store, executor: RecordingExecutor())
        chain.name = "Shipped"          // same UUID, new name
        chain.symbolName = "bolt"
        store.update(chain)

        let op = plugin.operations[0]
        #expect(op.id == chain.id.uuidString)   // slot references survive edits
        #expect(op.displayName == "Shipped")
        #expect(op.symbolName == "bolt")
    }

    @Test func removingAChainDropsItsOp() {
        let store = ChainStore(defaults: makeDefaults())
        var chain = ChainDefinition(name: "Gone")
        store.add(chain)
        let plugin = ChainPlugin(store: store, executor: RecordingExecutor())
        #expect(plugin.operations.count == 1)

        store.remove(id: chain.id)
        #expect(plugin.operations.isEmpty)
        // Mounted slots keep .pluginOp("chain", <uuid>) — the registry's
        // existing unknown-op tolerance covers the dangling reference.
    }

    @Test func shipsEnabledByDefault() {
        let registry = PluginRegistry(defaults: makeDefaults(),
                                      plugins: [ChainPlugin(store: ChainStore(defaults: makeDefaults()),
                                                            executor: RecordingExecutor())])
        #expect(registry.isEnabled("chain"))
    }

    @Test func opPerformDelegatesToTheExecutor() async throws {
        let store = ChainStore(defaults: makeDefaults())
        var chain = ChainDefinition(name: "Run me")
        chain.steps = [.pluginOp(pluginID: "stub", opID: "a")]
        chain.interStepDelay = 0
        store.add(chain)

        let executor = RecordingExecutor()
        let plugin = ChainPlugin(store: store, executor: executor)
        plugin.operations[0].perform()   // fire-and-forget Task inside

        // The perform() spawns a Task; give the main actor a beat to drain it.
        try await Task.sleep(for: .milliseconds(100))
        #expect(executor.runs.map(\.id) == [chain.id])
    }

    @Test func emptyStoreYieldsNoOperations() {
        let plugin = ChainPlugin(store: ChainStore(defaults: makeDefaults()),
                                 executor: RecordingExecutor())
        #expect(plugin.operations.isEmpty)
        #expect(plugin.status == .ready)
    }

    @Test func emptyChainYieldsNoOpUntilItHasAStep() {
        // Spec: an empty chain must not be mountable — the builder creates
        // chains with zero steps, and the op only appears once a step lands.
        let store = ChainStore(defaults: makeDefaults())
        var empty = ChainDefinition(name: "Nothing yet")
        store.add(empty)
        var filled = ChainDefinition(name: "Has a step")
        filled.steps = [.pluginOp(pluginID: "system", opID: "lockScreen")]
        store.add(filled)

        let plugin = ChainPlugin(store: store, executor: RecordingExecutor())
        #expect(plugin.operations.map(\.displayName) == ["Has a step"])

        empty.steps = [.pluginOp(pluginID: "system", opID: "sleep")]
        store.update(empty)
        #expect(plugin.operations.count == 2)   // becomes mountable immediately
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/ChainPluginTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet`
Expected: compile failure — `cannot find 'ChainPlugin' in scope`.

- [ ] **Step 3: Implement `ChainPlugin`**

Create `NemoLoop/Plugins/Chain/ChainPlugin.swift`:

```swift
// NemoLoop/Plugins/Chain/ChainPlugin.swift
import SwiftUI

/// The plugin over user-defined chains: every saved ChainDefinition becomes
/// exactly one op whose id is the chain's UUID — slots mount
/// `.pluginOp("chain", <uuid>)`, and edits flow into mounted blades because
/// ops derive from the store at read time. The first consumer of the P0
/// self-managed-config pattern (spec: 2026-09-10-plugin-config-chains).
@MainActor
final class ChainPlugin: NemoPlugin {
    static let pluginID = "chain"

    private let store: ChainStore
    private let executor: any ChainExecuting

    init(store: ChainStore = ChainStore(), executor: (any ChainExecuting)? = nil) {
        self.store = store
        self.executor = executor ?? ChainExecutor()
    }

    let id = ChainPlugin.pluginID
    let displayName = "Chains"
    let symbolName = "link"
    let summary = "Run several actions in one trigger — with repeat and inter-step delay."
    var status: PluginStatus { .ready }
    /// Ships connected like System: chains only exist once the user creates
    /// them, so an empty plugin costs nothing (spec decision).
    let isEnabledByDefault = true

    var operations: [any PluginOp] {
        // Empty chains stay unmountable (spec): they exist only in the
        // builder until their first step lands.
        store.chains
            .filter { !$0.steps.isEmpty }
            .map { Op(definition: $0, executor: executor) }
    }

    /// nil until the chain-builder task wires ChainConfigSection in.
    var configSections: AnyView? { nil }

    struct Op: @MainActor PluginOp {
        let definition: ChainDefinition
        let executor: any ChainExecuting
        var id: String { definition.id.uuidString }
        var displayName: String { definition.name }
        var symbolName: String { definition.symbolName }
        func perform() {
            // Fire-and-forget: the ring dismisses immediately; multi-second
            // chains must not hold the panel open.
            Task { await executor.run(definition) }
        }
    }
}
```

- [ ] **Step 4: Register in the shared registry**

In `NemoLoop/Services/PluginRegistry.swift`, change the `shared` definition (lines 12-16) to:

```swift
    static let shared = PluginRegistry(plugins: [
        SystemPlugin(),
        AppearancePlugin(),
        ScreenshotPlugin(),
        ChainPlugin(),
    ])
```

- [ ] **Step 5: Add the render-harness 4th seam**

`Design/render_check_ring_tab.swift` compiles `PluginRegistry.swift` verbatim (see `RenderCheckBootstrap.appSources`), so the new `ChainPlugin()` reference must be satisfied there. Two edits:

Edit A — append a mirrored plugin right after the `ScreenshotPlugin` mirror (after line 181, the class closing brace):

```swift
/// Verbatim from NemoLoop/Plugins/Chain/ChainPlugin.swift, EXCEPT: ops are
/// fixture-fixed (the real plugin derives them from ChainStore — irrelevant
/// to pixels) and perform is a no-op. Metadata is verbatim so the picker
/// model sees the real plugin shape. Pinned DISABLED until the chain
/// fixture task flips the pin and widens the whole-row assertions.
@MainActor
final class ChainPlugin: @MainActor NemoPlugin {
    static let pluginID = "chain"
    let id = ChainPlugin.pluginID
    let displayName = "Chains"
    let symbolName = "link"
    let summary = "Run several actions in one trigger — with repeat and inter-step delay."

    struct Op: @MainActor PluginOp {
        let id = "demo-chain-op"
        let displayName = "Wrap Up (fixture)"
        let symbolName = "link"
        func perform() { NSLog("NemoLoop render harness: chain perform skipped") }
    }

    var operations: [any PluginOp] { [Op()] }
    var status: PluginStatus { .ready }
}
```

(`pluginID` is required because the harness compiles the real `ActionPickerModel.swift`, which after Task 6 references `ChainPlugin.pluginID`.)

Edit B — in `RenderCheckBootstrap.registryPins` (around line 842), append:

```swift
        "-nemoloop.plugin.chain.enabled", "NO",
```

(Pinned NO so panel C's existing `trailingBands == 2` assertion stays valid; Task 9 flips it.)

Also update the header comment's pin list (lines 59-66 block) by appending the matching line `-nemoloop.plugin.chain.enabled NO   <- 4th plugin, seam-mirrored, off until Task 9` so the documented pin set stays truthful.

- [ ] **Step 6: Run tests + the harness to verify both pass**

Run the Step 2 command. Expected: PASS — 7 tests.
Then: `swift Design/render_check_ring_tab.swift`
Expected: exits 0, `SUMMARY: all pixel checks PASS`, output `Design/render_check_ring_tab.png`.

- [ ] **Step 7: Commit**

```bash
git add NemoLoop/Plugins/Chain/ChainPlugin.swift NemoLoop/Services/PluginRegistry.swift Design/render_check_ring_tab.swift NemoLoopTests/ChainPluginTests.swift
git commit -m "feat(chain): ChainPlugin with store-derived ops, registered by default"
```

---

### Task 6: Picker `.chainStep` context + zero-op plugin filter

**Files:**
- Modify: `NemoLoop/Services/ActionPickerModel.swift:6-9` (PickerContext), `:119-138` (plugin loop)
- Test: `NemoLoopTests/ActionPickerModelTests.swift` (append)

**Interfaces:**
- Consumes: `ChainPlugin.pluginID` (Task 5), `ChainStore`/`ChainDefinition` (Tasks 2-3).
- Produces: `PickerContext.chainStep` — the builder context: no whole-plugin rows (same as `.subSlot`) and the Chains plugin group hidden entirely (no nesting in v1). Plus a global rule: connected plugins with zero operations render nothing anywhere (a whole-mount of an empty plugin is a dead blade).

- [ ] **Step 1: Write the failing tests**

Append to `NemoLoopTests/ActionPickerModelTests.swift` (inside the struct):

```swift
    // MARK: - Chain-step context + zero-op filter

    private func makeChainModel() async throws -> ActionPickerModel {
        let defaults = UserDefaults(suiteName: "picker-tests-\(UUID().uuidString)")!
        let chainStore = ChainStore(defaults: defaults)
        var chain = ChainDefinition(name: "Wrap Up")
        chain.steps = [.pluginOp(pluginID: "system", opID: "lockScreen")]
        chainStore.add(chain)
        let registry = PluginRegistry(defaults: defaults,
                                      plugins: [SystemPlugin(), ChainPlugin(store: chainStore)])
        try await registry.setEnabled("system", true)
        try await registry.setEnabled("chain", true)
        return ActionPickerModel(apps: [], registry: registry)
    }

    @Test func chainStepListsSingleActionsOnly() async throws {
        let model = try await makeChainModel()
        let sections = model.sections(context: .chainStep, query: "")
        let plugins = sections.first { $0.title == "Plugins" }!

        // Single ops from other plugins stay pickable…
        #expect(plugins.items.contains { $0.kind == .op(pluginID: "system", opID: "lockScreen") })
        // …whole-plugin mounts are absent (like subSlot)…
        #expect(!plugins.items.contains { if case .wholePlugin = $0.kind { return true }; return false })
        // …and the Chains plugin itself never appears (no chain-in-chain).
        #expect(!plugins.items.contains { $0.kind == .op(pluginID: "chain", opID: "demo") })
        // Apps and Folders sections unaffected.
        #expect(sections.map(\.title) == ["Apps", "Plugins", "Folders"])
    }

    @Test func zeroOpConnectedPluginRendersNothingInMainSlot() async throws {
        // A connected plugin with no operations (e.g. Chains before the user
        // creates any) must not render at all — its whole-plugin row would
        // mount an empty blade that can never run anything.
        let defaults = UserDefaults(suiteName: "picker-tests-\(UUID().uuidString)")!
        let registry = PluginRegistry(defaults: defaults,
                                      plugins: [SystemPlugin(), ChainPlugin(store: ChainStore(defaults: defaults))])
        try await registry.setEnabled("system", true)
        try await registry.setEnabled("chain", true)
        let model = ActionPickerModel(apps: [], registry: registry)

        let items = model.sections(context: .mainSlot, query: "").flatMap(\.items)
        #expect(!items.contains { $0.kind == .wholePlugin("chain") })
        #expect(!items.contains { if case .op("chain", _) = $0.kind { return true }; return false })
    }
```

Note: `$0.kind == .op(pluginID: "chain", opID: "demo")` — `Kind` is `Equatable`; if the compiler rejects the labeled comparison, use the `if case` form like the neighboring tests.

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/ActionPickerModelTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet`
Expected: compile failure — `type 'PickerContext' has no member 'chainStep'`.

- [ ] **Step 3: Minimal implementation**

In `ActionPickerModel.swift`, extend the context enum (lines 6-9):

```swift
/// Where the picker is being used — sub-slots have no whole-plugin mounting,
/// so the Plugins section there lists ops only; the chain builder is the
/// same (single actions are the only chain-step kind) and additionally
/// hides the Chains plugin itself (v1 has no nested chains).
enum PickerContext {
    case mainSlot
    case subSlot
    case chainStep
}
```

In `sections(context:query:)`, change the plugin loop head (line 120) from

```swift
        for plugin in registry.plugins where registry.isEnabled(plugin.id) {
```

to

```swift
        for plugin in registry.plugins
        where registry.isEnabled(plugin.id) && !plugin.operations.isEmpty {
            if case .chainStep = context, plugin.id == ChainPlugin.pluginID { continue }
```

(Zero-op plugins are skipped entirely — connected-but-empty renders nothing, which is also what keeps an empty Chains plugin out of every context.)

- [ ] **Step 4: Run to verify pass**

Run the Step 2 command. Expected: PASS — all ActionPickerModelTests including the two new ones.

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Services/ActionPickerModel.swift NemoLoopTests/ActionPickerModelTests.swift
git commit -m "feat(picker): chainStep context hides chains/whole-mounts; zero-op plugins drop out"
```

---

### Task 7: `ActionPickerPopover` outcome-callback refactor

The popover currently writes the SliceStore directly, which couples it to slot semantics. Extract a `PickerOutcome` callback so the chain builder (Task 8) can host the same popover. Pure refactor — behavior identical; the picker model tests (Task 6) already pin the data side.

**Files:**
- Modify: `NemoLoop/Settings/ActionPickerPopover.swift`
- Modify: `NemoLoop/Settings/SettingsView.swift:201-225` (popover call site + stale comment)

**Interfaces:**
- Consumes: `PickerContext` (incl. `.chainStep` from Task 6).
- Produces (Task 8 hosts on these):

```swift
enum PickerOutcome {
    case action(SlotAction)    // an app, folder, or single op — incl. browse-panel picks
    case wholePlugin(String)   // mainSlot context only, by construction
}
struct ActionPickerPopover: View {
    init(context: PickerContext,
         onPick: @escaping (PickerOutcome) -> Void,
         onDismiss: @escaping () -> Void)
}
```

  The `store: SliceStore` and `slot: Int` initializers/members are gone.

- [ ] **Step 1: Refactor the popover**

In `ActionPickerPopover.swift`:

1. Add the outcome enum above the view struct:

```swift
/// What the picker hands back to its host. Slot hosts write the SliceStore;
/// the chain builder appends a step. Decouples the popover from any one
/// destination.
enum PickerOutcome {
    /// An app, folder, or single plugin op — including picks that arrived
    /// through the browse open-panels.
    case action(SlotAction)
    /// A whole-plugin mount row — mainSlot context only, by construction.
    case wholePlugin(String)
}
```

2. Replace the members `@Bindable var store: SliceStore` and `let slot: Int` plus the init (lines 13-37) with:

```swift
struct ActionPickerPopover: View {
    let context: PickerContext
    let onPick: (PickerOutcome) -> Void
    let onDismiss: () -> Void
```

(delete the custom init entirely — the memberwise one suffices).

3. Replace `choose(_:)` (lines 138-163) with:

```swift
    private func choose(_ item: PickerItem) {
        switch item.kind {
        case .app(let entry):
            onPick(.action(.app(entry.url)))
        case .wholePlugin(let id):
            // Main-only by construction: the model never emits whole-plugin
            // items for .subSlot or .chainStep.
            onPick(.wholePlugin(id))
        case .op(let pluginID, let opID):
            onPick(.action(.pluginOp(pluginID: pluginID, opID: opID)))
        case .browseApps, .browseFolder:
            // ORDERING CONTRACT: close the popover FIRST, then run the modal
            // open panel (NSOpenPanel.runModal() over a live popover detaches
            // the popover shell on some macOS versions). Early-return: the
            // host already dismissed via onDismiss.
            onDismiss()
            runOpenPanel(kind: item.kind == .browseApps ? .appPanel : .folderPanel)
            return
        }
        onDismiss()
    }
```

4. Delete `applyByContext(_:)` (lines 165-171) and change the tail of `runOpenPanel` (line 195) from `applyByContext(kind == .appPanel ? .app(url) : .folder(url))` to:

```swift
        onPick(.action(kind == .appPanel ? .app(url) : .folder(url)))
```

5. Update the view's doc comment (lines 7-11): replace "Picking an item writes the store immediately and dismisses." with "Picking an item reports a `PickerOutcome` to the host and dismisses."

- [ ] **Step 2: Update the slot call site**

In `SettingsView.swift`, replace the popover attachment (lines 204-209) with:

```swift
        .popover(item: $pickerSlot) { target in
            ActionPickerPopover(context: target.context,
                                onPick: { outcome in pick(outcome, for: target) },
                                onDismiss: { pickerSlot = nil })
        }
```

And replace the comment block above it (lines 210-215, starting `// Whole-plugin mounts auto-expand…` through `…react to the config transition instead`) with the same first sentence but an updated mechanism note:

```swift
        // Whole-plugin mounts auto-expand their chip row: the point of the
        // mount is the plugin's op fan-out, so it unfolds the moment the pick
        // lands. Reacting to the config transition (rather than special-casing
        // the outcome in the pick handler) also covers mounts restored from
        // disk; re-mounting the same plugin (no transition) leaves the fold
        // state alone.
```

Add the pick handler inside `SettingsView` (next to `wedgeRow`, before it is fine):

```swift
    /// Translates picker outcomes into store writes: a main pick REPLACES the
    /// slot's action, a sub pick APPENDS a child, a whole-plugin pick mounts.
    private func pick(_ outcome: PickerOutcome, for target: PickerTarget) {
        switch outcome {
        case .wholePlugin(let pluginID):
            store.attachWholePlugin(pluginID, at: target.index)
        case .action(let action):
            switch target {
            case .main: store.setAction(action, at: target.index)
            case .sub: store.addChild(action, at: target.index)
            }
        }
    }
```

Verify there are no other `ActionPickerPopover(` construction sites: `grep -rn "ActionPickerPopover(" NemoLoop` must show only the popover's own definition and the SettingsView site.

- [ ] **Step 3: Run the full unit suite as the compile + behavior gate**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet`
Expected: PASS — full suite green (no behavior change).

- [ ] **Step 4: Commit**

```bash
git add NemoLoop/Settings/ActionPickerPopover.swift NemoLoop/Settings/SettingsView.swift
git commit -m "refactor(settings): ActionPickerPopover reports PickerOutcome instead of writing slots"
```

---

### Task 8: `ChainConfigSection` builder UI + wire `configSections`

**Files:**
- Create: `NemoLoop/Plugins/Chain/ChainConfigSection.swift`
- Modify: `NemoLoop/Plugins/Chain/ChainPlugin.swift` (`configSections` nil → builder)
- Test: `NemoLoopTests/ChainPluginTests.swift` (append)

**Interfaces:**
- Consumes: `ChainStore`/`ChainDefinition` (Tasks 2-3), `ActionPickerPopover(context:onPick:onDismiss:)` + `PickerContext.chainStep` (Tasks 6-7), `ActionResolver.name/symbolName(for:)` (existing).
- Produces: `struct ChainConfigSection: View` with `@Bindable var store: ChainStore`; `ChainPlugin.configSections` returns `AnyView(ChainConfigSection(store: store))`.

- [ ] **Step 1: Write the failing test**

Append to `ChainPluginTests.swift` (inside the struct):

```swift
    @Test func configSectionsExposesTheBuilder() {
        let plugin = ChainPlugin(store: ChainStore(defaults: makeDefaults()),
                                 executor: RecordingExecutor())
        #expect(plugin.configSections != nil)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/ChainPluginTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet`
Expected: FAIL — `configSections` is nil.

- [ ] **Step 3: Implement the builder**

Create `NemoLoop/Plugins/Chain/ChainConfigSection.swift`:

```swift
// NemoLoop/Plugins/Chain/ChainConfigSection.swift
import AppKit
import Luminare
import SwiftUI

/// Plugins-tab config area for Chains: the saved-chain list, each row
/// expanding inline into the editor (name, icon chips, steps with reorder,
/// repeat count, inter-step delay). "Add Step" opens the shared action
/// picker in .chainStep context. Every edit writes straight through the
/// store binding — the store clamps, and mounted blades follow via the
/// op id (the chain's UUID).
struct ChainConfigSection: View {
    @Bindable var store: ChainStore
    @State private var editingID: UUID?
    @State private var stepPicker: StepPickerTarget?

    /// `popover(item:)` needs an Identifiable anchor; UUID has none built in.
    private struct StepPickerTarget: Identifiable {
        let chainID: UUID
        var id: UUID { chainID }
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(store.chains) { chain in
                if chain.id == editingID {
                    ChainEditor(chain: binding(for: chain),
                                onAddStep: { stepPicker = StepPickerTarget(chainID: chain.id) },
                                onDelete: {
                                    store.remove(id: chain.id)
                                    editingID = nil
                                })
                } else {
                    chainRow(chain)
                }
            }
            Button {
                let chain = ChainDefinition(name: "New Chain")
                if store.add(chain) {
                    withAnimation(.smooth(duration: 0.2)) { editingID = chain.id }
                }
            } label: {
                Label("New Chain", systemImage: "plus")
            }
            .buttonStyle(.luminareCompact)
            .disabled(store.chains.count >= ChainStore.maxChains)
        }
        .popover(item: $stepPicker) { target in
            ActionPickerPopover(
                context: .chainStep,
                onPick: { outcome in
                    // chainStep context never yields .wholePlugin; the guard
                    // keeps the exhaustive switch honest anyway.
                    guard case .action(let action) = outcome,
                          let index = store.chains.firstIndex(where: { $0.id == target.chainID }),
                          store.chains[index].steps.count < ChainDefinition.maxSteps else { return }
                    var chain = store.chains[index]
                    chain.steps.append(action)
                    store.update(chain)
                },
                onDismiss: { stepPicker = nil })
        }
    }

    private func chainRow(_ chain: ChainDefinition) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.2)) { editingID = chain.id }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: chain.symbolName)
                    .font(.system(size: 14))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chain.name)
                    Text("\(chain.steps.count) step\(chain.steps.count == 1 ? "" : "s") × \(chain.repeatCount)×")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func binding(for chain: ChainDefinition) -> Binding<ChainDefinition> {
        Binding(
            get: { store.chains.first { $0.id == chain.id } ?? chain },
            set: { store.update($0) }   // store-side clamp keeps fields in spec range
        )
    }
}

/// One expanded chain: identity, icon, steps, repeat/delay, delete.
private struct ChainEditor: View {
    @Binding var chain: ChainDefinition
    let onAddStep: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $chain.name)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 6) {
                ForEach(ChainDefinition.presetSymbols, id: \.self) { symbol in
                    Button {
                        chain.symbolName = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 12))
                            .frame(width: 26, height: 20)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(chain.symbolName == symbol ? Color.accentColor.opacity(0.3) : .clear)
                    )
                }
            }

            ForEach(chain.steps.indices, id: \.self) { index in
                stepRow(index)
            }

            HStack {
                Button(action: onAddStep) {
                    Label("Add Step", systemImage: "plus")
                }
                .buttonStyle(.luminareCompact)
                .disabled(chain.steps.count >= ChainDefinition.maxSteps)
                Spacer()
                Stepper("×\(chain.repeatCount)", value: $chain.repeatCount,
                        in: ChainDefinition.minRepeatCount...ChainDefinition.maxRepeatCount)
                    .fixedSize()
                Stepper("\(chain.interStepDelay, format: .number.precision(.fractionDigits(1)))s",
                        value: $chain.interStepDelay,
                        in: 0...ChainDefinition.maxDelaySeconds, step: 0.1)
                    .fixedSize()
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete Chain", systemImage: "trash")
            }
            .buttonStyle(.luminareCompact)
        }
        .padding(.vertical, 4)
    }

    private func stepRow(_ index: Int) -> some View {
        let step = chain.steps[index]
        return HStack(spacing: 6) {
            Text("\(index + 1).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
            stepIcon(step)
            Text(ActionResolver.name(for: step))
                .lineLimit(1)
            Spacer()
            Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.luminareCompact)
                .disabled(index == 0)
            Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.luminareCompact)
                .disabled(index == chain.steps.count - 1)
            Button { chain.steps.remove(at: index) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.luminareCompact)
        }
    }

    @ViewBuilder
    private func stepIcon(_ step: SlotAction) -> some View {
        switch step {
        case .app(let url), .folder(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 16, height: 16)
        case .plugin, .pluginOp:
            Image(systemName: ActionResolver.symbolName(for: step) ?? "circle.dashed")
                .frame(width: 16)
        }
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard chain.steps.indices.contains(index), chain.steps.indices.contains(target) else { return }
        chain.steps.swapAt(index, target)
    }
}
```

Then in `ChainPlugin.swift` replace:

```swift
    /// nil until the chain-builder task wires ChainConfigSection in.
    var configSections: AnyView? { nil }
```

with:

```swift
    var configSections: AnyView? { AnyView(ChainConfigSection(store: store)) }
```

(`import SwiftUI` at the top stays — `AnyView` needs it.)

- [ ] **Step 4: Run to verify pass + full suite**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet`
Expected: PASS — full suite green.

- [ ] **Step 5: Launch the app for human inspection (repo convention: pkill first)**

```bash
pkill -x NemoLoop
xcodebuild build -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet
open ~/Library/Developer/Xcode/DerivedData/NemoLoop-*/Build/Products/Debug/NemoLoop.app --args --settings
```

Manual checklist to report to the user (they verify visually): Plugins tab → Chains card expands → "New Chain" → rename, pick icon, "Add Step" → picker shows Apps/other plugins/Folders but no Chains group and no whole-plugin rows → add 2 steps → reorder with arrows → set ×2 and 0.3s delay → close settings, mount the chain from a Ring-tab slot picker (Plugins group shows the chain by name; note: a chain with no steps does NOT appear there — it becomes pickable only after its first step) → trigger it from the ring.

- [ ] **Step 6: Commit**

```bash
git add NemoLoop/Plugins/Chain/ChainConfigSection.swift NemoLoop/Plugins/Chain/ChainPlugin.swift NemoLoopTests/ChainPluginTests.swift
git commit -m "feat(chain): builder UI in Plugins tab with inline editor and step picker"
```

---

### Task 9: Harness chain fixture ON + final verification

Flip the harness pin, widen the whole-row assertion to the 4th plugin, add a data-level Chains check, run everything.

**Files:**
- Modify: `Design/render_check_ring_tab.swift` (pin, assertion, header comment)

**Interfaces:**
- Consumes: the mirrored `ChainPlugin` seam and `registryPins` from Task 5.
- Produces: harness verifying the picker renders the Chains group (3 whole-plugin rows).

- [ ] **Step 1: Flip the pin and update assertions**

In `Design/render_check_ring_tab.swift`:

1. In `RenderCheckBootstrap.registryPins`, change `"-nemoloop.plugin.chain.enabled", "NO",` to `"-nemoloop.plugin.chain.enabled", "YES",`.
2. Update the header pin list comment accordingly (`<- 4th plugin, seam-mirrored, ON`).
3. The `sectionsComplete(gridC:headerBands:trailingBands:trailingPixels:)` function (line ~796-799) asserted `trailingBands == 2 && trailingPixels >= 24` — a third connected plugin with one op adds a third whole-plugin row and its link glyph. Change the body to:

```swift
        headerBands == 3 && trailingBands == 3 && trailingPixels >= 36 && gridC.h > 200
```

4. Update the harness's existing code-side picker checks (lines ~448-460, variables `sections` / `pluginItems` / `wholeRows` already exist there):

   - `check(wholeRows.map(\.title) == ["System", "Screenshot"], …)` → `== ["System", "Screenshot", "Chains"]` (plugin order in `registryPins`-driven enablement: System, Appearance off, Screenshot, Chains) and update the message text.
   - `check(pluginItems.count == 8 && …)` → `pluginItems.count == 10` (3 whole rows + 7 ops: System 5, Screenshot 1, Chains fixture 1); update the parenthetical in the message accordingly.

Then thread the data result into verdict 5: `sectionsComplete` (line ~796) gains the new conjunction — simplest is to `&&` the wholeRows-title check into the verdict-5 `verdict(...)` call by computing `let chainRowListed = wholeRows.map(\.title) == ["System", "Screenshot", "Chains"]` next to the existing checks and passing it into `sectionsComplete(chainRowsPresent: chainRowListed)` (extend the signature; update the verdict-5 message `2 whole rows` → `3 whole rows`).

- [ ] **Step 2: Run the harness**

Run: `swift Design/render_check_ring_tab.swift`
Expected: exits 0, `SUMMARY: all pixel checks PASS` — including verdict 5 with 3 header bands and 3 link-glyph bands. Read `Design/render_check_ring_tab.png` to eyeball the Chains row in panel C.

- [ ] **Step 3: Run the FULL unit suite one last time**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet`
Expected: PASS — everything.

- [ ] **Step 4: Final app launch for acceptance**

```bash
pkill -x NemoLoop
xcodebuild build -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet
open ~/Library/Developer/Xcode/DerivedData/NemoLoop-*/Build/Products/Debug/NemoLoop.app
```

Report to the user: suite green, harness green, app launched — hand over for hands-on acceptance (build a chain, mount, run it from the ring).

- [ ] **Step 5: Commit**

```bash
git add Design/render_check_ring_tab.swift
git commit -m "test(render): ring-tab harness covers the 4th Chains plugin row"
```

---

## Deferred (explicitly out of P0 — do not sneak in)

- Nested chains, per-step delay, continue-on-failure, step-level dim state (spec: 已知简化).
- Web / TextClip / Automation plugins (P2/P3/P7 — they reuse the ChainStore pattern).
- Keyboard macro (P8 — TCC authorization flow must be asked of the user first).
- The staged-but-uncommitted OCR diagnostic line in `OcrSessionController.swift` — leave the index untouched.
