import Foundation
import CoreMotion
import Accelerate
import Observation

struct SpectrumPoint: Identifiable { let id: Int; let freq: Double; let power: Double }
struct SamplePoint: Identifiable { let id: Int; let value: Double }

@Observable
final class SensorEngine {
    // Published state (main thread)
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
    var bandPower: Double = 0
    var hfVariance: Double = 0
    var aliasFrequency: Double = 0

    // Baseline
    var baselineMagnitude: Double?
    var baselineBand: Double = 0
    var baselineHF: Double = 0
    var calibrating = false
    var calibrationProgress: Double = 0

    // Derived scores 0...1
    var magDeviation: Double { guard let b = baselineMagnitude else { return 0 }; return abs(currentMagnitude - b) }
    var currentMagnitude: Double { calibratedMagnitude > 0 ? calibratedMagnitude : rawMagnitude }
    var magScore: Double { min(1, magDeviation / 40) }
    var humRatio: Double { baselineBand > 0 ? bandPower / baselineBand : 1 }
    var hfRatio: Double { baselineHF > 0 ? hfVariance / baselineHF : 1 }
    var humScore: Double {
        let r = max(humRatio, hfRatio * 0.7)
        return max(0, min(1, log2(max(r, 1)) / 4))
    }
    var score: Double { max(humScore, magScore * 0.8) }

    // Settings
    var bandLow: Double = 35
    var bandHigh: Double = 45
    var autoBand = true
    var mainsHz: Double = 60

    // Internals (sensor queue)
    private let manager = CMMotionManager()
    private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 1; q.qualityOfService = .userInteractive; return q }()
    private let n = 256
    private var buf: [Double] = []
    private var times: [Double] = []
    private var motionTimes: [Double] = []
    private var sinceFFT = 0
    private var histCounter = 0
    private var histBuf: [SamplePoint] = []
    private var lastPublish: Double = 0
    private var latestCal: Double = 0
    private var latestAcc = "—"
    private var calSamples: [(mag: Double, band: Double, hf: Double)] = []
    private var lastBand: Double = 0
    private var lastHF: Double = 0
    private var lastSpectrum: [SpectrumPoint] = []
    private let dft = vDSP.DFT(count: 256, direction: .forward, transformType: .complexComplex, ofType: Float.self)

    func start() {
        guard !running, manager.isMagnetometerAvailable else { return }
        running = true
        manager.magnetometerUpdateInterval = 1.0 / 100.0
        manager.deviceMotionUpdateInterval = 1.0 / 100.0
        manager.startMagnetometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let d = data else { return }
            self.ingestRaw(d.magneticField, t: d.timestamp)
        }
        if manager.isDeviceMotionAvailable {
            manager.showsDeviceMovementDisplay = false
            manager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: queue) { [weak self] m, _ in
                guard let self, let m else { return }
                let f = m.magneticField.field
                self.latestCal = sqrt(f.x * f.x + f.y * f.y + f.z * f.z)
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

    func stop() {
        manager.stopMagnetometerUpdates()
        manager.stopDeviceMotionUpdates()
        running = false
    }

    func beginCalibration() {
        queue.addOperation { self.calSamples.removeAll() }
        calibrating = true
        calibrationProgress = 0
    }

    func resetBaseline() { baselineMagnitude = nil; baselineBand = 0; baselineHF = 0 }

    private func ingestRaw(_ f: CMMagneticField, t: Double) {
        let mag = sqrt(f.x * f.x + f.y * f.y + f.z * f.z)
        buf.append(mag); times.append(t)
        if buf.count > n { buf.removeFirst(buf.count - n); times.removeFirst(times.count - n) }
        histCounter += 1
        if histCounter % 2 == 0 {
            histBuf.append(SamplePoint(id: histCounter, value: mag))
            if histBuf.count > 250 { histBuf.removeFirst(histBuf.count - 250) }
        }
        sinceFFT += 1
        if buf.count == n && sinceFFT >= 16 { sinceFFT = 0; analyze() }

        if t - lastPublish > 0.05 { lastPublish = t; publish(raw: f, mag: mag) }
    }

    private func measuredRate(_ ts: [Double]) -> Double {
        guard ts.count > 10, let a = ts.first, let b = ts.last, b > a else { return 0 }
        return Double(ts.count - 1) / (b - a)
    }

    private func analyze() {
        let fs = measuredRate(times)
        guard fs > 1, let dft else { return }
        // Detrend + Hann window
        let mean = buf.reduce(0, +) / Double(n)
        var x = buf.map { Float($0 - mean) }
        let win = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        x = vDSP.multiply(x, win)
        let zeros = [Float](repeating: 0, count: n)
        var re = [Float](repeating: 0, count: n), im = [Float](repeating: 0, count: n)
        dft.transform(inputReal: x, inputImaginary: zeros, outputReal: &re, outputImaginary: &im)
        let half = n / 2
        var pts: [SpectrumPoint] = []
        pts.reserveCapacity(half)
        var band = 0.0, total = 0.0
        // alias of mains
        var alias = mainsHz.truncatingRemainder(dividingBy: fs)
        if alias > fs / 2 { alias = fs - alias }
        let lo = autoBand ? max(0.5, alias - 5) : bandLow
        let hi = autoBand ? alias + 5 : bandHigh
        for k in 1..<half {
            let p = Double(re[k] * re[k] + im[k] * im[k]) / Double(n)
            let fr = Double(k) * fs / Double(n)
            pts.append(SpectrumPoint(id: k, freq: fr, power: p))
            if fr >= lo && fr <= hi { band += p }
            if fr > 5 { total += p }
        }
        // High-frequency variance: first differences
        var hf = 0.0
        for i in 1..<n { let d = buf[i] - buf[i - 1]; hf += d * d }
        hf /= Double(n - 1)
        lastBand = band; lastHF = hf; lastSpectrum = pts
        let a = alias
        if calibrating {
            calSamples.append((buf.suffix(32).reduce(0, +) / 32, band, hf))
        }
        let calCount = calSamples.count
        DispatchQueue.main.async {
            self.aliasFrequency = a
            if self.calibrating {
                self.calibrationProgress = min(1, Double(calCount) / 20)
                if calCount >= 20 { self.finishCalibration() }
            }
        }
    }

    private func finishCalibration() {
        let s = calSamples
        guard !s.isEmpty else { return }
        let cal = calibratedMagnitude > 0 ? calibratedMagnitude : s.map(\.mag).reduce(0, +) / Double(s.count)
        baselineMagnitude = cal
        baselineBand = max(1e-6, s.map(\.band).sorted()[s.count / 2])
        baselineHF = max(1e-6, s.map(\.hf).sorted()[s.count / 2])
        calibrating = false
        calibrationProgress = 1
    }

    private func publish(raw f: CMMagneticField, mag: Double) {
        let rr = measuredRate(times), mr = measuredRate(motionTimes)
        let cal = latestCal, acc = latestAcc, sp = lastSpectrum, h = histBuf, b = lastBand, hf = lastHF
        DispatchQueue.main.async {
            self.rawRate = rr; self.motionRate = mr
            self.rawField = (f.x, f.y, f.z); self.rawMagnitude = mag
            self.calibratedMagnitude = cal; self.calibrationAccuracy = acc
            self.spectrum = sp; self.history = h
            self.bandPower = b; self.hfVariance = hf
        }
    }
}
