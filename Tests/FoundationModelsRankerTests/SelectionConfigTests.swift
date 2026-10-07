import FoundationModelsRanker
import Testing

/// Tests for `SelectionConfig`'s defaults, budget clamping, and the
/// `.selectionDefault` preamble's neutral wording.
struct SelectionConfigTests {
    // MARK: - Defaults

    @Test
    func defaultCapacityLimitMatchesTheNamedConstant() {
        let config = SelectionConfig(model: ScriptedLanguageModel([]))

        #expect(config.capacityCharacterLimit == SelectionConfig.defaultCapacityCharacterLimit)
    }

    @Test
    func defaultPreambleIsSelectionDefault() {
        let config = SelectionConfig(model: ScriptedLanguageModel([]))

        #expect(config.preamble == .selectionDefault)
    }

    // MARK: - Clamping

    @Test
    func negativeCapacityCharacterLimitClampsToZero() {
        let config = SelectionConfig(model: ScriptedLanguageModel([]), capacityCharacterLimit: -1)

        #expect(config.capacityCharacterLimit == 0)
    }

    @Test
    func positiveCapacityLimitPassesThroughUnclamped() {
        let config = SelectionConfig(model: ScriptedLanguageModel([]), capacityCharacterLimit: 1_234)

        #expect(config.capacityCharacterLimit == 1_234)
    }

    // MARK: - `.selectionDefault` neutral wording

    @Test
    func selectionDefaultUsesNeutralCandidateAndIdLanguage() {
        let preamble = String.selectionDefault

        #expect(preamble.contains("Each candidate below has an id and a description."))
    }

    @Test
    func selectionDefaultTellsTheModelToCopyEachIdExactlyFromItsIdLine() {
        // A real model shortened a URI id to its last path part. The
        // preamble must say that an id is copied whole, from its `id:` line.
        let preamble = String.selectionDefault

        #expect(preamble.contains(#"Copy each id exactly as it is written after"#))
        #expect(preamble.contains(#""id:", character for character, with its full scheme, path and punctuation."#))
        #expect(preamble.contains("do not shorten it, change it or make one up."))
    }

    @Test
    func selectionDefaultContainsNoDomainSpecificLanguage() {
        let preamble = String.selectionDefault.lowercased()

        #expect(!preamble.contains("function"))
        #expect(!preamble.contains("librarian"))
        #expect(!preamble.contains("api"))
    }
}
