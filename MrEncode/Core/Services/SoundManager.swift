//
//  SoundManager.swift
//  MrEncode
//
//  Created by scott ulrich on 1/13/26.
//


import Foundation
import AVFoundation

@MainActor
final class SoundManager {
    static let shared = SoundManager()
    private var player: AVAudioPlayer?

    private init() {}

    func playDoneChime() {
        let name = "MrEncode_DONE"
        let ext = "wav"

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            NSLog("MrEncode SoundManager: NOT FOUND in bundle: \(name).\(ext)")
            return
        }

        // NSLog("MrEncode SoundManager: will play \(url.lastPathComponent)")

        do {
            let p = try AVAudioPlayer(contentsOf: url)

            NSLog(
                "MrEncode SoundManager: duration=%.3fs channels=%d",
                p.duration,
                p.numberOfChannels
            )

            let vol = Float(AppCore.shared.settings.doneChimeVolume)
            p.volume = max(0.0, min(vol, 1.0))
            p.prepareToPlay()
            let ok = p.play()

            // NSLog("MrEncode SoundManager: play() returned \(ok)")

            self.player = p // retain during playback
        } catch {
            // NSLog("MrEncode SoundManager: FAILED to init AVAudioPlayer: \(error)")
        }
    }
}
