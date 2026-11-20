"""Build design/coaching-v1/variantes.html: 3 key screens of maquettes.html in 5 style flavors."""
import re, sys

src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()
style = s[s.index("<style>") + 7:s.index("</style>")]
script = s[s.index("<script>"):s.index("</script>") + 9]

def figure(start, end):
    block = s[s.index(start):s.index(end)]
    block = re.sub(r"<figcaption>.*?</figcaption>", "", block, flags=re.S)
    return block.replace("<figure>", "<figure>").strip()

screens = [figure("<!-- 1. ACCUEIL -->", "<!-- 2. ACCUEIL SUITE -->"),
           figure("<!-- 3. JOURNAL -->", "<!-- 4. AJOUTER -->"),
           figure("<!-- 5. PROGRAMME -->", "<!-- 6. PROGRAMME SUITE -->")]

FLAVORS = [
    ("nuit", "1 · Nuit", "Noir pur pour écran OLED, cartes remplacées par de simples filets, couleurs de macros plus vives. Le plus sobre et le plus « pro ».", """
.fv-nuit{--bg:#000;--raise:#0a0a0c;--raise2:#151518;--line:#1d1d21;--line2:#2a2a2f;--kcal:#4d8dff;--carb:#2fd28a;--pro:#ff7a59;--fat:#ffc83d}
.fv-nuit .card{background:transparent;border:1px solid var(--line);box-shadow:none;border-radius:12px}
.fv-nuit .search{background:#0d0d10}
.fv-nuit .fcard{background:transparent;border:1px solid var(--line)}
.fv-nuit #kg-nuit stop:first-child{stop-color:#7fb0ff}.fv-nuit #kg-nuit stop:last-child{stop-color:#2f6ff0}
.fv-nuit #gg-nuit stop:first-child{stop-color:#5ef0a8}.fv-nuit #gg-nuit stop:last-child{stop-color:#1fb070}
"""),
    ("papier", "2 · Papier", "Thème clair : fond crème, cartes blanches avec une ombre douce, couleurs de macros plus profondes. Lisible en plein soleil.", """
.fv-papier{--bg:#f4f3ef;--raise:#ffffff;--raise2:#ecebe6;--line:#e6e4de;--line2:#d9d6cf;--fg:#16161a;--fg2:#38383e;--mut:#6b6b73;--mut2:#8a8a92;--mut3:#acacb2;--kcal:#2f6fe0;--carb:#1f9d66;--pro:#e0603a;--fat:#d9a514;--weight:#7c5cd6;--good:#1f9d66;--flame:#ea6a12}
.fv-papier .card{background:#fff;border:1px solid var(--line);box-shadow:0 1px 2px rgba(0,0,0,.04),0 10px 24px -14px rgba(0,0,0,.18)}
.fv-papier .fcard{background:#fff;box-shadow:0 1px 2px rgba(0,0,0,.05)}
.fv-papier .tabs .plus,.fv-papier .seg span.on{color:#fff}
.fv-papier .hi{background:#16161a}
.fv-papier .di{background:#000}
.fv-papier .search{background:#fff;box-shadow:0 -14px 22px -6px var(--bg),0 4px 14px -6px rgba(0,0,0,.15)}
.fv-papier circle[stroke="#2a2a2e"],.fv-papier circle[stroke="#2c2c31"],.fv-papier circle[stroke="#2f2f34"]{stroke:#e2dfd8}
.fv-papier .macros .bar,.fv-papier .jl .bar,.fv-papier .meter{background:#e6e3dc}
.fv-papier #kg-papier stop:first-child{stop-color:#5b93f0}.fv-papier #kg-papier stop:last-child{stop-color:#1f5bd0}
.fv-papier #gg-papier stop:first-child{stop-color:#3cc283}.fv-papier #gg-papier stop:last-child{stop-color:#14855a}
.fv-papier .day .kc{border-color:rgba(47,111,224,.35)}
"""),
    ("verre", "3 · Verre", "Fond sombre bleuté avec des halos colorés, cartes translucides et floutées, halo lumineux autour de l'anneau. Le plus spectaculaire.", """
.fv-verre{--bg:#0b0c12;--raise:rgba(255,255,255,.06);--raise2:rgba(255,255,255,.09);--line:rgba(255,255,255,.08);--line2:rgba(255,255,255,.13);--kcal:#7fb0ff;--carb:#6fe0a8;--pro:#ff9a7a;--fat:#ffd36e}
.fv-verre .scr{background:radial-gradient(70% 40% at 15% 8%,rgba(80,110,255,.35),transparent 70%),radial-gradient(60% 35% at 95% 45%,rgba(40,200,160,.18),transparent 70%),radial-gradient(80% 40% at 30% 95%,rgba(255,120,90,.14),transparent 70%),#0b0c12}
.fv-verre .card,.fv-verre .fcard{background:rgba(255,255,255,.055);border:1px solid rgba(255,255,255,.09);box-shadow:inset 0 1px 0 rgba(255,255,255,.08);backdrop-filter:blur(16px)}
.fv-verre .ring svg,.fv-verre .count svg{filter:drop-shadow(0 0 10px rgba(127,176,255,.45))}
.fv-verre .search{background:rgba(20,22,32,.7);backdrop-filter:blur(18px);border-color:rgba(255,255,255,.1);box-shadow:none}
.fv-verre .tabs{background:rgba(11,12,18,.75);backdrop-filter:blur(18px)}
.fv-verre .seg div{background:rgba(255,255,255,.07)}
.fv-verre #kg-verre stop:first-child{stop-color:#b9d3ff}.fv-verre #kg-verre stop:last-child{stop-color:#6b8cff}
"""),
    ("technique", "4 · Technique", "Typo Space Grotesk avec les chiffres en JetBrains Mono, angles presque droits, étiquettes en capitales, fine grille en fond. Côté tableau de bord de données.", """
.fv-technique{--bg:#0d0e0e;--raise:#141616;--raise2:#1c1f1f;--line:#252929;--line2:#323737;--kcal:#8ab4ff;--carb:#7ee2a8;--pro:#ff9a76;--fat:#ffd166}
.fv-technique .scr{font-family:'Space Grotesk',sans-serif;background-color:#0d0e0e;background-image:linear-gradient(rgba(255,255,255,.025) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.025) 1px,transparent 1px);background-size:16px 16px}
.fv-technique .ring .c b,.fv-technique .count .c b,.fv-technique .hero .side b,.fv-technique .card .v b,.fv-technique .macros .n,.fv-technique .pill,.fv-technique .ch,.fv-technique .day .kc,.fv-technique .day .s,.fv-technique .goal3 b,.fv-technique .fcard .q{font-family:'JetBrains Mono',monospace;letter-spacing:-.02em}
.fv-technique .ring .c b{font-size:27px}
.fv-technique .card,.fv-technique .fcard{border-radius:4px;background:#121414;border:1px solid var(--line);box-shadow:none}
.fv-technique .card .t,.fv-technique .sec h3,.fv-technique .macros .l{text-transform:uppercase;letter-spacing:.08em;font-size:10px;font-weight:600}
.fv-technique .sec h3::before{content:"// ";color:var(--mut3)}
.fv-technique .tb h2{font-weight:700;letter-spacing:-.03em}
.fv-technique .search,.fv-technique .seg div,.fv-technique .seg span,.fv-technique .ib,.fv-technique .tile,.fv-technique .btn2{border-radius:4px}
.fv-technique .tabs .plus{border-radius:6px}
.fv-technique .pill,.fv-technique .addc{border-radius:3px}
.fv-technique .macros .bar,.fv-technique .jl .bar{border-radius:0;height:4px}
"""),
    ("chaud", "5 · Chaud", "Gris-brun chaud, titres et grands chiffres en Fraunces (police à empattements), coins très arrondis, couleurs de macros pastel. Ambiance carnet gourmand haut de gamme.", """
.fv-chaud{--bg:#1a1715;--raise:#24201d;--raise2:#302a26;--line:#332d29;--line2:#433b36;--fg:#f7f0e8;--fg2:#ddd3c8;--mut:#ad9f93;--mut2:#86796e;--mut3:#5f554d;--kcal:#9db7f5;--carb:#9fd3a6;--pro:#f2a07b;--fat:#f1d17e;--weight:#d7b6f5;--good:#9fd3a6;--flame:#f2945b}
.fv-chaud .tb h2,.fv-chaud .ring .c b,.fv-chaud .count .c b,.fv-chaud .hero .side b,.fv-chaud .sec h3,.fv-chaud .card .v b,.fv-chaud .goal3 b{font-family:'Fraunces',serif;font-weight:600;letter-spacing:-.02em}
.fv-chaud .tb h2{font-size:26px}
.fv-chaud .ring .c b{font-size:33px}
.fv-chaud .card{border-radius:22px;background:linear-gradient(180deg,#28231f,#221e1b);border:1px solid rgba(255,240,225,.05);box-shadow:none}
.fv-chaud .fcard{border-radius:18px}
.fv-chaud .search{border-radius:20px;background:#24201d}
.fv-chaud .seg div{border-radius:20px;background:#24201d}.fv-chaud .seg span{border-radius:16px}
.fv-chaud .tabs .plus{border-radius:50%;background:#f7f0e8}
.fv-chaud .ib,.fv-chaud .btn2{border-radius:14px}
.fv-chaud circle[stroke="#2a2a2e"],.fv-chaud circle[stroke="#2c2c31"],.fv-chaud circle[stroke="#2f2f34"]{stroke:#3a332e}
.fv-chaud #kg-chaud stop:first-child{stop-color:#c5d5ff}.fv-chaud #kg-chaud stop:last-child{stop-color:#7f9cf0}
"""),
]

page_css = """
body{margin:0;padding:4px 0 24px;font-family:'DM Sans',system-ui,sans-serif;color:var(--foreground,#fafafa)}
.flavor{margin:0 0 34px}
.flavor h2{margin:0 0 4px;font-size:17px;letter-spacing:-.02em}
.flavor p{margin:0 0 14px;font-size:13px;line-height:1.5;color:var(--muted-foreground,#a1a1aa);max-width:640px}
.trio{display:flex;gap:12px;justify-content:center;flex-wrap:wrap}
.trio .ph{zoom:.75}
"""
body = []
for key, title, desc, css in FLAVORS:
    trio = "\n".join(screens)
    for gid in ("kg", "gg", "fa"):
        trio = trio.replace(f'id="{gid}"', f'id="{gid}-{key}"').replace(f"url(#{gid})", f"url(#{gid}-{key})")
    body.append(f'<section class="flavor fv-{key}"><h2>{title}</h2><p>{desc}</p><div class="trio">{trio}</div></section>')
    page_css += css

html = f"""<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Assiette variantes</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=DM+Sans:opsz,wght@9..40,400;9..40,500;9..40,600;9..40,700&family=Fraunces:opsz,wght@9..144,500;9..144,600;9..144,700&family=JetBrains+Mono:wght@500;600&family=Space+Grotesk:wght@400;500;600;700&display=swap">
<style>{style}
{page_css}</style></head><body>
{chr(10).join(body)}
{script}
</body></html>"""
# the base stylesheet sets body padding/colors for maquettes; page_css comes last and wins.
open(dst, "w", encoding="utf-8").write(html)
print("written", dst)
