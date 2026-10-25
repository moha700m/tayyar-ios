import XCTest
@testable import Tayyar

struct RNG { var s: UInt64
    mutating func u() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
    mutating func g() -> Double { let a = max(1e-12, u()), b = u(); return (-2 * log(a)).squareRoot() * cos(2 * .pi * b) } }

/// Synthetic trace driver. Earth field ~45 µT; raw stream adds a hard-iron offset in device frame.
final class Sim {
    var core = DetectorCore(); var rng = RNG(s: 42); var t = 0.0
    let fs: Double
    var earth = (x: 20.0, y: 5.0, z: -40.0)
    let hard = (x: 120.0, y: -80.0, z: 300.0)
    init(fs: Double = 100) { self.fs = fs; core.startCalibration() }
    /// field(t) returns extra (calibrated-frame) DC offset magnitude to add; ac(t) adds AC on raw axes; rot = yaw rate rad/s
    func run(_ dur: Double, noise: Double = 0.3, rot: Double = 0, dc: (Double) -> Double = { _ in 0 }, ac: (Double) -> Double = { _ in 0 }, gyroNoise: Double = 0.02, every: ((DetectorCore, Double) -> Void)? = nil) {
        let dt = 1 / fs
        let end = t + dur
        while t < end {
            let a = rot * t
            let ex = earth.x * cos(a) - earth.y * sin(a), ey = earth.x * sin(a) + earth.y * cos(a), ez = earth.z
            let m = (ex * ex + ey * ey + ez * ez).squareRoot(), k = (m + dc(t)) / m
            let cx = ex * k + noise * rng.g(), cy = ey * k + noise * rng.g(), cz = ez * k + noise * rng.g()
            let g = abs(rot) + abs(gyroNoise * rng.g())
            core.ingestField(t: t, x: cx, y: cy, z: cz, gyro: g)
            let h = ac(t)
            core.ingestRaw(t: t + dt * 0.3 * rng.u(), x: cx + hard.x + h, y: cy + hard.y + 0.5 * h, z: cz + hard.z + 0.3 * h)
            every?(core, t)
            t += dt
        }
    }
    func calibrate() { run(6); XCTAssertEqual(core.phase, .ready, "calibration should complete when still") }
}

final class DetectorTests: XCTestCase {
    func testStillNoiseNoFalsePositive30s() {
        let s = Sim(); s.calibrate()
        var maxScore = 0.0, anyLikely = false
        s.run(30) { c, _ in maxScore = max(maxScore, c.score); anyLikely = anyLikely || c.metalLikely || c.humLikely }
        XCTAssertFalse(anyLikely); XCTAssertLessThan(maxScore, 0.2, "still noise must stay quiet")
    }
    func testGentleRotationNoFalsePositive() {
        let s = Sim(); s.calibrate()
        var maxScore = 0.0, anyLikely = false
        s.run(30, noise: 0.4, rot: 0.6, dc: { 0.8 * sin(0.7 * $0) }) { c, _ in maxScore = max(maxScore, c.score); anyLikely = anyLikely || c.metalLikely || c.humLikely }
        XCTAssertFalse(anyLikely); XCTAssertLessThan(maxScore, 0.2)
    }
    func testMetalStepLatencyUnderHalfSecond() {
        let s = Sim(); s.calibrate()
        s.run(2)
        let t0 = s.t; var hit: Double?
        s.run(2, dc: { $0 >= t0 ? 20 : 0 }) { c, t in if hit == nil && c.metalLikely { hit = t } }
        XCTAssertNotNil(hit); if let h = hit { XCTAssertLessThan(h - t0, 0.5) }
        s.run(2)   // metal removed
        XCTAssertFalse(s.core.metalLikely, "should release after metal removed")
    }
    func testNoiseBurstsIgnored() {
        let s = Sim(); s.calibrate()
        var anyLikely = false
        s.run(20, dc: { t in t.truncatingRemainder(dividingBy: 2) < 0.03 ? 40 : 0 }) { c, _ in anyLikely = anyLikely || c.metalLikely || c.humLikely }
        XCTAssertFalse(anyLikely, "30 ms spikes must not trigger")
    }
    func testHum60At100Hz() {
        let s = Sim(fs: 100); s.calibrate()
        let t0 = s.t; var hit: Double?
        s.run(4, ac: { 1.0 * sin(2 * .pi * 60 * $0) }) { c, t in if hit == nil && c.humLikely { hit = t } }
        XCTAssertTrue(s.core.humMeasurable); XCTAssertEqual(s.core.aliasHz, 40, accuracy: 1.5)
        XCTAssertNotNil(hit); if let h = hit { XCTAssertGreaterThanOrEqual(h - t0, 1.0); XCTAssertLessThan(h - t0, 3.0) }
    }
    func testHum60At50HzAliasesTo10() {
        let s = Sim(fs: 50); s.calibrate()
        var hit = false
        s.run(5, ac: { 1.0 * sin(2 * .pi * 60 * $0) }) { c, _ in hit = hit || c.humLikely }
        XCTAssertEqual(s.core.aliasHz, 10, accuracy: 1); XCTAssertTrue(hit)
    }
    func testHum50At100HzNotMeasurable() {
        let s = Sim(fs: 100); s.core.cfg.mainsHz = 50; s.calibrate()
        var hit = false
        s.run(4, ac: { 1.0 * sin(2 * .pi * 50 * $0 + 0.3) }) { c, _ in hit = hit || c.humLikely }
        XCTAssertFalse(s.core.humMeasurable); XCTAssertFalse(hit)
    }
    func testShortHumBlipNotReported() {
        let s = Sim(); s.calibrate(); let t0 = s.t
        var hit = false
        s.run(3, ac: { t in (t - t0) < 0.5 ? 1.0 * sin(2 * .pi * 60 * t) : 0 }) { c, _ in hit = hit || c.humLikely }
        XCTAssertFalse(hit, "hum shorter than 1 s must not be reported")
    }
    func testCalibrationWaitsWhileMoving() {
        let s = Sim()
        s.run(6, noise: 3.0, rot: 1.2)
        XCTAssertNotEqual(s.core.phase, .ready, "must keep asking to hold still")
        XCTAssertTrue(s.core.calibrationTooNoisy)
        s.run(4)
        XCTAssertEqual(s.core.phase, .ready)
    }
    func testNoHighStartAfterCalibration() {
        let s = Sim(); s.calibrate()
        XCTAssertEqual(s.core.score, 0); XCTAssertFalse(s.core.metalLikely)
    }

    /// Calibrate upright, then lay the phone flat on a wall in any orientation: |B| is orientation-independent.
    func testOrientationChangeDoesNotTrigger() {
        let s = Sim(); s.calibrate()
        var anyLikely = false, maxScore = 0.0
        for (ex, ey, ez) in [(45.0, 0.0, 0.0), (0.0, 0.0, 45.0), (-30.0, 30.0, 10.0), (0.0, -44.0, 9.0)] {
            let n = (ex*ex + ey*ey + ez*ez).squareRoot(), m = (20.0*20 + 25 + 1600).squareRoot()
            s.earth = (ex * m / n, ey * m / n, ez * m / n)
            s.run(5, rot: 0.3) { c, _ in anyLikely = anyLikely || c.metalLikely; maxScore = max(maxScore, c.metalScore) }
        }
        XCTAssertFalse(anyLikely); XCTAssertLessThan(maxScore, 0.2)
    }

    /// Strong metal for 2 s, then removed: score must fall < 0.2 within 0.5 s and stay down.
    func testMetalReleaseFast() {
        let s = Sim(); s.calibrate(); s.run(1)
        let t0 = s.t
        s.run(2, dc: { $0 >= t0 ? 60 : 0 })
        XCTAssertGreaterThan(s.core.score, 0.9, "should reach full scale")
        let tOff = s.t; var fell: Double?
        s.run(3) { c, t in if fell == nil && c.score < 0.2 { fell = t } }
        XCTAssertNotNil(fell); if let f = fell { XCTAssertLessThan(f - tOff, 0.5) }
        XCTAssertLessThan(s.core.score, 0.05, "must not stick")
    }
    /// Hum for 3 s then load switched off: score < 0.2 within 0.5 s.
    func testHumReleaseFast() {
        let s = Sim(); s.calibrate()
        let t0 = s.t
        s.run(3, ac: { 1.0 * sin(2 * .pi * 60 * $0) })
        XCTAssertTrue(s.core.humLikely)
        let tOff = s.t; var fell: Double?
        s.run(3) { c, t in if fell == nil && c.score < 0.2 { fell = t } }
        _ = t0
        XCTAssertNotNil(fell); if let f = fell { XCTAssertLessThan(f - tOff, 0.5) }
        XCTAssertLessThan(s.core.score, 0.05)
    }
    /// iOS re-estimates the compass offset mid-scan (flat 30 µT jump while moving): must not stay pinned.
    func testOffsetJumpDoesNotPin() {
        let s = Sim(); s.calibrate()
        let t0 = s.t
        s.run(8, rot: 0.3, dc: { $0 >= t0 ? 30 : 0 })
        XCTAssertLessThan(s.core.score, 0.1); XCTAssertGreaterThan(s.core.autoZeroCount, 0)
    }

    func testHistoryRoundTripAndCap() {
        let d = UserDefaults(suiteName: "tayyar-test")!; ScanHistory.clear(d)
        for i in 0..<210 { ScanHistory.add(ScanRecord(date: Date(), kind: i % 2 == 0 ? "metal" : "wire", peak: i % 100), d) }
        let all = ScanHistory.load(d)
        XCTAssertEqual(all.count, 200); XCTAssertEqual(all.first?.peak, 209 % 100)
        ScanHistory.clear(d); XCTAssertTrue(ScanHistory.load(d).isEmpty)
    }
    func testGeigerRateRisesWithScore() {
        XCTAssertNil(Geiger.interval(score: 0.02))
        let a = Geiger.interval(score: 0.2)!, b = Geiger.interval(score: 0.9)!
        XCTAssertGreaterThan(a, b); XCTAssertGreaterThan(b, 0.05)
    }
}
