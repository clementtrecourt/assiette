import Foundation

/// Trend weight from noisy daily scale readings.
///
/// The model is a local linear trend: a hidden weight level that drifts with a slowly changing
/// slope, observed through scale noise. A Kalman filter gives the **real-time** trend (only past
/// readings, what the app knew that day, used by the expenditure estimate). A Rauch–Tung–Striebel
/// pass then gives the **retrospective** trend (past values revised with later readings), which is
/// what MacroFactor displays for past days.
struct EngineWeightTrend: Sendable {
    struct Point: Equatable, Sendable {
        /// Trend weight using readings up to that day (kg).
        var realtime: Double
        /// Trend weight using every reading (kg).
        var smoothed: Double
    }

    /// One point per input day; nil before the first weigh-in.
    static func compute(scaleWeights: [Double?], parameters: EngineParameters = .calibrated) -> [Point?] {
        guard let start = scaleWeights.firstIndex(where: { $0 != nil }), let firstWeight = scaleWeights[start] else {
            return Array(repeating: nil, count: scaleWeights.count)
        }
        let q = (level: parameters.trendLevelNoise, slope: parameters.trendSlopeNoise)
        let r = parameters.scaleNoise

        var x = Vec2(firstWeight, 0)
        var p = Mat2(1, 0, 0, 0.01)
        var filtered: [Vec2] = [], filteredCov: [Mat2] = [], predicted: [Vec2] = [], predictedCov: [Mat2] = []

        for weight in scaleWeights[start...] {
            // Predict: level += slope.
            let xp = Vec2(x.a + x.b, x.b)
            let pp = Mat2(p.a + 2 * p.b + p.d + q.level, p.b + p.d,
                          p.c + p.d, p.d + q.slope)
            x = xp
            p = pp
            if let weight {
                let s = pp.a + r
                let k = Vec2(pp.a / s, pp.c / s)
                let innovation = weight - xp.a
                x = Vec2(xp.a + k.a * innovation, xp.b + k.b * innovation)
                p = Mat2((1 - k.a) * pp.a, (1 - k.a) * pp.b,
                         pp.c - k.b * pp.a, pp.d - k.b * pp.b)
            }
            filtered.append(x); filteredCov.append(p)
            predicted.append(xp); predictedCov.append(pp)
        }

        var smoothed = filtered
        if filtered.count > 1 {
            for k in stride(from: filtered.count - 2, through: 0, by: -1) {
                let pk = filteredCov[k]
                let pkFt = Mat2(pk.a + pk.b, pk.b, pk.c + pk.d, pk.d) // P · Fᵀ
                let gain = pkFt * predictedCov[k + 1].inverse
                let next = smoothed[k + 1], nextPrediction = predicted[k + 1]
                smoothed[k] = filtered[k] + gain * Vec2(next.a - nextPrediction.a, next.b - nextPrediction.b)
            }
        }

        var result = [Point?](repeating: nil, count: start)
        for i in filtered.indices {
            result.append(Point(realtime: filtered[i].a, smoothed: smoothed[i].a))
        }
        return result
    }
}

// MARK: - 2×2 linear algebra

private struct Vec2 {
    var a: Double, b: Double
    init(_ a: Double, _ b: Double) { self.a = a; self.b = b }
    static func + (l: Vec2, r: Vec2) -> Vec2 { Vec2(l.a + r.a, l.b + r.b) }
}

/// Row-major 2×2 matrix [[a, b], [c, d]].
private struct Mat2 {
    var a: Double, b: Double, c: Double, d: Double
    init(_ a: Double, _ b: Double, _ c: Double, _ d: Double) { self.a = a; self.b = b; self.c = c; self.d = d }

    var inverse: Mat2 {
        let det = a * d - b * c
        return Mat2(d / det, -b / det, -c / det, a / det)
    }

    static func * (l: Mat2, r: Mat2) -> Mat2 {
        Mat2(l.a * r.a + l.b * r.c, l.a * r.b + l.b * r.d,
             l.c * r.a + l.d * r.c, l.c * r.b + l.d * r.d)
    }

    static func * (m: Mat2, v: Vec2) -> Vec2 {
        Vec2(m.a * v.a + m.b * v.b, m.c * v.a + m.d * v.b)
    }
}
