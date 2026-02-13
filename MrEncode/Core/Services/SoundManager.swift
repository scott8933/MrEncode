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
            return
        }


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


            self.player = p // retain during playback
        } catch {
        }
    }
}
