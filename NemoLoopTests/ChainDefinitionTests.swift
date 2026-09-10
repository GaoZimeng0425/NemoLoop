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
