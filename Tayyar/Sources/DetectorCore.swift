import Foundation

/// Pure, testable detection core (no CoreMotion). Two input streams:
///  - `ingestField`: hard-iron-corrected field (deviceMotion.magneticField) + gyro rate → metal channel
///  - `ingestRaw`:   raw magnetometer vector → mains-hum channel (offsets don't matter for AC)
/// All times are seconds. Field in µT.
public final class DetectorCore {
    public struct Config {
        public var warmup = 0.6              // s discarded after (re)start: sensor/filter transients
        public var calWindow = 1.5           // s of still data required
        public var calMaxStd = 0.8           // µT; baseline only accepted when this quiet
        public var calTimeout = 12.0         // s; then accept best window with honest warning
        public var metalDeadbandMin = 3.0    // µT
        public var metalDeadbandSigma = 6.0  // × calibration σ
        public var metalFullScale = 25.0     // µT above deadband → score 1
        public var metalTau = 0.12           // s EMA after median
        public var metalDwell = 0.15         // s above threshold before "likely"
        public var rotationSuppress = 2.5    // rad/s: above this, don't escalate (fast hand twist)
        public var driftTau = 25.0           // s; baseline follows slow drift only while quiet
        public var driftRecal = 8.0          // µT of accumulated drift → ask for recalibration
        public var humN = 128                // samples per Goertzel window (~1.3 s @100 Hz)
        public var humHop = 10               // analyse every N raw samples (~0.1 s)
        public var humMinSNR = 10.0          // dB above neighbour floor
        public var humAboveCal = 8.0         // dB above calibration SNR
        public var humDwell = 1.0            // s continuously high before "likely"
        public var humRelease = 0.1         // s low (short window) before clearing
        public var humShortN = 48            // short window used only for fast release
        public var offsetStuck = 4.0         // s of flat, unchanging deviation → treat as sensor offset shift
        public var mainsHz = 60.0
        public init() {}
    }
    public enum Phase: Equatable { case idle, warmup, calibrating, ready }

    public var cfg: Config
    public private(set) var phase: Phase = .idle
    // outputs
    public private(set) var metalScore = 0.0, humScore = 0.0
    public private(set) var metalLikely = false, humLikely = false
    public private(set) var deviation = 0.0, snrDB = 0.0, aliasHz = 0.0, fs = 0.0
    public private(set) var humMeasurable = false
    public private(set) var baseline: Double?, baselineStd = 0.0, baselineSNR = 0.0
    public private(set) var calibrationProgress = 0.0
    public private(set) var calibrationTooNoisy = false   // user moving / near metal during cal
    public private(set) var needsRecalibration = false
    public private(set) var suppressedByMotion = false
    public private(set) var spectrum: [(Double, Double)] = []
    public var score: Double { max(humScore, metalScore) }

    private var startT: Double?
    private var calBuf: [(Double, Double)] = []
    private var calStart: Double?
    private var bestCal: (mean: Double, std: Double)?
    private var med: [Double] = []
    private var ema: Double?
    private var lastFieldT: Double?
    private var metalAboveSince: Double?
    private var driftAccum = 0.0
    private var flatSince: Double?, flatRef = 0.0
    private var shortPeak = 0.0
    private var bx: [Double] = [], by: [Double] = [], bz: [Double] = [], ts: [Double] = []
    private var hop = 0
    private var humAboveSince: Double?, humBelowSince: Double?
    private var calSNRs: [Double] = []
    private var spectrumCounter = 0

    public init(_ cfg: Config = Config()) { self.cfg = cfg }

    public func startCalibration() {
        phase = .warmup; startT = nil; calBuf = []; calStart = nil; bestCal = nil
        baseline = nil; calSNRs = []; calibrationProgress = 0; calibrationTooNoisy = false
        needsRecalibration = false; driftAccum = 0
        resetOutputs()
    }
    private func resetOutputs() {
        metalScore = 0; humScore = 0; metalLikely = false; humLikely = false; deviation = 0
        med = []; ema = nil; metalAboveSince = nil; humAboveSince = nil; humBelowSince = nil
    }

    public static func alias(_ f: Double, fs: Double) -> Double {
        guard fs > 0 else { return 0 }
        return abs(f - fs * (f / fs).rounded())
    }

    // MARK: metal / DC channel
    public func ingestField(t: Double, x: Double, y: Double, z: Double, gyro: Double) {
        let m = (x * x + y * y + z * z).squareRoot()
        guard m > 1 else { return }   // deviceMotion not calibrated yet
        if startT == nil { startT = t }
        switch phase {
        case .idle: return
        case .warmup:
            if t - startT! >= cfg.warmup { phase = .calibrating; calStart = t }
            return
        case .calibrating:
            calBuf.append((t, m))
            calBuf.removeAll { t - $0.0 > cfg.calWindow }
            let span = (calBuf.last?.0 ?? t) - (calBuf.first?.0 ?? t)
            let vals = calBuf.map { $0.1 }
            let mean = vals.reduce(0, +) / Double(max(1, vals.count))
            let std = (vals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(1, vals.count))).squareRoot()
            if span >= cfg.calWindow * 0.95 {
                if bestCal == nil || std < bestCal!.std { bestCal = (mean, std) }
                calibrationTooNoisy = std > cfg.calMaxStd || gyro > 0.5
                if !calibrationTooNoisy && humReadyForCal() { finishCal(mean: mean, std: std); return }
                if t - calStart! > cfg.calTimeout, let b = bestCal { finishCal(mean: b.mean, std: b.std); return }
            }
            let still = std <= cfg.calMaxStd && gyro <= 0.5
            calibrationProgress = still ? min(0.99, span / cfg.calWindow) : min(calibrationProgress, 0.3)
            if !still && vals.count > 10 { calibrationTooNoisy = true; calBuf = Array(calBuf.suffix(3)) }
            return
        case .ready: break
        }
        guard let b = baseline else { return }
        // 7-sample median kills single-sample spikes, then EMA
        med.append(m); if med.count > 7 { med.removeFirst() }
        let mm = med.sorted()[med.count / 2]
        let dt = lastFieldT.map { max(0.001, min(0.2, t - $0)) } ?? 0.01
        lastFieldT = t
        let a = 1 - exp(-dt / cfg.metalTau)
        ema = ema.map { $0 + a * (mm - $0) } ?? mm
        deviation = abs(ema! - b)
        let dead = max(cfg.metalDeadbandMin, cfg.metalDeadbandSigma * baselineStd)
        var raw = max(0, min(1, (deviation - dead) / cfg.metalFullScale))
        suppressedByMotion = gyro > cfg.rotationSuppress
        if suppressedByMotion { raw = min(raw, metalScore) }       // never escalate while twisting fast
        metalScore += (raw > metalScore ? 0.6 : 0.35) * (raw - metalScore)
        if raw == 0 && metalScore < 0.01 { metalScore = 0 }
        // A real object changes as you sweep; a perfectly flat, large deviation for seconds while the
        // phone moves is a sensor offset jump (iOS recalibrated the compass) → re-anchor the baseline.
        if deviation > dead {
            if flatSince == nil || abs(deviation - flatRef) > 1.0 { flatSince = t; flatRef = deviation }
            else if t - flatSince! > cfg.offsetStuck && gyro > 0.15 {
                baseline = ema; needsRecalibration = true; flatSince = nil
                metalScore = 0; metalLikely = false; metalAboveSince = nil
                return
            }
        } else { flatSince = nil }
        if metalScore > 0.35 {
            if metalAboveSince == nil { metalAboveSince = t }
            if t - metalAboveSince! >= cfg.metalDwell { metalLikely = true }
        } else { metalAboveSince = nil; if metalScore < 0.15 { metalLikely = false } }
        // slow drift tracking only while clearly quiet
        if deviation < dead * 0.8 && gyro < 1 {
            let k = 1 - exp(-dt / cfg.driftTau)
            let nb = b + k * (ema! - b)
            driftAccum += abs(nb - b); baseline = nb
            if driftAccum > cfg.driftRecal { needsRecalibration = true }
        }
    }

    private func humReadyForCal() -> Bool { !calSNRs.isEmpty || ts.count < cfg.humN }  // no raw stream → don't block
    private func finishCal(mean: Double, std: Double) {
        baseline = mean; baselineStd = std
        let s = calSNRs.sorted(); baselineSNR = s.isEmpty ? 0 : s[s.count / 2]
        phase = .ready; calibrationProgress = 1; resetOutputs()
    }

    // MARK: hum / AC channel
    public func ingestRaw(t: Double, x: Double, y: Double, z: Double) {
        bx.append(x); by.append(y); bz.append(z); ts.append(t)
        if bx.count > cfg.humN { bx.removeFirst(); by.removeFirst(); bz.removeFirst(); ts.removeFirst() }
        hop += 1
        guard bx.count == cfg.humN, hop >= cfg.humHop else { return }
        hop = 0
        analyseHum(t: t)
    }

    private func measuredRate() -> Double {
        var d: [Double] = []
        for i in 1..<ts.count { d.append(ts[i] - ts[i - 1]) }
        d.sort(); let m = d[d.count / 2]
        return m > 0 ? 1 / m : 0
    }
    private func prep(_ s: [Double]) -> [Double] {
        let n = Double(s.count), tm = (n - 1) / 2, ym = s.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (i, v) in s.enumerated() { let d = Double(i) - tm; num += d * (v - ym); den += d * d }
        let sl = den > 0 ? num / den : 0
        return s.enumerated().map { i, v in (v - ym - sl * (Double(i) - tm)) * (0.5 - 0.5 * cos(2 * .pi * Double(i) / (n - 1))) }
    }
    private func goertzel(_ x: [Double], k: Double) -> Double {
        let w = 2 * Double.pi * k / Double(x.count), c = 2 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for v in x { let s0 = v + c * s1 - s2; s2 = s1; s1 = s0 }
        return max(0, s1 * s1 + s2 * s2 - c * s1 * s2) / Double(x.count)
    }
    private func analyseHum(t: Double) {
        fs = measuredRate()
        let n = cfg.humN
        aliasHz = DetectorCore.alias(cfg.mainsHz, fs: fs)
        let bin = fs / Double(n), kT = aliasHz / max(bin, 1e-9)
        humMeasurable = fs >= 30 && kT > 4 && kT < Double(n / 2) - 4
        let axes = [prep(bx), prep(by), prep(bz)]
        spectrumCounter += 1
        if spectrumCounter % 5 == 0 {
            spectrum = (1..<n / 2).map { k in (Double(k) * bin, axes.reduce(0) { $0 + goertzel($1, k: Double(k)) }) }
        }
        guard humMeasurable else {
            snrDB = 0; humScore = 0; humLikely = false
            if phase == .calibrating || phase == .warmup { calSNRs.append(0) }
            return
        }
        let target = axes.reduce(0) { $0 + goertzel($1, k: kT) }
        var noise: [Double] = []
        for off in [-7.0, -6, -5, -4, -3, 3, 4, 5, 6, 7] { noise.append(axes.reduce(0) { $0 + goertzel($1, k: kT + off) }) }
        noise.sort()
        let floorP = max(1e-12, noise[noise.count / 2])
        snrDB = 10 * log10(max(target, 1e-14) / floorP)
        if phase == .calibrating || phase == .warmup { calSNRs.append(snrDB); return }
        guard phase == .ready else { return }
        let thr = max(cfg.humMinSNR, baselineSNR + cfg.humAboveCal)
        // short-window SNR reacts within ~0.3 s when the wire/load goes away
        let sn = cfg.humShortN
        let sAxes = [prep(Array(bx.suffix(sn))), prep(Array(by.suffix(sn))), prep(Array(bz.suffix(sn)))]
        let kS = aliasHz / (fs / Double(sn))
        let tS = sAxes.reduce(0) { $0 + goertzel($1, k: kS) }
        var nS: [Double] = []
        for off in [-4.0, -3, 3, 4] where kS + off > 1 && kS + off < Double(sn / 2) - 0.5 { nS.append(sAxes.reduce(0) { $0 + goertzel($1, k: kS + off) }) }
        nS.sort()
        let snrShort = nS.isEmpty ? snrDB : 10 * log10(max(tS, 1e-14) / max(1e-12, nS[nS.count / 2]))
        if humLikely { shortPeak = max(shortPeak * 0.98, tS) } else { shortPeak = 0 }
        let dropped = humLikely && tS < 0.2 * shortPeak
        if snrShort < thr - 3 || dropped {
            humAboveSince = nil
            if humBelowSince == nil { humBelowSince = t }
            if t - humBelowSince! >= cfg.humRelease { humLikely = false }
        } else if snrDB >= thr {
            humBelowSince = nil
            if humAboveSince == nil { humAboveSince = t }
            if t - humAboveSince! >= cfg.humDwell { humLikely = true }
        }
        let target01 = humLikely ? max(0.4, min(1, (snrDB - thr + 6) / 15)) : 0
        humScore += (target01 > humScore ? 0.5 : 0.85) * (target01 - humScore)
        if !humLikely && humScore < 0.02 { humScore = 0 }
    }
}
