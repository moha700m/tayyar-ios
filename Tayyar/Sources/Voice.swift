import Foundation
import AVFoundation
import AudioToolbox
import UIKit

/// Spoken Arabic guidance. Plays a bundled human recording `<cue>.m4a`/`.mp3` when present (offline),
/// otherwise falls back to the on-device Arabic system voice. No network, nothing recorded.
enum VoiceCue: String, CaseIterable {
    case finderIntro, finderPlace, finderNext, finderDone, finderProblem
    case calHold, calDone, calNoisy
    case scanStart, scanMetal, scanWire, scanTooFast, scanRecal

    var text: String {
        switch self {
        case .finderIntro: "اقلب الجوال على وجهه فوق الطاولة، وامسك مفتاح حديد"
        case .finderPlace: "حط المفتاح على الدائرة الصفرا"
        case .finderNext: "تمام، شيل المفتاح وروح للمكان اللي بعده"
        case .finderDone: "تم، لقينا مكان الحساس. اضغط احفظ"
        case .finderProblem: "فيه مشكلة، ما بان فرق واضح. جرّب مفتاح أكبر وأعد"
        case .calHold: "خل الجوال ثابت بعيد عن الجدار"
        case .calDone: "تمت المعايرة، تقدر تبدأ الفحص"
        case .calNoisy: "فيه حركة أو حديد قريب، ثبّت الجوال"
        case .scanStart: "حط ظهر الجوال على الجدار وحرّكه ببطء"
        case .scanMetal: "انتبه، فيه حديد أو معدن هنا"
        case .scanWire: "انتبه، فيه إشارة سلك كهربا عليه حمل"
        case .scanTooFast: "شوي شوي، حرّك الجوال ببطء"
        case .scanRecal: "القراءة انحرفت، أعد المعايرة"
        }
    }
    var isWarning: Bool { [.finderProblem, .scanMetal, .scanWire, .scanTooFast, .scanRecal, .calNoisy].contains(self) }
    var isSuccess: Bool { [.finderNext, .finderDone, .calDone].contains(self) }
}

final class VoiceGuide: NSObject {
    static let shared = VoiceGuide()
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var last: [VoiceCue: Date] = [:]
    private let notify = UINotificationFeedbackGenerator()
    var enabled: Bool { UserDefaults.standard.object(forKey: "voice") as? Bool ?? true }

    static func configureSession() {
        // mix with other audio and duck it; never record
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Bundled recording URL, if any.
    static func bundledURL(_ c: VoiceCue) -> URL? {
        for ext in ["m4a", "mp3"] { if let u = Bundle.main.url(forResource: c.rawValue, withExtension: ext) { return u } }
        return nil
    }

    func say(_ c: VoiceCue, minGap: TimeInterval = 3) {
        let now = Date()
        if let l = last[c], now.timeIntervalSince(l) < minGap { return }
        last[c] = now
        if c.isSuccess { notify.notificationOccurred(.success); AudioServicesPlaySystemSound(1057) }
        else if c.isWarning { notify.notificationOccurred(.warning) }
        guard enabled else { return }
        VoiceGuide.configureSession()
        if let u = VoiceGuide.bundledURL(c), let p = try? AVAudioPlayer(contentsOf: u) {
            synth.stopSpeaking(at: .immediate); player?.stop(); player = p; p.play(); return
        }
        if synth.isSpeaking { synth.stopSpeaking(at: .word) }
        let u = AVSpeechUtterance(string: c.text)
        u.voice = AVSpeechSynthesisVoice(language: "ar-SA") ?? AVSpeechSynthesisVoice(language: "ar")
        u.rate = 0.48
        synth.speak(u)
    }
}

/// Local scan history (UserDefaults JSON, on device only).
struct ScanRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var kind: String      // "metal" | "wire"
    var peak: Int         // 0–100
}

enum ScanHistory {
    static let key = "scanHistory"
    static func load(_ d: UserDefaults = .standard) -> [ScanRecord] {
        guard let data = d.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ScanRecord].self, from: data)) ?? []
    }
    static func add(_ r: ScanRecord, _ d: UserDefaults = .standard) {
        var all = load(d); all.insert(r, at: 0); if all.count > 200 { all.removeLast(all.count - 200) }
        d.set(try? JSONEncoder().encode(all), forKey: key)
    }
    static func clear(_ d: UserDefaults = .standard) { d.removeObject(forKey: key) }
}

/// Geiger-style click interval: no clicks when quiet, ~2/s at low signal up to ~16/s at full scale.
enum Geiger {
    static func interval(score: Double) -> Double? {
        guard score > 0.08 else { return nil }
        return 1 / (2 + 14 * min(1, score))
    }
}
