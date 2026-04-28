import AVFoundation
import Foundation

@MainActor
final class PetAudioService {
    private var players: [AVAudioPlayer] = []

    init() {
        for i in 1...10 {
            if let player = Self.loadPlayer(resourceName: "shiba\(i)", fileExtension: "mp3") {
                players.append(player)
            }
        }

        for i in 1...10 {
            let player = Self.loadPlayer(resourceName: "purr\(i)", fileExtension: "mp3")
                ?? Self.loadPlayer(resourceName: "purr\(i)", fileExtension: "wav")
            if let player {
                players.append(player)
            }
        }

        if players.isEmpty, let player = Self.loadPlayer(resourceName: "shiba1", fileExtension: "mp3") {
            players.append(player)
        }

        NSLog("[petOS] PetAudioService init; total sounds loaded=\(players.count)")
    }

    private var stopTask: Task<Void, Never>?

    func playRandomSound() {
        guard let player = players.randomElement() else {
            NSLog("[petOS] no audio files available")
            return
        }

        stopTask?.cancel()
        players.forEach { $0.stop() }

        player.currentTime = 0
        let didPlay = player.play()
        NSLog("[petOS] playRandomSound called; didPlay=\(didPlay) volume=\(player.volume) duration=\(player.duration)")

        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            player.stop()
            self?.stopTask = nil
        }
    }

    private static func loadPlayer(resourceName: String, fileExtension: String) -> AVAudioPlayer? {
        let resourceBundle = PetResourceBundle.bundle
        let candidateURLs = [
            resourceBundle.url(forResource: resourceName, withExtension: fileExtension),
            resourceBundle.url(forResource: resourceName, withExtension: fileExtension, subdirectory: "Sounds"),
            resourceBundle.url(forResource: resourceName, withExtension: fileExtension, subdirectory: "Resources/Sounds")
        ]

        guard let url = candidateURLs.compactMap({ $0 }).first else {
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            return player
        } catch {
            NSLog("[petOS] failed to load audio '\(resourceName)': \(error.localizedDescription)")
            return nil
        }
    }
}
