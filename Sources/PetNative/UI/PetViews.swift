import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: PetAppModel

    var body: some View {
        ZStack {
            Color.clear
            PetStageView(
                mood: model.currentMood,
                worldState: model.worldState,
                reactionVariant: model.reactionVariant,
                reactionToken: model.reactionToken,
                notificationToken: model.notificationToken
            )
        }
        .frame(width: AppConstants.windowSize.width, height: AppConstants.windowSize.height)
        .background(WindowAccessor { model.attachWindow($0) })
        .onTapGesture {
            model.handleSoundGesture()
        }
        .contextMenu {
            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Divider()
            Button("Recenter", action: model.recenterWindow)
            Button("Reset Pet", action: model.resetPet)
            Button("Reload Sprites", action: model.reloadSprites)
            Button(model.soundEnabled ? "Disable Sound" : "Enable Sound", action: model.toggleSound)
            if model.debugEnabled {
                Divider()
                Button("Cycle Mood", action: model.cycleDebugMood)
                Button("Clear Mood Override", action: model.clearDebugMoodOverride)
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .task {
            model.start()
        }
    }
}

struct PetStageView: View {
    let mood: PetMood
    let worldState: WorldState
    let reactionVariant: ReactionVariant
    let reactionToken: UUID?
    let notificationToken: UUID?

    @State private var showReaction = false

    var body: some View {
        ZStack(alignment: .bottom) {
            auraView
                .frame(width: 124, height: 90)
                .offset(y: -72)
                .opacity(worldState.music.playing ? 0.38 : 0.28)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.16, green: 0.11, blue: 0.08, opacity: 0.34),
                            Color(red: 0.16, green: 0.11, blue: 0.08, opacity: 0.16),
                            Color(red: 0.16, green: 0.11, blue: 0.08, opacity: 0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 48
                    )
                )
                .frame(
                    width: PetSpriteCatalog.configuration(for: mood).shadowSize.width,
                    height: PetSpriteCatalog.configuration(for: mood).shadowSize.height
                )
                .blur(radius: 6)
                .opacity(showReaction ? 0.52 : 0.42)
                .offset(y: -24)

            if showReaction {
                ReactionBurstView(variant: reactionVariant)
                    .frame(width: 90, height: 90)
                    .offset(y: -112)
                    .transition(.scale.combined(with: .opacity))
            }

            PetSpriteView(mood: mood, animationToken: mood == .alert ? notificationToken : nil)
                .offset(y: -34)
        }
        .frame(width: 220, height: 220, alignment: .bottom)
        .modifier(StageSunTintModifier(sunPhase: worldState.sunPhase))
        .animation(.easeOut(duration: 0.18), value: worldState.sunPhase)
        .animation(.easeOut(duration: 0.18), value: showReaction)
        .onChange(of: reactionToken) { _, token in
            guard token != nil else {
                return
            }

            triggerReactionAnimation()
        }
    }

    private var auraView: some View {
        let colors = auraColors(sunPhase: worldState.sunPhase)

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors.primary, .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 56
                    )
                )
                .scaleEffect(x: 1.2, y: 0.88)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors.secondary, .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 64
                    )
                )
                .scaleEffect(x: 1.1, y: 0.78)
                .offset(y: 12)
        }
        .blur(radius: 10)
        .saturation(worldState.music.playing ? 1.05 : 0.95)
    }

    private func triggerReactionAnimation() {
        showReaction = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            showReaction = false
        }
    }

    private func auraColors(sunPhase: SunPhase) -> (primary: Color, secondary: Color) {
        switch sunPhase {
        case .night:
            return (Color(red: 0.52, green: 0.66, blue: 1, opacity: 0.14), Color(red: 0.42, green: 0.92, blue: 1, opacity: 0.09))
        case .golden, .dusk:
            return (Color(red: 1, green: 0.77, blue: 0.47, opacity: 0.18), Color(red: 1, green: 0.56, blue: 0.47, opacity: 0.10))
        case .dawn:
            return (Color(red: 1, green: 0.8, blue: 0.60, opacity: 0.18), Color(red: 1, green: 0.9, blue: 0.74, opacity: 0.11))
        default:
            return (Color(red: 0.48, green: 0.89, blue: 0.82, opacity: 0.18), Color(red: 1, green: 0.82, blue: 0.49, opacity: 0.12))
        }
    }
}

private struct StageSunTintModifier: ViewModifier {
    let sunPhase: SunPhase

    func body(content: Content) -> some View {
        switch sunPhase {
        case .dawn:
            content
                .hueRotation(.degrees(-8))
                .brightness(0.05)
        case .day:
            content
        case .golden:
            content
                .saturation(1.08)
                .brightness(0.02)
        case .dusk:
            content
                .saturation(0.95)
                .brightness(-0.05)
        case .night:
            content
                .brightness(-0.15)
                .contrast(1.05)
        }
    }
}

struct ReactionBurstView: View {
    let variant: ReactionVariant

    @State private var scale: CGFloat = 0.78
    @State private var opacity: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 2)
                .frame(width: 30, height: 30)

            ForEach(0 ..< particleOffsets.count, id: \.self) { index in
                particleView(at: index)
            }
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.22)) {
                opacity = 1
                scale = 1
            }

            withAnimation(.easeOut(duration: 1.6).delay(0.2)) {
                opacity = 0
                scale = 1.18
            }
        }
    }

    private var coreColor: Color {
        switch variant {
        case .sparkle:
            return Color(red: 0.44, green: 1, blue: 0.89, opacity: 0.95)
        case .heart:
            return Color(red: 1, green: 0.51, blue: 0.69, opacity: 0.92)
        case .zap:
            return Color(red: 0.48, green: 0.83, blue: 1, opacity: 0.90)
        case .pulse:
            return Color.white.opacity(0.92)
        }
    }

    private var borderColor: Color {
        switch variant {
        case .sparkle:
            return Color.white.opacity(0.94)
        case .heart:
            return Color(red: 1, green: 0.58, blue: 0.76, opacity: 0.42)
        case .zap:
            return Color(red: 0.48, green: 0.83, blue: 1, opacity: 0.50)
        case .pulse:
            return Color(red: 0.37, green: 0.88, blue: 0.76, opacity: 0.52)
        }
    }

    private var particleOffsets: [CGSize] {
        switch variant {
        case .sparkle:
            return [
                CGSize(width: -18, height: -10),
                CGSize(width: 18, height: -10),
                CGSize(width: -22, height: 10),
                CGSize(width: 20, height: 12),
                CGSize(width: 0, height: -22),
                CGSize(width: 0, height: 20)
            ]
        case .heart:
            return [
                CGSize(width: -6, height: -6),
                CGSize(width: 6, height: -6),
                CGSize(width: 0, height: 6),
                CGSize(width: -12, height: 12),
                CGSize(width: 12, height: 12)
            ]
        case .zap:
            return [
                CGSize(width: -18, height: -10),
                CGSize(width: 18, height: -10),
                CGSize(width: -10, height: 0),
                CGSize(width: 10, height: 0),
                CGSize(width: 0, height: 16),
                CGSize(width: 0, height: -18)
            ]
        case .pulse:
            return [
                CGSize(width: -18, height: -10),
                CGSize(width: 18, height: -10),
                CGSize(width: -22, height: 10),
                CGSize(width: 20, height: 12),
                CGSize(width: 0, height: -22),
                CGSize(width: 0, height: 20)
            ]
        }
    }

    @ViewBuilder
    private func particleView(at index: Int) -> some View {
        RoundedRectangle(cornerRadius: variant == .heart ? 4 : 2)
            .fill(coreColor)
            .frame(width: 8, height: 8)
            .offset(particleOffsets[index])
    }
}
