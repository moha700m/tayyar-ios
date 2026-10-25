import Foundation
import CoreMotion
import Observation

struct SpectrumPoint: Identifiable { let id: Int; let freq: Double; let power: Double }
struct SamplePoint: Identifiable { let id: Int; let value: Double }

/// v4 signal chain. ONE stream: raw magnetometer (CMMagnetometerData) minus a hard-iron offset that is
/// frozen at calibration (taken from iOS's estimate once, then never changes). deviceMotion is used only
/// for gyro/gravity. v3 fed the metal channel from deviceMotion.magneticField, which (a) stops when iOS
/// marks the compass uncalibrated near a strong magnet → score froze at 100, and (b) jumps when iOS
/// re-estimates its offset → a permanent deviation that the old "flat + moving" re-anchor never caught.
///
/// v3 signal chain (history) — CoreMotion wrapper around the pure, unit-tested `DetectorCore`.
/// Metal (DC) channel: ONE consistent source, locked per calibration — hard-iron-corrected
///   deviceMotion.magneticField when iOS has calibrated it, else raw magnitude. (v2 mixed the two,
///   so the baseline and the live value came from different sources → instant false "strong".)
/// Hum (AC) channel: raw magnetometer axes, 128-sample Goertzel at the alias of 60/50 Hz for the
///   MEASURED rate, SNR vs neighbour bins, must stay high ≥1 s.
/// Calibration waits for warm-up and a still, low-variance window; baseline tracks slow drift only
///   while quiet and asks for recalibration if drift accumulates.
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
    var bandPower: Double = 0
    var hfVariance: Double = 0       // SNR dB at alias
    var aliasFrequency: Double = 0
    var humMeasurable = true

    var baselineMagnitude: Double?
    var baselineSNR: Double = 0
    var baselineNoise: Double = 1
    var calibrating = false
    var calibrationProgress: Double = 0
    var calibrationTooNoisy = false
    var needsRecalibration = false
    var suppressedByMotion = false
    var usingCalibratedField = true
    var gravity = (x: 0.0, y: 0.0, z: -1.0)

    var humScore: Double = 0
    var magScore: Double = 0
    var magDeviation: Double = 0
    var humRatio: Double = 1
    var humLikely = false
    var metalLikely = false
    var score: Double { max(humScore, magScore) }
    var currentMagnitude: Double { fieldMagnitude }
    // live debug (Test tab)
    var fieldMagnitude: Double = 0      // |raw − frozen hard-iron| µT
    var filteredMagnitude: Double = 0   // after median + EMA
    var hardIronMagnitude: Double = 0
    var autoZeroCount = 0
    var humLevel: Double = 0
    var phaseName = "—"
    var sensitivity: Double = UserDefaults.standard.object(forKey: "sensitivity") as? Double ?? 1.0 {
        didSet { UserDefaults.standard.set(sensitivity, forKey: "sensitivity"); let v = sensitivity; queue.addOperation { self.core.cfg.sensitivity = v } }
    }

    var bandLow: Double = 35
    var bandHigh: Double = 45
    var autoBand = true
    var mainsHz: Double = 60 { didSet { queue.addOperation { self.core.cfg.mainsHz = self.mainsHz } } }

    // trace recording (Test tab) for tuning with real data
    var recording = false
    var recordedLines = 0
    @ObservationIgnored private var trace: [String] = []

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 1; q.qualityOfService = .userInteractive; return q }()
    @ObservationIgnored private let core = DetectorCore()
    @ObservationIgnored private var useCal = true
    @ObservationIgnored private var lastGyro = 0.0
    @ObservationIgnored private var latestCalOK = false
    @ObservationIgnored private var rawTimes: [Double] = []
    @ObservationIgnored private var motionTimes: [Double] = []
    @ObservationIgnored private var histBuf: [SamplePoint] = []
    @ObservationIgnored private var histCounter = 0
    @ObservationIgnored private var lastPublish = 0.0
    @ObservationIgnored private var lastRaw = (x: 0.0, y: 0.0, z: 0.0)
    @ObservationIgnored private var lastCalMag = 0.0
    @ObservationIgnored private var acc = "—"
    @ObservationIgnored private var askedUpgrade = false
    @ObservationIgnored private var hEst: (x: Double, y: Double, z: Double)?
    @ObservationIgnored private var epoch = 0          // queue side
    @ObservationIgnored private var wantedEpoch = 0    // main side

    func start() {
        guard !running, manager.isMagnetometerAvailable else { return }
        running = true
        manager.magnetometerUpdateInterval = 0.01
        manager.deviceMotionUpdateInterval = 0.01
        manager.startMagnetometerUpdates(to: queue) { [weak self] d, _ in
            guard let self, let d else { return }
            let f = d.magneticField
            self.lastRaw = (f.x, f.y, f.z)
            self.core.ingestMag(t: d.timestamp, x: f.x, y: f.y, z: f.z, gyro: self.lastGyro)
            self.rawTimes.append(d.timestamp); if self.rawTimes.count > 120 { self.rawTimes.removeFirst() }
            self.record("r", d.timestamp, f.x, f.y, f.z)
            self.tick(d.timestamp)
        }
        if manager.isDeviceMotionAvailable {
            manager.showsDeviceMovementDisplay = true
            manager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: queue) { [weak self] m, _ in
                guard let self, let m else { return }
                let gv = m.gravity
                if Int(m.timestamp * 30) != Int((m.timestamp - 0.01) * 30) { DispatchQueue.main.async { self.gravity = (gv.x, gv.y, gv.z) } }
                let r = m.rotationRate
                self.lastGyro = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
                let f = m.magneticField.field
                self.latestCalOK = m.magneticField.accuracy != .uncalibrated
                switch m.magneticField.accuracy {
                case .uncalibrated: self.acc = "غير معاير"
                case .low: self.acc = "منخفضة"
                case .medium: self.acc = "متوسطة"
                case .high: self.acc = "عالية"
                @unknown default: self.acc = "—"
                }
                self.motionTimes.append(m.timestamp); if self.motionTimes.count > 120 { self.motionTimes.removeFirst() }
                if self.latestCalOK && !self.useCal && self.core.phase == .ready && !self.askedUpgrade {
                    // raw-mode baseline depends on orientation (hard-iron offset); now that iOS has a
                    // corrected field, ask for one recalibration so tilting/turning stops mattering
                    self.askedUpgrade = true
                    DispatchQueue.main.async { self.needsRecalibration = true }
                }
                if self.latestCalOK {
                    self.lastCalMag = (f.x * f.x + f.y * f.y + f.z * f.z).squareRoot()
                    // running estimate of iOS's hard-iron offset (raw − corrected); only READ at calibration
                    let r = self.lastRaw, k = self.hEst == nil ? 1.0 : 0.05
                    let d = (x: r.x - f.x, y: r.y - f.y, z: r.z - f.z), o = self.hEst ?? d
                    self.hEst = (o.x + k * (d.x - o.x), o.y + k * (d.y - o.y), o.z + k * (d.z - o.z))
                }
                self.record("c", m.timestamp, f.x, f.y, f.z, self.lastGyro)
            }
        }
    }

    func stop() { manager.stopMagnetometerUpdates(); manager.stopDeviceMotionUpdates(); running = false }

    func beginCalibration() {
        calibrating = true; calibrationProgress = 0; baselineMagnitude = nil
        wantedEpoch += 1
        let e = wantedEpoch
        queue.addOperation {
            self.epoch = e
            // lock ONE source for baseline and live values
            self.useCal = self.latestCalOK && self.hEst != nil
            self.askedUpgrade = false
            self.core.cfg.sensitivity = UserDefaults.standard.object(forKey: "sensitivity") as? Double ?? 1.0
            self.core.startCalibration(hardIron: self.useCal ? self.hEst! : (0, 0, 0))
        }
    }

    func resetBaseline() {
        humScore = 0; magScore = 0; humLikely = false; metalLikely = false
        beginCalibration()
    }

    /// Tare on the current reading.
    func zero() { queue.addOperation { self.core.zero() } }

    static func alias(_ f: Double, fs: Double) -> Double { DetectorCore.alias(f, fs: fs) }

    private func rate(_ ts: [Double]) -> Double {
        guard ts.count > 10 else { return 0 }
        var d: [Double] = []; for i in 1..<ts.count { d.append(ts[i] - ts[i - 1]) }
        d.sort(); return d[d.count / 2] > 0 ? 1 / d[d.count / 2] : 0
    }

    private func record(_ k: String, _ t: Double, _ x: Double, _ y: Double, _ z: Double, _ g: Double = 0) {
        guard recording, trace.count < 200_000 else { return }
        trace.append(String(format: "%@,%.4f,%.3f,%.3f,%.3f,%.3f", k, t, x, y, z, g))
    }

    func toggleRecording() {
        queue.addOperation {
            if !self.recording { self.trace = ["kind,t,x,y,z,gyro"] }
            let on = !self.recording
            DispatchQueue.main.async { self.recording = on }
        }
    }

    /// Writes the recorded trace to a temp CSV and returns its URL.
    func exportTrace() -> URL? {
        var lines: [String] = []
        queue.addOperations([BlockOperation { lines = self.trace }], waitUntilFinished: true)
        guard lines.count > 1 else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tayyar-trace.csv")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func tick(_ t: Double) {
        let mag = (lastRaw.x * lastRaw.x + lastRaw.y * lastRaw.y + lastRaw.z * lastRaw.z).squareRoot()
        let hi = core.hardIron
        let fx = lastRaw.x - hi.x, fy = lastRaw.y - hi.y, fz = lastRaw.z - hi.z
        let fmag = (fx * fx + fy * fy + fz * fz).squareRoot()
        histCounter += 1
        if histCounter % 2 == 0 {
            histBuf.append(SamplePoint(id: histCounter, value: fmag))
            if histBuf.count > 250 { histBuf.removeFirst(histBuf.count - 250) }
        }
        guard t - lastPublish >= 0.025 else { return }   // ~40 Hz UI
        lastPublish = t
        let c = core
        let snap = (phase: c.phase, prog: c.calibrationProgress, noisy: c.calibrationTooNoisy, base: c.baseline, std: c.baselineStd,
                    bsnr: c.baselineSNR, m: c.metalScore, h: c.humScore, ml: c.metalLikely, hl: c.humLikely, dev: c.deviation,
                    snr: c.snrDB, fa: c.aliasHz, meas: c.humMeasurable, recal: c.needsRecalibration, sup: c.suppressedByMotion)
        let sp = c.spectrum.enumerated().map { SpectrumPoint(id: $0.offset, freq: $0.element.0, power: $0.element.1) }
        let rr = rate(rawTimes), mr = rate(motionTimes), raw = lastRaw, cal = lastCalMag, a = acc, h = histBuf, uc = useCal
        let rec = trace.count, ep = epoch
        let dbg = (filt: c.filtered, hm: (hi.x * hi.x + hi.y * hi.y + hi.z * hi.z).squareRoot(), az: c.autoZeroCount, hl: c.humLevel,
                   ph: { switch c.phase { case .idle: "idle"; case .warmup: "warmup"; case .calibrating: "calibrating"; case .ready: "ready" } }())
        DispatchQueue.main.async {
            self.rawRate = rr; self.motionRate = mr; self.rawField = raw; self.rawMagnitude = mag
            self.calibratedMagnitude = cal; self.calibrationAccuracy = a; self.history = h; self.usingCalibratedField = uc
            if !sp.isEmpty { self.spectrum = sp }
            self.recordedLines = rec
            self.fieldMagnitude = fmag; self.filteredMagnitude = dbg.filt; self.hardIronMagnitude = dbg.hm
            self.autoZeroCount = dbg.az; self.humLevel = dbg.hl; self.phaseName = dbg.ph
            if self.calibrating {
                guard ep == self.wantedEpoch else { return }
                self.calibrationProgress = snap.prog; self.calibrationTooNoisy = snap.noisy
                if snap.phase == .ready { self.calibrating = false }
                else { return }
            }
            self.baselineMagnitude = snap.base; self.baselineNoise = snap.std; self.baselineSNR = snap.bsnr
            self.magScore = snap.m; self.humScore = snap.h; self.metalLikely = snap.ml; self.humLikely = snap.hl
            self.magDeviation = snap.dev; self.hfVariance = snap.snr; self.aliasFrequency = snap.fa
            self.humMeasurable = snap.meas; self.needsRecalibration = snap.recal || (self.needsRecalibration && !uc); self.suppressedByMotion = snap.sup
            self.humRatio = pow(10, max(0, snap.snr - snap.bsnr) / 10); self.bandPower = snap.snr
        }
    }
}
