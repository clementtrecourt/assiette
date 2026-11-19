#!/usr/bin/env python3
"""design/directions-v3.html: header 02 (four columns) + 5 ways to show what was eaten."""
import sys
K, P, C, F = (1420, 2200), (98, 150), (160, 240), (45, 70)
def pct(a): return f"{min(a[0]/a[1],1)*100:.0f}%"
def rest(a): return a[1]-a[0]
def n(x): return f"{x:,}".replace(",", " ")
LOG = [("7:45","Flocons d'avoine","60 g",228,8,39,4),("7:45","Banane","1 moyenne",105,1,27,0),
       ("7:45","Lait demi-écrémé","150 ml",87,5,7,2),("12:50","Poulet grillé","150 g",248,46,0,6),
       ("12:50","Riz basmati cuit","200 g",432,6,87,6),("16:15","Skyr nature","150 g",147,16,6,0),
       ("16:15","Amandes","30 g",173,6,6,15)]
MEALS=[("Petit-déjeuner",LOG[0:3]),("Déjeuner",LOG[3:5]),("Collation",LOG[5:7]),("Dîner",[])]
def tot(items,i): return sum(e[i] for e in items)

cols = "".join(f'<div class="col {c}"><small>{l}</small><b class="tn">{n(rest(a))}</b><div class="bar"><i style="width:{pct(a)}"></i></div><small class="tn">sur {n(a[1])}</small></div>'
               for l,a,c in [("Kcal",K,"k"),("Prot.",P,"p"),("Gluc.",C,"c"),("Lip.",F,"f")])
HEAD = '<div class="dayb"><span class="chev">‹</span><b>Aujourd\'hui</b><span class="chev">›</span></div>' + f'<div class="cols">{cols}</div>'
TABS = '<nav class="tabs"><span class="on t-j">Journal</span><span class="t-p">Progrès</span><span class="t-u">Profil</span></nav>'
FAB = '<div class="fab">+</div>'
def phone(cls, body, fab=True):
    return f'<div class="ph mf {cls}"><div class="island"></div><div class="sb"><span>9:41</span><i></i></div><div class="hd">{HEAD}</div><div class="lg">{body}</div>{TABS}{FAB if fab else ""}</div>'
def mm(p,c,f): return f'<span class="mm"><i class="p">{p}</i><i class="c">{c}</i><i class="f">{f}</i></span>'

V=[]
# 1 Collapsible meal cards
b=[]
for i,(t,it) in enumerate(MEALS):
    if not it:
        b.append(f'<div class="mc empty"><div class="row"><b>{t}</b><span class="add">+ Ajouter</span></div></div>'); continue
    open_=i==1
    head=f'<div class="row"><b>{t}</b><span class="tn"><b>{tot(it,3)}</b> kcal</span></div><div class="row sub"><span class="names">{" · ".join(e[1] for e in it)}</span>{mm(tot(it,4),tot(it,5),tot(it,6))}</div>'
    inner="".join(f'<div class="li"><span>{e[1]} <small>{e[2]}</small></span><span class="tn">{e[3]}</span></div>' for e in it) if open_ else ""
    b.append(f'<div class="mc{" open" if open_ else ""}">{head}{inner}<span class="chev2">{"⌃" if open_ else "⌄"}</span></div>')
V.append(("Cartes repliables","Une carte par repas : total, macros et noms des aliments sur deux lignes. Un toucher déplie le détail (ici le déjeuner). Toute la journée tient sur un écran.",["Vue d'ensemble","Détail à la demande"],phone("w1","".join(b))))

# 2 Timeline
b=['<div class="tl">']
last=None
for e in LOG:
    if e[0]!=last:
        grp=[x for x in LOG if x[0]==e[0]]
        b.append(f'<div class="tg"><time>{e[0]}</time><div class="tc">' + "".join(f'<div class="li"><span>{x[1]} <small>{x[2]}</small></span><span class="tn">{x[3]}</span></div>' for x in grp) + f'<div class="tt">{mm(tot(grp,4),tot(grp,5),tot(grp,6))}<span class="tn">{tot(grp,3)} kcal</span></div></div></div>')
        last=e[0]
b.append('<div class="tg now"><time>19:40</time><div class="tc ghost">Maintenant : + Ajouter</div></div></div>')
V.append(("Fil horaire","Les aliments s'alignent sur une ligne du temps, regroupés par heure de prise, avec le sous-total de chaque prise. Le dernier point « Maintenant » invite à noter le prochain repas.",["Chronologique","Sans cases repas"],phone("w2","".join(b))))

# 3 Tiles grid
b=[]
for t,it in MEALS:
    b.append(f'<div class="ms"><span>{t}</span><span class="tn">{tot(it,3) or ""}</span></div><div class="tiles">')
    for e in it:
        dom=max((e[4]*4,"p"),(e[5]*4,"c"),(e[6]*9,"f"))[1]
        b.append(f'<div class="tile {dom}"><b>{e[1]}</b><small>{e[2]}</small><span class="tn">{e[3]} kcal</span></div>')
    b.append('<div class="tile addt">+</div></div>')
V.append(("Vignettes","Chaque aliment est une vignette, avec un liseré de la couleur de sa macro dominante (rouge = surtout des protéines). La tuile + de chaque repas ajoute un aliment.",["Visuel","Macro dominante"],phone("w3","".join(b))))

# 4 Spreadsheet
rows=['<table class="sh"><tr><th>Aliment</th><th>kcal</th><th class="p">P</th><th class="c">G</th><th class="f">L</th></tr>']
for t,it in MEALS:
    rows.append(f'<tr class="mh"><th>{t}</th><td class="tn">{tot(it,3) or "–"}</td><td class="tn">{tot(it,4) or ""}</td><td class="tn">{tot(it,5) or ""}</td><td class="tn">{tot(it,6) or ""}</td></tr>')
    for e in it:
        rows.append(f'<tr><th>{e[1]}<small>{e[2]}</small></th><td class="tn">{e[3]}</td><td class="tn">{e[4]}</td><td class="tn">{e[5]}</td><td class="tn">{e[6]}</td></tr>')
rows.append(f'<tr class="tot"><th>Total</th><td class="tn">{n(K[0])}</td><td class="tn">{P[0]}</td><td class="tn">{C[0]}</td><td class="tn">{F[0]}</td></tr></table>')
V.append(("Tableau de bord","Un tableur : une ligne par aliment, colonnes kcal, P, G, L alignées, sous-total par repas et total du jour en bas. Pour suivre ses macros au gramme près.",["Précis","Tous les chiffres"],phone("w4","".join(rows))))

# 5 Meal share bars + chips
b=[]
for t,it in MEALS:
    k=tot(it,3)
    w=f"{k/K[0]*100:.0f}%" if k else "0%"
    chips="".join(f'<span>{e[1]} <b class="tn">{e[3]}</b></span>' for e in it) or '<span class="ghost">+ Ajouter le dîner</span>'
    b.append(f'<div class="mb"><div class="row"><b>{t}</b><span class="tn">{k or "–"} kcal · {round(k/K[0]*100) if k else 0} %</span></div><div class="bar k"><i style="width:{w}"></i></div><div class="chips">{chips}</div></div>')
V.append(("Part de la journée","Chaque repas a une barre qui montre sa part des calories du jour (le déjeuner pèse 48 %). Les aliments sont en pastilles : un toucher pour modifier, appui long pour supprimer.",["Équilibre des repas","Très compact"],phone("w5","".join(b))))

cards=[]
for i,(title,desc,tags,ph) in enumerate(V,1):
    cards.append(f'<article class="card">{ph}<div class="cap"><h2><span class="n">{i:02d}</span>{title}</h2><p>{desc}</p></div><div class="meta">{"".join(f"<b>{t}</b>" for t in tags)}</div></article>')
css=open(sys.argv[1]).read()+open(sys.argv[2]).read()
open(sys.argv[3],"w").write(f'''<title>Assiette — journal du jour</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800&family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@500;600&display=swap">
<style>{css}</style>
<div class="wrap">
<header class="top"><span class="eyebrow">Assiette · v3 · en-tête 02 retenu</span>
<h1>Ce qui est mangé : 5 variantes</h1>
<p class="lede">L'en-tête quatre colonnes reste identique sur les 5 maquettes. Seule change la façon d'afficher les aliments mangés en dessous. Même journée : 7 aliments sur 3 repas, dîner vide.</p></header>
<div class="grid">{"".join(cards)}</div>
<footer class="note"><p><strong>Ma recommandation : 01, les cartes repliables.</strong> La journée tient sur un écran sans défiler, et le détail reste à un toucher.</p><p>Dis-moi le numéro, ou une combinaison (par exemple les cartes de 01 avec le tableau de 04 dans la carte dépliée).</p></footer>
</div>''')
