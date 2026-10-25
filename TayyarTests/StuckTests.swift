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
