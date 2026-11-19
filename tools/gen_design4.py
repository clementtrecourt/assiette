#!/usr/bin/env python3
"""design/directions-v4.html: chosen layout (header 02 + timeline 02) in 5 dark finishes."""
import sys
K, P, C, F = (1420, 2200), (98, 150), (160, 240), (45, 70)
def pct(a): return f"{min(a[0]/a[1],1)*100:.0f}%"
def rest(a): return a[1]-a[0]
def n(x): return f"{x:,}".replace(",", " ")
LOG = [("7:45","Flocons d'avoine","60 g",228,8,39,4),("7:45","Banane","1 moyenne",105,1,27,0),
       ("7:45","Lait demi-écrémé","150 ml",87,5,7,2),("12:50","Poulet grillé","150 g",248,46,0,6),
       ("12:50","Riz basmati cuit","200 g",432,6,87,6),("16:15","Skyr nature","150 g",147,16,6,0),
       ("16:15","Amandes","30 g",173,6,6,15)]
def tot(items,i): return sum(e[i] for e in items)
def mm(p,c,f): return f'<span class="mm"><i class="p">{p}</i><i class="c">{c}</i><i class="f">{f}</i></span>'
cols = "".join(f'<div class="col {c}"><small>{l}</small><b class="tn">{n(rest(a))}</b><div class="bar"><i style="width:{pct(a)}"></i></div><small class="tn">sur {n(a[1])}</small></div>'
               for l,a,c in [("Kcal",K,"k"),("Prot.",P,"p"),("Gluc.",C,"c"),("Lip.",F,"f")])
HEAD = '<div class="dayb"><span class="chev">‹</span><b>Aujourd\'hui</b><span class="chev">›</span></div>' + f'<div class="cols">{cols}</div>'
b=['<div class="tl">']; seen=[]
for e in LOG:
    if e[0] in seen: continue
    seen.append(e[0]); grp=[x for x in LOG if x[0]==e[0]]
    b.append(f'<div class="tg"><time>{e[0]}</time><div class="tc">' + "".join(f'<div class="li"><span>{x[1]} <small>{x[2]}</small></span><span class="tn">{x[3]}</span></div>' for x in grp) + f'<div class="tt">{mm(tot(grp,4),tot(grp,5),tot(grp,6))}<span class="tn">{tot(grp,3)} kcal</span></div></div></div>')
b.append('<div class="tg now"><time>19:40</time><div class="tc ghost">Maintenant : + Ajouter</div></div></div>')
BODY="".join(b)
TABS='<nav class="tabs"><span class="on t-j">Journal</span><span class="t-p">Progrès</span><span class="t-u">Profil</span></nav><div class="fab">+</div>'

THEMES = [
  ("OLED noir", "Noir pur, cartes gris très foncé, couleurs de macros vives. Sur iPhone OLED, les pixels noirs sont éteints : contraste maximal et économie de batterie.",
   ["Le plus contrasté","Économise la batterie"],
   "--bgp:#000;--fg:#f5f5f7;--mut:#8a8a90;--ln:#1f1f22;--tr:#121214;--k:#f5f5f7;--p:#ff5c74;--c:#4da3ff;--f:#ffb83d;--ac:#4da3ff;--fabbg:#f5f5f7;--fabfg:#000", ""),
  ("Graphite", "Le gris sombre natif d'iOS (comme Réglages ou Santé), cartes un peu plus claires. Moins dur que le noir pur et parfaitement cohérent avec le système.",
   ["Natif iOS","Doux pour les yeux"],
   "--bgp:#1c1c1e;--fg:#f2f2f7;--mut:#98989f;--ln:#2c2c2e;--tr:#2c2c2e;--k:#e5e5ea;--p:#ff6482;--c:#5eb1ff;--f:#ffc94d;--ac:#0a84ff;--fabbg:#0a84ff;--fabfg:#fff", ""),
  ("Bleu nuit", "Fond bleu marine profond, cartes bleu ardoise, accent turquoise. Plus d'ambiance qu'un gris neutre, toujours sobre.",
   ["Ambiance calme","Accent turquoise"],
   "--bgp:#0a1020;--fg:#e8eefc;--mut:#7f8bab;--ln:#18223a;--tr:#121b30;--k:#e8eefc;--p:#ff7a90;--c:#56b4ff;--f:#ffc65c;--ac:#3ee0c5;--fabbg:#3ee0c5;--fabfg:#04131a", ""),
  ("Athlète", "Noir avec un accent citron vert et des chiffres larges et serrés. Look sportif, pensé pour la sèche et la prise de masse. Les protéines restantes ressortent en vert.",
   ["Sportif","Gros chiffres"],
   "--bgp:#0a0a0a;--fg:#f4f4f4;--mut:#80807f;--ln:#1e1e1e;--tr:#151515;--k:#f4f4f4;--p:#c6ff3d;--c:#6fb8ff;--f:#ffb13b;--ac:#c6ff3d;--fabbg:#c6ff3d;--fabfg:#0a0a0a", "sport"),
  ("Ambre", "Brun très foncé, texte crème et accent ambre, sans lumière bleue. Le plus reposant le soir, au moment de noter le dîner.",
   ["Lecture du soir","Chaleureux"],
   "--bgp:#14100c;--fg:#f3e9dc;--mut:#9a8b78;--ln:#262019;--tr:#1e1913;--k:#f3e9dc;--p:#ff7b6b;--c:#7fb7d9;--f:#f5b544;--ac:#f5b544;--fabbg:#f5b544;--fabfg:#14100c", ""),
]
cards=[]
for i,(t,d,tags,vars_,extra) in enumerate(THEMES,1):
    ph=f'<div class="ph mf dk {extra}" style="{vars_}"><div class="island"></div><div class="sb"><span>9:41</span><i></i></div><div class="hd">{HEAD}</div><div class="lg">{BODY}</div>{TABS}</div>'
    cards.append(f'<article class="card">{ph}<div class="cap"><h2><span class="n">{i:02d}</span>{t}</h2><p>{d}</p></div><div class="meta">{"".join(f"<b>{x}</b>" for x in tags)}</div></article>')
css=open(sys.argv[1]).read()+open(sys.argv[2]).read()+'''
/* v4 dark finishes */
.ph.dk .tg.now::before{background:var(--ac)}
.ph.dk .tc.ghost{color:var(--ac);font-weight:600}
.ph.dk .fab{background:var(--fabbg);color:var(--fabfg)}
.ph.dk .tabs span.on{color:var(--ac)}
.ph.dk .tg::before{box-shadow:0 0 0 3px var(--bgp)}
.ph.sport{font-family:"Archivo",var(--ios)}
.ph.sport .col b{font-family:"Archivo Black",var(--ios);font-size:18px;letter-spacing:-.02em}
.ph.sport .col.p b{color:var(--p)}
.ph.sport .dayb b{font-family:"Archivo Black",var(--ios);text-transform:uppercase;letter-spacing:.02em}
'''
open(sys.argv[3],"w").write(f'''<title>Assiette — finitions sombres</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wght@400;600;700&family=Archivo+Black&family=Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800&family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@500;600&display=swap">
<style>{css}</style>
<div class="wrap">
<header class="top"><span class="eyebrow">Assiette · v4 · en-tête 02 + fil horaire</span>
<h1>Finitions : 5 thèmes sombres</h1>
<p class="lede">La mise en page est fixée : 4 colonnes en haut, aliments sur une ligne du temps. Seuls changent le fond, les surfaces, l'accent et la typo des chiffres.</p></header>
<div class="grid">{"".join(cards)}</div>
<footer class="note"><p><strong>Ma recommandation : 01 (OLED noir)</strong>, le plus lisible et le plus proche de MacroFactor en sombre. Je peux aussi faire suivre le réglage de l'iPhone : le thème choisi en sombre, une version claire assortie en mode clair.</p><p>Dis-moi le numéro.</p></footer>
</div>''')
