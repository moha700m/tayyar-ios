import Foundation

/// Pure, testable analysis for the sensor-location test.
/// The user places a key/magnet on each grid cell of the phone's back; for every placement we keep a
/// robust peak delta (|field − reference|, 80th percentile of the settled samples). Cells are measured
/// repeatedly; the result is a sub-cell estimate (weighted centroid around the best cell), a confidence
/// score, the cells to retry when ambiguous, and a plausibility check against the published hardware
/// layout (recent iPhones: compass on the MagSafe / wireless-charging flex, roughly mid-back).
public struct LocatorCore {
    public let cols: Int, rows: Int
    public var noise: Double                       // reference σ (µT)
    public private(set) var samples: [[Double]]    // per cell: repeated peak deltas

    public init(cols: Int = 3, rows: Int = 5, noise: Double = 0.3) {
        self.cols = cols; self.rows = rows; self.noise = noise
        samples = Array(repeating: [], count: cols * rows)
    }
    public var count: Int { cols * rows }

    /// Normalised centre of a cell (x: 0 left … 1 right looking at the back, y: 0 top … 1 bottom).
    /// Top 12 % is the camera bump; cells span the rest.
    public func center(_ i: Int) -> (x: Double, y: Double) {
        let c = i % cols, r = i / cols
        return ((Double(c) + 0.5) / Double(cols), 0.14 + (Double(r) + 0.5) / Double(rows) * 0.82)
    }

    /// Robust per-placement peak: 80th percentile of |sample − reference|, minus noise floor.
    public static func peakDelta(_ values: [Double], reference: Double, noise: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let d = values.map { abs($0 - reference) }.sorted()
        let p = d[min(d.count - 1, Int(Double(d.count) * 0.8))]
        return max(0, p - 2 * noise)
    }

    public mutating func add(cell: Int, delta: Double) { samples[cell].append(delta) }

    /// Median of the repeats for a cell.
    public func value(_ i: Int) -> Double {
        let s = samples[i].sorted(); guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
    /// Relative spread of repeats for a cell (0 = perfectly repeatable).
    public func spread(_ i: Int) -> Double {
        let s = samples[i]; guard s.count > 1 else { return 0.5 }
        let v = value(i); guard v > 0 else { return 1 }
        return min(1, (s.max()! - s.min()!) / v)
    }
    public var ranked: [Int] { (0..<count).sorted { value($0) > value($1) } }

    public struct Result: Equatable {
        public var cell: Int
        public var x: Double, y: Double
        public var confidence: Double      // 0…1
        public var signal: Double          // µT at best cell
        public var retry: [Int]            // cells to measure again (empty when clear)
        public var plausible: Bool         // inside the expected mid-back region
    }

    /// Expected region from teardown photos (iFixit) and the MagSafe coil position: central band of the back.
    public static func plausible(x: Double, y: Double) -> Bool { x > 0.2 && x < 0.8 && y > 0.25 && y < 0.8 }

    public func result() -> Result {
        let r = ranked, b = r[0], s1 = value(b), s2 = r.count > 1 ? value(r[1]) : 0
        // sub-cell position: weighted centroid of the best cell and its 8 neighbours
        let bc = b % cols, br = b / cols
        var wx = 0.0, wy = 0.0, ws = 0.0
        for dr in -1...1 { for dc in -1...1 {
            let c = bc + dc, rr = br + dr
            guard c >= 0, c < cols, rr >= 0, rr < rows else { continue }
            let i = rr * cols + c, w = pow(value(i), 2)
            let p = center(i); wx += w * p.x; wy += w * p.y; ws += w
        } }
        let x = ws > 0 ? wx / ws : center(b).x, y = ws > 0 ? wy / ws : center(b).y
        // confidence = signal strength × separation from runner-up (unless runner-up is a neighbour,
        // which is expected for a dipole) × repeatability
        let snr = min(1, s1 / max(3, 10 * noise))
        let neighbour = abs(r[1] % cols - bc) <= 1 && abs(r[1] / cols - br) <= 1
        let sep = s1 > 0 ? (neighbour ? min(1, 0.6 + (s1 - s2) / s1) : (s1 - s2) / s1) : 0
        let rep = 1 - spread(b) * 0.6
        let plaus = LocatorCore.plausible(x: x, y: y)
        var conf = max(0, min(1, snr * (0.35 + 0.65 * sep) * rep))
        if !plaus { conf *= 0.7 }
        var retry: [Int] = []
        if conf < 0.55 && s1 > 0 {
            retry = [b]
            if s2 > 0.6 * s1 { retry.append(r[1]) }
            if samples[b].count < 2 { retry = Array(Set(retry + [b])) }
        }
        return Result(cell: b, x: x, y: y, confidence: conf, signal: s1, retry: retry, plausible: plaus)
    }
}
