"""Two-sided smoothers vs MacroFactor trend (is the exported trend retrospective?)."""
import csv, sys, math
rows = list(csv.DictReader(open(sys.argv[1])))
W = [float(r["weight"]) if r["weight"] else None for r in rows]
T = [float(r["trend"]) for r in rows]
n = len(T)
def rmse(p, lo=0, hi=None):
    e = [a - b for a, b in zip(p[lo:hi], T[lo:hi])]
    return round(math.sqrt(sum(x*x for x in e)/len(e)), 3), round(max(map(abs, e)), 3)

# 1) Rauch-Tung-Striebel smoother on local linear trend (level + slope)
def rts(q_level, q_slope, r):
    import copy
    x = [W[0] if W[0] else T[0], 0.0]; P = [[1, 0], [0, 0.01]]
    xs, Ps, xp_, Pp_ = [], [], [], []
    for w in W:
        # predict
        xp = [x[0] + x[1], x[1]]
        Pp = [[P[0][0] + 2*P[0][1] + P[1][1] + q_level, P[0][1] + P[1][1]],
              [P[0][1] + P[1][1], P[1][1] + q_slope]]
        if w is not None:
            S = Pp[0][0] + r; K = [Pp[0][0]/S, Pp[1][0]/S]; y = w - xp[0]
            x = [xp[0] + K[0]*y, xp[1] + K[1]*y]
            P = [[(1-K[0])*Pp[0][0], (1-K[0])*Pp[0][1]], [Pp[1][0] - K[1]*Pp[0][0], Pp[1][1] - K[1]*Pp[0][1]]]
        else:
            x, P = xp, Pp
        xs.append(x); Ps.append(P); xp_.append(xp); Pp_.append(Pp)
    sm = [None]*n; sm[-1] = xs[-1]; Psm = Ps[-1]
    for k in range(n-2, -1, -1):
        Pp = Pp_[k+1]; det = Pp[0][0]*Pp[1][1] - Pp[0][1]*Pp[1][0]
        inv = [[Pp[1][1]/det, -Pp[0][1]/det], [-Pp[1][0]/det, Pp[0][0]/det]]
        F = [[1, 1], [0, 1]]; P = Ps[k]
        PFt = [[P[0][0] + P[0][1], P[0][1]], [P[1][0] + P[1][1], P[1][1]]]
        C = [[PFt[i][0]*inv[0][j] + PFt[i][1]*inv[1][j] for j in range(2)] for i in range(2)]
        d = [sm[k+1][0] - xp_[k+1][0], sm[k+1][1] - xp_[k+1][1]]
        sm[k] = [xs[k][0] + C[0][0]*d[0] + C[0][1]*d[1], xs[k][1] + C[1][0]*d[0] + C[1][1]*d[1]]
    return [s[0] for s in sm], [f[0] for f in xs]

best = []
for ql in [0, 1e-5, 1e-4, 1e-3, 1e-2]:
    for qs in [1e-7, 1e-6, 1e-5, 1e-4, 1e-3]:
        for r in [0.1, 0.2, 0.3, 0.5]:
            s, f = rts(ql, qs, r)
            best.append((rmse(s)[0], rmse(f)[0], ql, qs, r))
best.sort(); print("RTS smoother best (rmse_smooth, rmse_filter, q_level, q_slope, r):"); [print(" ", b) for b in best[:5]]
best.sort(key=lambda b: b[1]); print("Kalman filter (one-sided) best:", best[0])

# 2) centered moving average
for h in [5, 7, 10, 14, 21]:
    p = []
    for i in range(n):
        v = [W[j] for j in range(max(0, i-h), min(n, i+h+1)) if W[j] is not None]
        p.append(sum(v)/len(v))
    print(f"centered MA ±{h}d:", rmse(p), " interior:", rmse(p, 25, n-25))

# 3) how smooth is MF trend? second differences
d1 = [T[i]-T[i-1] for i in range(1, n)]
print("trend daily change: min %.3f max %.3f" % (min(d1), max(d1)))
print("last 15 days weight/trend:", [(r["date"][5:], r["weight"], r["trend"]) for r in rows[-15:]])
