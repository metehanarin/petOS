import AppKit
import SwiftUI

struct PetSpriteFrame {
    var name: String
    var offset: CGSize = .zero
}

struct PetSpriteConfiguration {
    var size: CGSize
    var shadowSize: CGSize
    var frames: [PetSpriteFrame]
    var frameDurationMilliseconds: UInt64
}

@MainActor
enum PetSpriteCatalog {
    private static let cache = NSCache<NSString, NSImage>()
    private static let spriteSize = CGSize(width: 160, height: 160)
    private static let shortSpriteSetFrameDelayMilliseconds: UInt64 = 15

    static func clearCache() {
        cache.removeAllObjects()
    }

    private struct MoodSpriteSpec {
        var shadowSize: CGSize
        var frames: [PetSpriteFrame]
        var fallbackFrames: [PetSpriteFrame] = []
        var nominalFrameCount: Int
        var frameDurationMilliseconds: UInt64
    }

    static func configuration(for mood: PetMood) -> PetSpriteConfiguration {
        let spec = spriteSpec(for: mood)
        let primaryFrames = loadableFrames(from: spec.frames)
        let frames = primaryFrames.isEmpty ? loadableFrames(from: spec.fallbackFrames) : primaryFrames

        return PetSpriteConfiguration(
            size: spriteSize,
            shadowSize: spec.shadowSize,
            frames: frames,
            frameDurationMilliseconds: adjustedFrameDurationMilliseconds(
                base: spec.frameDurationMilliseconds,
                nominalFrameCount: spec.nominalFrameCount,
                actualFrameCount: frames.count
            )
        )
    }

    static func image(named name: String) -> NSImage? {
        if let cached = cache.object(forKey: name as NSString) {
            return cached
        }

        let candidateURLs = [
            Bundle.module.url(forResource: name, withExtension: "png"),
            Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Sprites/Moods"),
            Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Resources/Sprites/Moods")
        ]

        guard
            let url = candidateURLs.compactMap({ $0 }).first,
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        cache.setObject(image, forKey: name as NSString)
        return image
    }

    private static func spriteSpec(for mood: PetMood) -> MoodSpriteSpec {
        switch mood {
        case .sick:
            return MoodSpriteSpec(
                shadowSize: CGSize(width: 96, height: 18),
                frames: [PetSpriteFrame(name: "sick-05")],
                nominalFrameCount: 1,
                frameDurationMilliseconds: 240
            )
        case .idle:
            return MoodSpriteSpec(
                shadowSize: CGSize(width: 88, height: 16),
                frames: numberedFrames(prefix: "idle"),
                nominalFrameCount: 6,
                frameDurationMilliseconds: 210
            )
        case .sleeping:
            return MoodSpriteSpec(
                shadowSize: CGSize(width: 96, height: 18),
                frames: ["01", "02", "03", "04", "06", "04"].map { PetSpriteFrame(name: "sleeping-\($0)") },
                nominalFrameCount: 6,
                frameDurationMilliseconds: 320
            )
        case .dancing:
            return MoodSpriteSpec(
                shadowSize: CGSize(width: 86, height: 16),
                frames: [
                    PetSpriteFrame(name: "dancing-01"),
                    PetSpriteFrame(name: "dancing-02"),
                    PetSpriteFrame(name: "dancing-03"),
                    PetSpriteFrame(name: "dancing-04", offset: CGSize(width: 0, height: 14)),
                    PetSpriteFrame(name: "dancing-05", offset: CGSize(width: 0, height: 24)),
                    PetSpriteFrame(name: "dancing-06", offset: CGSize(width: 0, height: 14))
                ],
                nominalFrameCount: 6,
                frameDurationMilliseconds: 140
            )
        case .working:
            return MoodSpriteSpec(
                shadowSize: CGSize(width: 92, height: 16),
                frames: numberedFrames(prefix: "working"),
                fallbackFrames: numberedFrames(prefix: "focused"),
                nominalFrameCount: 6,
                frameDurationMilliseconds: 170
            )
        case .alert:
            return MoodSpriteSpec(
                shadowSize: CGSize(width: 90, height: 16),
                frames: numberedFrames(prefix: "alert"),
                nominalFrameCount: 6,
                frameDurationMilliseconds: 150
            )
        }
    }

    private static func numberedFrames(prefix: String) -> [PetSpriteFrame] {
        (1 ... 6).map { PetSpriteFrame(name: "\(prefix)-\(String(format: "%02d", $0))") }
    }

    private static func loadableFrames(from frames: [PetSpriteFrame]) -> [PetSpriteFrame] {
        frames.filter { image(named: $0.name) != nil }
    }

    private static func adjustedFrameDurationMilliseconds(
        base: UInt64,
        nominalFrameCount: Int,
        actualFrameCount: Int
    ) -> UInt64 {
        guard actualFrameCount > 0, actualFrameCount < nominalFrameCount else {
            return base
        }

        let missingFrameCount = nominalFrameCount - actualFrameCount
        return base + UInt64(missingFrameCount) * shortSpriteSetFrameDelayMilliseconds
    }
}

struct PetSpriteView: View {
    let mood: PetMood
    var animationToken: UUID?

    @State private var frameIndex = 0

    var body: some View {
        let configuration = PetSpriteCatalog.configuration(for: mood)
        let frame = configuration.frames.isEmpty
            ? nil
            : configuration.frames[min(frameIndex, configuration.frames.count - 1)]

        Group {
            if let frame, let image = PetSpriteCatalog.image(named: frame.name) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 0.96, green: 0.92, blue: 0.88))
                    .overlay(
                        Text(mood.rawValue.capitalized)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: configuration.size.width, height: configuration.size.height)
        .offset(frame?.offset ?? .zero)
        .task(id: "\(mood.rawValue)-\(animationToken?.uuidString ?? "none")") {
            await animate(with: configuration)
        }
    }

    @MainActor
    private func animate(with configuration: PetSpriteConfiguration) async {
        frameIndex = 0
        guard configuration.frames.count > 1 else {
            return
        }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .milliseconds(configuration.frameDurationMilliseconds))
            } catch {
                return
            }

            frameIndex = (frameIndex + 1) % configuration.frames.count
        }
    }
}

