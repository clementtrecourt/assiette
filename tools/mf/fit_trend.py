"""Try candidate trend-weight models against MacroFactor's exported trend."""
import csv, sys, math
rows = list(csv.DictReader(open(sys.argv[1])))
W = [float(r["weight"]) if r["weight"] else None for r in rows]
T = [float(r["trend"]) for r in rows]

def ema(alpha, init, skip_missing=True):
    out, t = [], init
    for w in W:
        if w is not None:
            t = t + alpha * (w - t)
        out.append(t)
    return out

def rmse(pred, lo=0):
    e = [(p - t) for p, t in zip(pred[lo:], T[lo:])]
    return math.sqrt(sum(x * x for x in e) / len(e)), max(abs(x) for x in e)

print("EMA, init = first trend value")
for a in [0.05, 0.07, 0.08, 0.09, 0.1, 0.11, 0.12, 0.15]:
    print(f"  alpha={a:.2f} rmse/max(kg) all={rmse(ema(a, T[0]))}  after30d={rmse(ema(a, T[0]), 30)}")
# best alpha + free init
best = min(((rmse(ema(a / 1000, i / 100), 30)[0], a / 1000, i / 100)
            for a in range(30, 200, 2) for i in range(6900, 7050, 2)))
print("best EMA (rmse, alpha, init):", best)
# implied per-day alpha where denominator is large
imp = [(T[i] - T[i-1]) / (W[i] - T[i-1]) for i in range(1, len(T)) if W[i] is not None and abs(W[i] - T[i-1]) > 0.8]
imp.sort(); print("implied alpha (|w-trend|>0.8kg): n=%d median=%.3f p10=%.3f p90=%.3f" % (len(imp), imp[len(imp)//2], imp[len(imp)//10], imp[9*len(imp)//10]))
