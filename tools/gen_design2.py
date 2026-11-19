#!/usr/bin/env python3
"""Generate design/directions-v2.html: 10 header variants, MacroFactor-like, macros on top."""
import sys

K, P, C, F = (1420, 2200), (98, 150), (160, 240), (45, 70)
def pct(a): return f"{min(a[0]/a[1],1)*100:.0f}%"
def rest(a): return a[1]-a[0]
def n(x): return f"{x:,}".replace(",", " ")

LOG = [
    ("7:45", "Flocons d'avoine", "60 g", 228, 8, 39, 4),
    ("7:45", "Banane", "1 moyenne · 118 g", 105, 1, 27, 0),
    ("7:45", "Lait demi-écrémé", "150 ml", 87, 5, 7, 2),
    ("12:50", "Poulet grillé", "150 g", 248, 46, 0, 6),
    ("12:50", "Riz basmati cuit", "200 g", 432, 6, 87, 6),
    ("16:15", "Skyr nature", "150 g", 147, 16, 6, 0),
    ("16:15", "Amandes", "30 g", 173, 6, 6, 15),
]
MEALS = [("Petit-déjeuner", LOG[0:3]), ("Déjeuner", LOG[3:5]), ("Collation", LOG[5:7]), ("Dîner", [])]

def entry(e, macros=True, time=False):
    t, name, q, k, p, c, f = e
    m = f'<span class="mm"><i class="p">{p}</i><i class="c">{c}</i><i class="f">{f}</i></span>' if macros else ""
    tm = f'<time>{t}</time>' if time else ""
    return f'<div class="en">{tm}<div class="nm"><b>{name}</b><small>{q}</small></div><div class="kv"><b class="tn">{k}</b>{m}</div></div>'

def log_meals(compact=False):
    out = []
    for title, items in MEALS:
        tot = sum(i[3] for i in items)
        out.append(f'<div class="ms"><span>{title}</span><span class="tn">{tot or ""}{" kcal" if tot else "<em>+ Ajouter</em>"}</span></div>')
        for e in (items[:2] if compact else items):
            out.append(entry(e))
    return "\n".join(out)

def log_time():
    out, last = [], None
    for e in LOG:
        if e[0] != last:
            out.append(f'<div class="ms"><span>{e[0]}</span><span></span></div>'); last = e[0]
        out.append(entry(e))
    return "\n".join(out)

def bar(label, a, cls, unit="g", remain=False):
    right = f'{rest(a)} {unit} restant{"es" if unit=="kcal" else "s"}' if remain else f'{n(a[0])} / {n(a[1])} {unit}'
    return f'<div class="hb {cls}"><div class="row"><span>{label}</span><span class="tn">{right}</span></div><div class="bar"><i style="width:{pct(a)}"></i></div></div>'

TABS = '<nav class="tabs"><span class="on t-j">Journal</span><span class="t-p">Progrès</span><span class="t-u">Profil</span></nav><div class="fab">+</div>'

def phone(cls, header, body, dark=False, tabs=TABS):
    return f'''<div class="ph mf {cls}{' dk' if dark else ''}"><div class="island"></div><div class="sb"><span>9:41</span><i></i></div>
<div class="hd">{header}</div><div class="lg">{body}</div>{tabs}</div>'''

DAYBAR = '<div class="dayb"><span class="chev">‹</span><b>Aujourd\'hui</b><span class="chev">›</span></div>'
WEEK = '<div class="week">' + "".join(
    f'<span class="{"on" if i==2 else ""}"><small>{d}</small><i style="--p:{p}"></i><b>{17+i}</b></span>'
    for i, (d, p) in enumerate(zip("LMMJVSD", [.98, 1.03, .65, 0, 0, 0, 0]))) + '</div>'

V = []

# 1 Four stacked bars
V.append(("Quatre barres", "La base MacroFactor : quatre barres empilées, mangé / objectif à droite. Lisible, chaque chiffre a sa place.",
    ["Le plus lisible", "Repas classiques"],
    phone("v1", DAYBAR + bar("Calories", K, "k", "kcal") + bar("Protéines", P, "p") + bar("Glucides", C, "c") + bar("Lipides", F, "f"), log_meals())))

# 2 Four columns
cols = "".join(f'<div class="col {c}"><small>{l}</small><b class="tn">{n(rest(a))}</b><div class="bar"><i style="width:{pct(a)}"></i></div><small class="tn">sur {n(a[1])}</small></div>'
               for l, a, c in [("Kcal", K, "k"), ("Prot.", P, "p"), ("Gluc.", C, "c"), ("Lip.", F, "f")])
V.append(("Quatre colonnes", "Une ligne de quatre colonnes affiche ce qu'il te reste. L'en-tête prend moitié moins de place, donc le journal en montre plus.",
    ["Compact", "Restant en gros"],
    phone("v2", DAYBAR + f'<div class="cols">{cols}</div>', log_meals())))

# 3 Week strip
V.append(("Semaine + chiffres", "Une bande des 7 jours en haut, avec un anneau d'adhérence par jour : tu changes de jour d'un toucher. En dessous, les 4 chiffres de la journée.",
    ["Navigation rapide", "Vue de la semaine"],
    phone("v3", WEEK + f'<div class="cols">{cols}</div>', log_meals())))

# 4 Calories hero + macro pills
pills = "".join(f'<div class="pill {c}"><b class="tn">{a[0]}<small>/{a[1]} g</small></b><div class="bar"><i style="width:{pct(a)}"></i></div><small>{l}</small></div>'
                for l, a, c in [("Protéines", P, "p"), ("Glucides", C, "c"), ("Lipides", F, "f")])
V.append(("Calories en vedette", "Le reste de calories en très grand, la jauge juste dessous, puis trois pastilles de macros. Tu sais en une seconde où tu en es.",
    ["Hiérarchie claire", "Un chiffre clé"],
    phone("v4", DAYBAR + f'<div class="hero"><div><b class="tn">{rest(K)}</b><span> kcal restantes</span></div><small class="tn">{n(K[0])} mangées · objectif {n(K[1])}</small><div class="bar k"><i style="width:{pct(K)}"></i></div></div><div class="pills">{pills}</div>', log_meals())))

# 5 Sticky compact (scrolled state)
mini = "".join(f'<span class="{c}"><b class="tn">{v}</b><small>{l}</small><i style="--w:{pct(a)}"></i></span>'
               for l, v, a, c in [("kcal", n(rest(K)), K, "k"), ("P", rest(P), P, "p"), ("G", rest(C), C, "c"), ("L", rest(F), F, "f")])
V.append(("Barre collante", "L'écran est montré défilé : l'en-tête se réduit à une barre fine qui reste en haut. Les chiffres restent visibles pendant que tu parcours le journal.",
    ["Toujours visible", "Maximum de place"],
    phone("v5", f'<div class="sticky">{mini}</div>', log_meals())))

# 6 Dark
V.append(("Sombre", "La variante 01 en mode sombre : fond noir, barres saturées, chiffres blancs. Confortable le soir.",
    ["Mode sombre", "Contraste fort"],
    phone("v6", DAYBAR + bar("Calories", K, "k", "kcal", True) + bar("Protéines", P, "p", remain=True) + bar("Glucides", C, "c", remain=True) + bar("Lipides", F, "f", remain=True), log_meals(), dark=True)))

# 7 Segmented calorie bar
kp, kc, kf = P[0]*4, C[0]*4, F[0]*9
seg = f'<div class="seg"><i class="p" style="width:{kp/K[1]*100:.1f}%"></i><i class="c" style="width:{kc/K[1]*100:.1f}%"></i><i class="f" style="width:{kf/K[1]*100:.1f}%"></i></div>'
leg = "".join(f'<span class="{c}"><i></i>{l} <b class="tn">{a[0]}</b>/{a[1]}</span>' for l, a, c in [("Prot.", P, "p"), ("Gluc.", C, "c"), ("Lip.", F, "f")])
V.append(("Barre segmentée", "Une seule barre de calories, découpée en kcal de protéines, glucides et lipides : tu vois d'où viennent tes calories.",
    ["Répartition visible", "Original"],
    phone("v7", DAYBAR + f'<div class="hero sm"><div><b class="tn">{n(K[0])}</b><span class="tn"> / {n(K[1])} kcal</span></div><small class="tn">{rest(K)} restantes</small></div>{seg}<div class="leg">{leg}</div>', log_meals())))

# 8 Four rings row
rings = "".join(f'<div class="rg {c}"><div class="ring" style="--p:{min(a[0]/a[1],1)}"></div><b class="tn">{n(rest(a))}</b><small>{l}</small></div>'
                for l, a, c in [("kcal", K, "k"), ("prot.", P, "p"), ("gluc.", C, "c"), ("lip.", F, "f")])
V.append(("Quatre anneaux", "Quatre anneaux alignés, le chiffre restant au centre de chacun. Plus doux visuellement, aussi rapide à lire.",
    ["Visuel", "Restant au centre"],
    phone("v8", DAYBAR + f'<div class="rings">{rings}</div>', log_meals())))

# 9 Table
rows = "".join(f'<tr class="{c}"><th>{l}</th><td class="tn">{n(a[1])}</td><td class="tn">{n(a[0])}</td><td class="tn r">{n(rest(a))}</td></tr>'
               for l, a, c in [("Kcal", K, "k"), ("Prot.", P, "p"), ("Gluc.", C, "c"), ("Lip.", F, "f")])
V.append(("Tableau", "Un mini tableau Objectif / Mangé / Reste. Aucun graphique, que des chiffres alignés : pour ceux qui comptent au gramme près.",
    ["Précis", "Zéro décoration"],
    phone("v9", DAYBAR + f'<table class="tb"><tr><th></th><th>Objectif</th><th>Mangé</th><th>Reste</th></tr>{rows}</table>', log_meals())))

# 10 Time log + fab menu
V.append(("Journal horodaté", "Les 4 barres en haut, puis les aliments classés par heure, sans cases repas (comme MacroFactor). Le + ouvre Rechercher, Scanner ou Ajout rapide.",
    ["Sans repas", "Menu d'ajout rapide"],
    phone("v10", DAYBAR + bar("Calories", K, "k", "kcal") + bar("Protéines", P, "p") + bar("Glucides", C, "c") + bar("Lipides", F, "f"),
          log_time() + '<div class="menu"><span>Rechercher</span><span>Scanner un code-barres</span><span>Ajout rapide</span></div>')))

cards = []
for i, (title, desc, tags, ph) in enumerate(V, 1):
    tg = "".join(f"<b>{t}</b>" for t in tags)
    cards.append(f'<article class="card">{ph}<div class="cap"><h2><span class="n">{i:02d}</span>{title}</h2><p>{desc}</p></div><div class="meta">{tg}</div></article>')

css = open(sys.argv[1]).read()
html = f'''<title>Assiette — en-têtes macros</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800&family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@500;600&display=swap">
<style>{css}</style>
<div class="wrap">
<header class="top"><span class="eyebrow">Assiette · v2 · inspiré de MacroFactor</span>
<h1>Calories et macros en haut : 10 variantes</h1>
<p class="lede">Sur toutes les maquettes, calories, protéines, glucides et lipides sont tout en haut, et le journal défile en dessous. Le style est épuré, dense en chiffres, avec une couleur par macro. Même journée partout : 1 420 kcal sur 2 200.</p>
<div class="shared"><span class="k">Calories</span><span class="p">Protéines</span><span class="c">Glucides</span><span class="f">Lipides</span></div></header>
<div class="grid">{"".join(cards)}</div>
<footer class="note"><p><strong>Ma recommandation : 01 ou 10 en clair et 06 en sombre</strong>, l'app suivant le réglage de l'iPhone. Les quatre barres sont le plus lisible, et l'en-tête se réduit en barre collante (05) quand tu fais défiler.</p>
<p>Tu peux combiner : l'en-tête d'une maquette, le journal d'une autre (par repas ou par heure). Dis-moi les numéros.</p></footer>
</div>'''
open(sys.argv[2], "w").write(html)
