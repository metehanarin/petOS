import AVFoundation
import Foundation

@MainActor
final class PetAudioService {
    private var players: [AVAudioPlayer] = []

    init() {
        for i in 1...10 {
            if let player = Self.loadPlayer(resourceName: "meow\(i)", fileExtension: "mp3") {
                players.append(player)
            }
        }

        for i in 1...10 {
            if let player = Self.loadPlayer(resourceName: "purr\(i)", fileExtension: "mp3") {
                players.append(player)
            }
        }

        if players.isEmpty, let player = Self.loadPlayer(resourceName: "meow", fileExtension: "mp3") {
            players.append(player)
        }

        NSLog("[PetNative] PetAudioService init; total sounds loaded=\(players.count)")
    }

    func playRandomSound() {
        guard let player = players.randomElement() else {
            NSLog("[PetNative] no audio files available")
            return
        }

        player.currentTime = 0
        let didPlay = player.play()
        NSLog("[PetNative] playRandomSound called; didPlay=\(didPlay) volume=\(player.volume) duration=\(player.duration)")
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
            NSLog("[PetNative] failed to load audio '\(resourceName)': \(error.localizedDescription)")
            return nil
        }
    }
}
