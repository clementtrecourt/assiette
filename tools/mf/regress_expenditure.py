"""Linear regression of daily expenditure change on intake gap and trend slope."""
import csv, sys, math
rows = list(csv.DictReader(open(sys.argv[1])))
f = lambda r, k: float(r[k]) if r[k] else None
K = [f(r, "kcal") for r in rows]; T = [f(r, "trend") for r in rows]; E = [f(r, "expenditure") for r in rows]
n = len(rows)

def ols(X, y):
    m = len(X[0]); A = [[sum(x[i]*x[j] for x in X) for j in range(m)] for i in range(m)]
    b = [sum(x[i]*yy for x, yy in zip(X, y)) for i in range(m)]
    for i in range(m):  # gaussian elimination
        p = A[i][i]
        for j in range(i+1, m):
            fct = A[j][i]/p; A[j] = [a - fct*c for a, c in zip(A[j], A[i])]; b[j] -= fct*b[i]
    coef = [0]*m
    for i in reversed(range(m)):
        coef[i] = (b[i] - sum(A[i][j]*coef[j] for j in range(i+1, m))) / A[i][i]
    pred = [sum(c*x for c, x in zip(coef, row)) for row in X]
    ss = sum((a-b)**2 for a, b in zip(pred, y)); st = sum((a - sum(y)/len(y))**2 for a in y)
    return coef, 1 - ss/st, math.sqrt(ss/len(y))

start = int(sys.argv[2]) if len(sys.argv) > 2 else 40
for N in [1, 2, 3, 5, 7, 14]:
    X, y = [], []
    for i in range(max(start, N), n):
        ks = [K[j] for j in range(i-N+1, i+1) if K[j]]
        if not ks: continue
        X.append([sum(ks)/len(ks) - E[i-1], (T[i]-T[i-N])/N])
        y.append(E[i]-E[i-1])
    c, r2, rm = ols(X, y)
    print(f"N={N:2d}  dE = {c[0]:.4f}*(meanK-E) + {c[1]:.1f}*slope   => density={-c[1]/c[0]:.0f} kcal/kg  R2={r2:.2f} rmse={rm:.1f}")
