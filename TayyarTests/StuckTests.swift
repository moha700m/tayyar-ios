import XCTest
@testable import Tayyar

/// Reproductions of "reading stays at 100 after pulling the phone away" (device-like scenarios).
final class StuckTests: XCTestCase {
    /// iOS flips deviceMotion.magneticField to .uncalibrated near a strong magnet, so the calibrated
    /// stream stops while raw samples keep arriving. The score must not freeze at its last value.
    func testScoreReleasesWhenCalibratedStreamStops() {
        let s = Sim(); s.calibrate()
        s.run(1.5, dc: { _ in 80 })
        XCTAssertGreaterThan(s.core.score, 0.9)
        for _ in 0..<300 {   // 3 s: raw only
            s.core.ingestRaw(t: s.t, x: s.earth.x + s.hard.x, y: s.earth.y + s.hard.y, z: s.earth.z + s.hard.z)
            s.t += 0.01
        }
        XCTAssertLessThan(s.core.score, 0.05, "metal score frozen when field stream stopped")
        XCTAssertFalse(s.core.metalLikely)
    }
    /// Sensor offset shifts (strong magnet / iOS recalibration) and the user keeps the phone still.
    func testOffsetShiftWhileStillReleases() {
        let s = Sim(); s.calibrate()
        s.run(10, dc: { _ in 30 })
        XCTAssertLessThan(s.core.metalScore, 0.1, "constant offset while still kept score high")
        XCTAssertFalse(s.core.metalLikely)
    }
    /// Offset shifts and the phone keeps moving, so |B| varies with orientation (never "flat").
    func testOffsetShiftWhileMovingReleases() {
        let s = Sim(); s.calibrate()
        s.run(14, rot: 0.4, dc: { 30 + 5 * sin(1.3 * $0) })
        XCTAssertLessThan(s.core.metalScore, 0.3, "orientation-varying offset kept score high")
        XCTAssertFalse(s.core.metalLikely)
    }
}

final class RawPathTests: XCTestCase {
    /// Raw magnetometer + frozen hard-iron offset: turning the phone must not read as metal.
    func testRawPathRotationNoFalsePositive() {
        let c = DetectorCore(); var rng = RNG(s: 7)
        let h = (x: 120.0, y: -80.0, z: 300.0)
        c.startCalibration(hardIron: h)
        var t = 0.0, maxS = 0.0
        func feed(_ dur: Double, rot: Double, extra: Double = 0) {
            let end = t + dur
            while t < end {
                let a = rot * t, ex = 20 * cos(a) - 5 * sin(a), ey = 20 * sin(a) + 5 * cos(a), ez = -40.0
                let m = (ex * ex + ey * ey + ez * ez).squareRoot(), k = (m + extra) / m
                c.ingestMag(t: t, x: ex * k + h.x + 0.3 * rng.g(), y: ey * k + h.y + 0.3 * rng.g(), z: ez * k + h.z + 0.3 * rng.g(), gyro: abs(rot))
                if c.phase == .ready { maxS = max(maxS, c.metalScore) }
                t += 0.01
            }
        }
        feed(6, rot: 0); XCTAssertEqual(c.phase, .ready)
        feed(20, rot: 0.8); XCTAssertLessThan(maxS, 0.2)
        // approach metal then pull away: must return to ~0 quickly
        feed(1.5, rot: 0, extra: 60); XCTAssertGreaterThan(c.metalScore, 0.9)
        feed(0.6, rot: 0); XCTAssertLessThan(c.metalScore, 0.05)
        XCTAssertFalse(c.metalLikely)
    }
    func testZeroButtonTares() {
        let s = Sim(); s.calibrate()
        s.run(1, dc: { _ in 40 }); XCTAssertGreaterThan(s.core.metalScore, 0.5)
        s.core.zero(); s.run(0.5, dc: { _ in 40 }); XCTAssertLessThan(s.core.metalScore, 0.05)
    }
    func testSensitivityScales() {
        var hi = DetectorCore.Config(); hi.sensitivity = 1.6
        var lo = DetectorCore.Config(); lo.sensitivity = 0.6
        let a = Sim(); a.core = DetectorCore(hi); a.core.startCalibration(); a.calibrate(); a.run(1, dc: { _ in 8 })
        let b = Sim(); b.core = DetectorCore(lo); b.core.startCalibration(); b.calibrate(); b.run(1, dc: { _ in 8 })
        XCTAssertGreaterThan(a.core.metalScore, b.core.metalScore + 0.1)
    }
}

final class LocatorTests: XCTestCase {
    /// Dipole-like falloff from a sensor at (sx, sy) in normalised back coordinates (phone ≈ 7×15 cm).
    func field(_ l: LocatorCore, _ i: Int, sx: Double, sy: Double, rng: inout RNG, noise: Double) -> Double {
        let p = l.center(i), dx = (p.x - sx) * 7, dy = (p.y - sy) * 15, d = (dx * dx + dy * dy + 1).squareRoot()
        return max(0, 120 / pow(d, 3) + noise * rng.g())
    }
    func testFindsMidBackSensorWithConfidence() {
        var l = LocatorCore(noise: 0.3); var rng = RNG(s: 3)
        for rep in 0..<2 { for i in 0..<l.count where rep == 0 || l.ranked.prefix(3).contains(i) { l.add(cell: i, delta: field(l, i, sx: 0.5, sy: 0.58, rng: &rng, noise: 0.4)) } }
        let r = l.result()
        XCTAssertEqual(r.cell, 7)                                   // centre column, middle row
        XCTAssertEqual(r.x, 0.5, accuracy: 0.08); XCTAssertEqual(r.y, 0.58, accuracy: 0.1)
        XCTAssertGreaterThan(r.confidence, 0.6); XCTAssertTrue(r.plausible); XCTAssertTrue(r.retry.isEmpty)
    }
    func testFlatResponseIsLowConfidenceAndRetries() {
        var l = LocatorCore(noise: 0.3); var rng = RNG(s: 9)
        for i in 0..<l.count { l.add(cell: i, delta: max(0, 1.0 + 0.3 * rng.g())) }
        let r = l.result()
        XCTAssertLessThan(r.confidence, 0.4); XCTAssertFalse(r.retry.isEmpty)
    }
    func testCornerResultFlaggedImplausible() {
        var l = LocatorCore(noise: 0.3); var rng = RNG(s: 5)
        for i in 0..<l.count { l.add(cell: i, delta: field(l, i, sx: 0.1, sy: 0.9, rng: &rng, noise: 0.2)) }
        XCTAssertFalse(l.result().plausible)
    }
    func testPeakDeltaIsRobustToSpike() {
        var v = Array(repeating: 50.0, count: 40); v[5] = 400
        XCTAssertEqual(LocatorCore.peakDelta(v + Array(repeating: 58, count: 60), reference: 50, noise: 0.5), 7, accuracy: 0.01)
    }
}
