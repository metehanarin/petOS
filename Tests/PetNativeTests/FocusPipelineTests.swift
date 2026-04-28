import Foundation
import Testing
@testable import PetNative

@MainActor
struct FocusPipelineTests {
    @Test
    func allSourcesFailLeavesFocusInactive() async {
        let fake = FakeFocusSourceProvider()
        let (model, coord) = makeModelAndCoordinator(fake: fake)

        await coord.refreshFocusForTest()

        #expect(model.worldState.focus.active == false)
    }

    @Test
    func inFocusActiveWithNoDescriptorResolvesSleeping() async {
        let fake = FakeFocusSourceProvider()
        fake.inFocusResult = (authorized: true, isFocused: true)
        let (model, coord) = makeModelAndCoordinator(fake: fake)

        await coord.refreshFocusForTest()

        #expect(model.worldState.focus.active == true)
        #expect(model.worldState.focus.modeIdentifier == nil)
        let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: model.worldState)
        #expect(resolution.mood == .sleeping)
        #expect(resolution.reason == .unidentifiedFocusAssumedSleep)
    }

    @Test
    func doNotDisturbDescriptorResolvesSleeping() async {
        let fake = FakeFocusSourceProvider()
        fake.assertionsResult = FocusModeDescriptor(identifier: "com.apple.donotdisturb", name: "Do Not Disturb")
        let (model, coord) = makeModelAndCoordinator(fake: fake)

        await coord.refreshFocusForTest()

        let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: model.worldState)
        #expect(resolution.mood == .sleeping)
        #expect(resolution.reason == .doNotDisturbFocus)
    }

    @Test
    func assertionsSleepDescriptorTakesPriorityOverControlCenter() async {
        let fake = FakeFocusSourceProvider()
        fake.assertionsResult = FocusModeDescriptor(identifier: "com.apple.focus.sleep", name: "Sleep")
        fake.controlCenterResult = FocusModeDescriptor(identifier: "com.apple.focus.work", name: "Work")
        let (model, coord) = makeModelAndCoordinator(fake: fake)

        await coord.refreshFocusForTest()

        #expect(model.worldState.focus.modeIdentifier == "com.apple.focus.sleep")
    }

    @Test
    func controlCenterFallsThroughWhenAssertionsEmpty() async {
        let fake = FakeFocusSourceProvider()
        fake.assertionsResult = nil
        fake.controlCenterResult = FocusModeDescriptor(identifier: "com.apple.focus.sleep", name: "Sleep")
        let (model, coord) = makeModelAndCoordinator(fake: fake)

        await coord.refreshFocusForTest()

        #expect(model.worldState.focus.modeIdentifier == "com.apple.focus.sleep")
    }

    @Test
    func partialDescriptorWithSleepNameOnlyResolvesSleeping() async {
        let fake = FakeFocusSourceProvider()
        fake.assertionsResult = FocusModeDescriptor(identifier: "", name: "Sleep")
        fake.inFocusResult = (authorized: true, isFocused: true)
        let (model, coord) = makeModelAndCoordinator(fake: fake)

        await coord.refreshFocusForTest()

        #expect(PetMoodEngine.resolveBaseMood(for: model.worldState) == .sleeping)
    }

    @Test
    func protectedLookupControlCenterDescriptorReportsControlCenterSource() async {
        let fake = FakeFocusSourceProvider()
        fake.focusModeLookupProtected = true
        fake.controlCenterResult = FocusModeDescriptor(identifier: "com.apple.focus.sleep", name: "Sleep")
        let (model, coord) = makeModelAndCoordinator(fake: fake)

        await coord.refreshFocusForTest()

        #expect(model.worldState.focus.source == "control-center")
    }

    @Test
    func protectedLookupOnlyInFocusActiveReportsProtectedStatusSource() async {
        let fake = FakeFocusSourceProvider()
        fake.focusModeLookupProtected = true
        fake.inFocusResult = (authorized: true, isFocused: true)
        let (model, coord) = makeModelAndCoordinator(fake: fake)

        await coord.refreshFocusForTest()

        #expect(model.worldState.focus.source == "protected-mode-status")
        let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: model.worldState)
        #expect(resolution.mood == .sleeping)
        #expect(resolution.reason == .unidentifiedFocusAssumedSleep)
    }

    private func makeModelAndCoordinator(fake: FakeFocusSourceProvider) -> (PetAppModel, PetMonitorCoordinator) {
        let persistence = PetPersistence(fileURL: PetTestSupport.temporaryFileURL())
        let model = PetAppModel(arguments: [], persistence: persistence)
        model.updateWorldState { state in
            state.hour = 12
            state.sunPhase = SunPhase.resolve(for: state.hour)
        }
        let coord = PetMonitorCoordinator(
            model: model,
            persistence: persistence,
            focusSourceProvider: fake
        )
        return (model, coord)
    }
}

@MainActor
final class FakeFocusSourceProvider: FocusSourceProvider {
    var focusModeLookupProtected = false
    var assertionsResult: FocusModeDescriptor?
    var controlCenterResult: FocusModeDescriptor?
    var inFocusResult: (authorized: Bool, isFocused: Bool) = (false, false)

    func readAssertionsFile() -> FocusModeDescriptor? { assertionsResult }
    func scrapeControlCenter() -> FocusModeDescriptor? { controlCenterResult }
    func queryInFocusStatus() async -> (authorized: Bool, isFocused: Bool) { inFocusResult }
}
