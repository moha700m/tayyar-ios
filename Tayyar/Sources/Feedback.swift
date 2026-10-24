import UIKit
import AVFoundation

final class FeedbackController {
    private let haptic = UIImpactFeedbackGenerator(style: .heavy)
    private var timer: Timer?
    private var lastHaptic = Date.distantPast
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var phase: Double = 0
    fileprivate var freq: Double = 300
    fileprivate var amp: Double = 0
    var soundOn = true
    var hapticsOn = true

    init() {
        let sr = 44100.0
        let node = AVAudioSourceNode { [unowned self] _, _, frames, abl -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            let inc = 2 * Double.pi * self.freq / sr
            let a = Float(self.amp)
            for i in 0..<Int(frames) {
                let v = Float(sin(self.phase)) * a
                self.phase += inc
                if self.phase > 2 * Double.pi { self.phase -= 2 * Double.pi }
                for b in list { b.mData?.assumingMemoryBound(to: Float.self)[i] = v }
            }
            return noErr
        }
        source = node
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
    }

    func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning { try? engine.start() }
        haptic.prepare()
    }

    func stop() { amp = 0; engine.pause() }

    func update(score: Double) {
        freq = 260 + score * 1100
        amp = soundOn && score > 0.08 ? 0.05 + 0.25 * score : 0
        guard hapticsOn, score > 0.15 else { return }
        let interval = 0.6 - 0.5 * score
        if Date().timeIntervalSince(lastHaptic) > interval {
            lastHaptic = Date()
            haptic.impactOccurred(intensity: CGFloat(min(1, 0.3 + score)))
        }
    }
}
