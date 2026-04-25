import Testing
@testable import PetNative

struct PetSpriteCatalogTests {
    @MainActor
    @Test
    func everyMoodConfigurationOnlyReferencesLoadableSpriteAssets() {
        for mood in PetMood.allCases {
            let configuration = PetSpriteCatalog.configuration(for: mood)
            #expect(!configuration.frames.isEmpty)

            for frame in configuration.frames {
                #expect(PetSpriteCatalog.image(named: frame.name) != nil)
            }
        }
    }

    @MainActor
    @Test
    func reducedSpriteSetsAnimateSlightlySlower() {
        let specs: [PetMood: (baseDurationMilliseconds: UInt64, nominalFrameCount: Int)] = [
            .sick: (240, 1),
            .idle: (210, 6),
            .alert: (150, 6),
            .sleeping: (320, 6),
            .working: (170, 6),
            .dancing: (140, 6)
        ]

        for (mood, spec) in specs {
            let configuration = PetSpriteCatalog.configuration(for: mood)
            let missingFrameCount = max(spec.nominalFrameCount - configuration.frames.count, 0)
            let expectedDurationMilliseconds = spec.baseDurationMilliseconds + UInt64(missingFrameCount) * 15

            #expect(configuration.frameDurationMilliseconds == expectedDurationMilliseconds)
        }
    }
}
