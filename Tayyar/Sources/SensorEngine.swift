import Foundation
import CoreMotion
import Accelerate
import Observation

struct SpectrumPoint: Identifiable { let id: Int; let freq: Double; let power: Double }
struct SamplePoint: Identifiable { let id: Int; let value: Double }

/// Signal chain (v2.2):
/// 1. Raw magnetometer per axis (x,y,z) at the fastest rate CoreMotion gives (asked 100 Hz, true rate measured from timestamps).
/// 2. Mains frequency (50/60 Hz) folded to its alias for the *measured* rate: f_a = |f - fs*round(f/fs)|.
/// 3. Per axis: linear detrend (removes DC field + slow drift from moving the phone), Hann window.
/// 4. Goertzel power at the alias bin, summed over the 3 axes (orientation independent),
///    SNR against median power of neighbouring bins (guard ±1 bin, excluding the target).
/// 5. SNR compared to the SNR recorded during calibration away from walls, EMA smoothed, with hysteresis.
/// 6. Separate DC anomaly channel: hard-iron-corrected (device motion) field magnitude vs baseline,
///    median-filtered, with a dead band of 4x the calibration noise.
@Observable
final class SensorEngine {
    var running = false
    var available = CMMotionManager().isMagnetometerAvailable
    var rawRate: Double = 0
    var motionRate: Double = 0
    var rawField = (x: 0.0, y: 0.0, z: 0.0)
    var rawMagnitude: Double = 0
    var calibratedMagnitude: Double = 0
    var calibrationAccuracy: String = "—"
    var spectrum: [SpectrumPoint] = []
    var history: [SamplePoint] = []
    var bandPower: Double = 0      // Goertzel power at alias (sum of axes)
    var hfVariance: Double = 0     // now: SNR in dB at alias
    var aliasFrequency: Double = 0
    /// False when the alias sits at DC or Nyquist (e.g. 50 Hz mains at exactly 100 Hz) or rate is too low.
    var humMeasurable = true

    var baselineMagnitude: Double?
    var baselineSNR: Double = 0
    var baselineNoise: Double = 1
    var calibrating = false
    var calibrationProgress: Double = 0

    // Smoothed outputs
    var humScore: Double = 0
    var magScore: Double = 0
    var magDeviation: Double = 0
    var humRatio: Double = 1          // SNR above baseline (linear)
    var humLikely = false
    var metalLikely = false
    var score: Double { max(humScore, magScore * 0.8) }
    var currentMagnitude: Double { calibratedMagnitude > 0 ? calibratedMagnitude : rawMagnitude }

    var bandLow: Double = 35
    var bandHigh: Double = 45
    var autoBand = true
    var mainsHz: Double = 60   // Saudi grid is 60 Hz

    private let manager = CMMotionManager()
    private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 1; q.qualityOfService = .userInteractive; return q }()
    private let n = 256
    private var bx: [Double] = [], by: [Double] = [], bz: [Double] = []
    private var times: [Double] = []
    private var motionTimes: [Double] = []
    private var magWindow: [Double] = []
    private var sinceFFT = 0
    private var histCounter = 0
    private var histBuf: [SamplePoint] = []
    private var lastPublish: Double = 0
    private var latestCal: Double = 0
    private var latestAcc = "—"
    private var calSNR: [Double] = []
    private var calMag: [Double] = []
    private var lastSpectrum: [SpectrumPoint] = []
    private let dft = vDSP.DFT(count: 256, direction: .forward, transformType: .complexComplex, ofType: Float.self)
    private lazy var hann: [Double] = (0..<n).map { 0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(n - 1)) }

    func start() {
        guard !running, manager.isMagnetometerAvailable else { return }
        running = true
        manager.magnetometerUpdateInterval = 0.01   // capped by hardware; real rate measured below
        manager.deviceMotionUpdateInterval = 0.02
        manager.startMagnetometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let d = data else { return }
            self.ingestRaw(d.magneticField, t: d.timestamp)
        }
        if manager.isDeviceMotionAvailable {
            manager.showsDeviceMovementDisplay = false
            manager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: queue) { [weak self] m, _ in
                guard let self, let m else { return }
                let f = m.magneticField.field
                let mag = sqrt(f.x * f.x + f.y * f.y + f.z * f.z)
                if m.magneticField.accuracy != .uncalibrated && mag > 0 { self.latestCal = mag }
                switch m.magneticField.accuracy {
                case .uncalibrated: self.latestAcc = "غير معاير"
                case .low: self.latestAcc = "منخفضة"
                case .medium: self.latestAcc = "متوسطة"
                case .high: self.latestAcc = "عالية"
                @unknown default: self.latestAcc = "—"
                }
                self.motionTimes.append(m.timestamp)
                if self.motionTimes.count > 200 { self.motionTimes.removeFirst(self.motionTimes.count - 200) }
            }
        }
    }

    func stop() { manager.stopMagnetometerUpdates(); manager.stopDeviceMotionUpdates(); running = false }

    func beginCalibration() {
        queue.addOperation { self.calSNR.removeAll(); self.calMag.removeAll() }
        calibrating = true; calibrationProgress = 0
    }

    func resetBaseline() {
        baselineMagnitude = nil; baselineSNR = 0; baselineNoise = 1
        humScore = 0; magScore = 0; humLikely = false; metalLikely = false
    }

    /// Fold a real frequency into [0, fs/2] for sample rate fs.
    static func alias(_ f: Double, fs: Double) -> Double {
        guard fs > 0 else { return 0 }
        return abs(f - fs * (f / fs).rounded())
    }

    private func ingestRaw(_ f: CMMagneticField, t: Double) {
        let mag = sqrt(f.x * f.x + f.y * f.y + f.z * f.z)
        bx.append(f.x); by.append(f.y); bz.append(f.z); times.append(t)
        if bx.count > n { let k = bx.count - n; bx.removeFirst(k); by.removeFirst(k); bz.removeFirst(k); times.removeFirst(k) }
        let dcMag = latestCal > 0 ? latestCal : mag
        magWindow.append(dcMag); if magWindow.count > 25 { magWindow.removeFirst() }
        histCounter += 1
        if histCounter % 2 == 0 {
            histBuf.append(SamplePoint(id: histCounter, value: mag))
            if histBuf.count > 250 { histBuf.removeFirst(histBuf.count - 250) }
        }
        sinceFFT += 1
        if bx.count == n && sinceFFT >= 16 { sinceFFT = 0; analyze() }
        if t - lastPublish > 0.05 { lastPublish = t; publish(raw: f, mag: mag) }
    }

    private func measuredRate(_ ts: [Double]) -> Double {
        guard ts.count > 10, let a = ts.first, let b = ts.last, b > a else { return 0 }
        // median interval is robust to dropped/bursty samples
        var d: [Double] = []
        for i in 1..<ts.count { d.append(ts[i] - ts[i - 1]) }
        d.sort()
        let med = d[d.count / 2]
        return med > 0 ? 1 / med : Double(ts.count - 1) / (b - a)
    }

    private func prep(_ s: [Double]) -> [Double] {
        // least-squares linear detrend then Hann
        let m = Double(s.count), tMean = (m - 1) / 2
        let yMean = s.reduce(0, +) / m
        var num = 0.0, den = 0.0
        for (i, v) in s.enumerated() { let dt = Double(i) - tMean; num += dt * (v - yMean); den += dt * dt }
        let slope = den > 0 ? num / den : 0
        return s.enumerated().map { (i, v) in (v - yMean - slope * (Double(i) - tMean)) * hann[i] }
    }

    private func goertzel(_ x: [Double], k: Double) -> Double {
        let w = 2 * Double.pi * k / Double(x.count), c = 2 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for v in x { let s0 = v + c * s1 - s2; s2 = s1; s1 = s0 }
        return (s1 * s1 + s2 * s2 - c * s1 * s2) / Double(x.count)
    }

    private func analyze() {
        let fs = measuredRate(times)
        guard fs > 1, let dft else { return }
        let axes = [prep(bx), prep(by), prep(bz)]
        let fa = autoBand ? SensorEngine.alias(mainsHz, fs: fs) : (bandLow + bandHigh) / 2
        let binHz = fs / Double(n)
        let kT = fa / binHz
        let measurable = fs >= 30 && fa > 3 * binHz && fa < fs / 2 - 2 * binHz
        // Goertzel at target (fractional bin, robust to rate jitter) summed across axes
        var target = 0.0
        for a in axes { target += max(goertzel(a, k: kT - 0.5), goertzel(a, k: kT), goertzel(a, k: kT + 0.5)) }
        // Neighbour noise: bins 2..6 away on both sides
        var noise: [Double] = []
        for off in [-6.0, -5, -4, -3, -2, 2, 3, 4, 5, 6] {
            let k = kT + off
            if k > 2 && k < Double(n / 2) - 1 { noise.append(axes.reduce(0) { $0 + goertzel($1, k: k) }) }
        }
        noise.sort()
        let floorP = noise.isEmpty ? 1e-9 : max(1e-9, noise[noise.count / 2])
        let snrDB = 10 * log10(max(target, 1e-12) / floorP)

        // Display spectrum: power summed over axes
        let zeros = [Float](repeating: 0, count: n)
        var sum = [Double](repeating: 0, count: n / 2)
        for a in axes {
            var re = [Float](repeating: 0, count: n), im = [Float](repeating: 0, count: n)
            dft.transform(inputReal: a.map(Float.init), inputImaginary: zeros, outputReal: &re, outputImaginary: &im)
            for k in 1..<n / 2 { sum[k] += Double(re[k] * re[k] + im[k] * im[k]) / Double(n) }
        }
        lastSpectrum = (1..<n / 2).map { SpectrumPoint(id: $0, freq: Double($0) * binHz, power: sum[$0]) }

        let sortedMag = magWindow.sorted()
        let medMag = sortedMag.isEmpty ? 0 : sortedMag[sortedMag.count / 2]
        if calibrating { calSNR.append(snrDB); calMag.append(medMag) }
        let calCount = calSNR.count
        let tp = target
        DispatchQueue.main.async {
            self.aliasFrequency = fa
            self.humMeasurable = measurable
            self.bandPower = tp
            self.hfVariance = snrDB
            if self.calibrating {
                self.calibrationProgress = min(1, Double(calCount) / 20)
                if calCount >= 20 { self.finishCalibration() }
                return
            }
            self.update(snrDB: snrDB, medMag: medMag, measurable: measurable)
        }
    }

    private func update(snrDB: Double, medMag: Double, measurable: Bool) {
        // AC hum: dB above calibrated SNR. 6 dB → starts, 18 dB → full.
        let excess = measurable ? snrDB - baselineSNR : 0
        humRatio = pow(10, max(0, excess) / 10)
        let rawHum = max(0, min(1, (excess - 6) / 12))
        humScore += (rawHum > humScore ? 0.5 : 0.2) * (rawHum - humScore)   // fast attack, slow release
        if !humLikely && humScore > 0.5 { humLikely = true } else if humLikely && humScore < 0.3 { humLikely = false }

        // DC anomaly with dead band = 4σ of calibration noise (min 2 µT)
        if let b = baselineMagnitude {
            magDeviation = abs(medMag - b)
            let dead = max(2, 4 * baselineNoise)
            let rawMagS = max(0, min(1, (magDeviation - dead) / 30))
            magScore += (rawMagS > magScore ? 0.5 : 0.2) * (rawMagS - magScore)
            if !metalLikely && magScore > 0.4 { metalLikely = true } else if metalLikely && magScore < 0.2 { metalLikely = false }
        }
    }

    private func finishCalibration() {
        guard !calSNR.isEmpty else { return }
        let s = calSNR.sorted()
        baselineSNR = s[s.count / 2]
        let m = calMag
        let mean = m.reduce(0, +) / Double(m.count)
        baselineMagnitude = mean
        baselineNoise = sqrt(m.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(m.count))
        calibrating = false; calibrationProgress = 1
    }

    private func publish(raw f: CMMagneticField, mag: Double) {
        let rr = measuredRate(times), mr = measuredRate(motionTimes)
        let cal = latestCal, acc = latestAcc, sp = lastSpectrum, h = histBuf
        DispatchQueue.main.async {
            self.rawRate = rr; self.motionRate = mr
            self.rawField = (f.x, f.y, f.z); self.rawMagnitude = mag
            self.calibratedMagnitude = cal; self.calibrationAccuracy = acc
            self.spectrum = sp; self.history = h
        }
    }
}
