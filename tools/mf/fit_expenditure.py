"""Explore how MacroFactor's daily expenditure reacts to intake and weight trend."""
import csv, sys, math
rows = list(csv.DictReader(open(sys.argv[1])))
f = lambda r, k: float(r[k]) if r[k] else None
K = [f(r, "kcal") for r in rows]; T = [f(r, "trend") for r in rows]; E = [f(r, "expenditure") for r in rows]
W = [f(r, "weight") for r in rows]
n = len(rows)

def raw(i, N, density, trend):
    """Energy-balance TDEE over the N days ending at i (skips unlogged days)."""
    if i - N < 0: return None
    ks = [K[j] for j in range(i - N + 1, i + 1) if K[j]]
    if not ks: return None
    return sum(ks) / len(ks) - (trend[i] - trend[i - N]) * density / N

# one-sided (real-time) Kalman level filter as a stand-in for the at-the-time trend
def kalman(q_level, q_slope, r):
    x, P, out = [W[0], 0.0], [[1, 0], [0, 0.01]], []
    for w in W:
        x = [x[0] + x[1], x[1]]
        P = [[P[0][0] + 2*P[0][1] + P[1][1] + q_level, P[0][1] + P[1][1]], [P[0][1] + P[1][1], P[1][1] + q_slope]]
        if w is not None:
            S = P[0][0] + r; k0, k1 = P[0][0]/S, P[1][0]/S; y = w - x[0]
            x = [x[0] + k0*y, x[1] + k1*y]
            P = [[(1-k0)*P[0][0], (1-k0)*P[0][1]], [P[1][0]-k1*P[0][0], P[1][1]-k1*P[0][1]]]
        out.append(x[0])
    return out

def simulate(N, density, alpha, cap, trend, start=40):
    e, pred = E[start - 1], {}
    for i in range(start, n):
        r = raw(i, N, density, trend)
        if r is not None:
            e += max(-cap, min(cap, alpha * (r - e)))
        pred[i] = e
    err = [pred[i] - E[i] for i in pred]
    return math.sqrt(sum(x*x for x in err) / len(err)), max(map(abs, err))

rt = kalman(1e-3, 1e-5, 0.3)
for name, tr in [("retro trend", T), ("realtime trend", rt)]:
    res = []
    for N in [7, 14, 21, 28]:
        for d in [5500, 6500, 7700]:
            for a in [0.02, 0.04, 0.06, 0.1, 0.15]:
                for cap in [10, 15, 20, 1e9]:
                    res.append((*[round(x) for x in simulate(N, d, a, cap, tr)], N, d, a, cap))
    res.sort()
    print(name, "best (rmse, max, window, density, alpha, cap):")
    for r in res[:6]: print("  ", r)

print("\nwider search")
for name, tr in [("retro", T), ("realtime", rt)]:
    res = []
    for N in [1, 2, 3, 5, 7, 10]:
        for d in [2000, 3000, 4000, 5000, 6000, 7700]:
            for a in [0.005, 0.01, 0.015, 0.02, 0.03]:
                res.append((*[round(x) for x in simulate(N, d, a, 1e9, tr)], N, d, a))
    res.sort(); print(name, res[:5])
# what does the rest of the error look like? residual vs time for best realtime model
