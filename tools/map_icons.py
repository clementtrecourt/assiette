#!/usr/bin/env python3
"""Map OpenNutrition food ids to the icon shown on their public food page.

Usage: python3 -I tools/map_icons.py <opennutrition_foods.tsv> <out icons.tsv>
Visits https://www.opennutrition.app/search/<slug>-<id> (allowed by robots.txt) for every
non-grocery food (grocery pages have no icon), politely (few requests/second, resumable),
and records the CloudFront icon file name. Images themselves are NOT downloaded here:
the app loads them from the OpenNutrition CDN and caches them on the device.
"""
import concurrent.futures as cf, csv, gzip, os, re, sys, threading, time, urllib.request

csv.field_size_limit(10**9)
SRC, OUT = sys.argv[1], sys.argv[2]
ICON_RE = re.compile(r'\\?"src\\?":\\?"https://drd3kry2ubqnc\.cloudfront\.net/([A-Za-z0-9_\-]+)@4x\.webp\\?",\\?"alt\\?":\\?"[^"\\]*\\?",\\?"width\\?":48')
WORKERS, DELAY = 3, 0.5

def slug(name):
    return re.sub(r'[^a-z0-9]+', '-', re.sub(r"[,'()]", '', name.lower())).strip('-')

done = set()
if os.path.exists(OUT):
    with open(OUT) as f:
        done = {line.split('\t')[0] for line in f if line.strip()}
todo = []
with open(SRC, newline='', encoding='utf-8') as f:
    for r in csv.DictReader(f, delimiter='\t'):
        if r['type'] != 'grocery' and r['id'] not in done:
            todo.append((r['id'], r['name']))
print(f"{len(done)} done, {len(todo)} to fetch", flush=True)
lock = threading.Lock()
out = open(OUT, 'a')

def fetch(item):
    fid, name = item
    url = f"https://www.opennutrition.app/search/{slug(name)}-{fid[3:]}"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (personal icon mapper)", "Accept-Encoding": "gzip"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                body = resp.read()
                if resp.headers.get('Content-Encoding') == 'gzip':
                    body = gzip.decompress(body)
            m = ICON_RE.search(body.decode('utf-8', 'replace'))
            icon = m.group(1) if m else ''
            break
        except Exception as e:  # 404 / network: record empty, retry transient
            icon = ''
            if getattr(e, 'code', None) == 404:
                break
            time.sleep(5 * (attempt + 1))
    with lock:
        out.write(f"{fid}\t{icon}\n"); out.flush()
    time.sleep(DELAY)
    return icon

n = 0
with cf.ThreadPoolExecutor(WORKERS) as ex:
    for icon in ex.map(fetch, todo):
        n += 1
        if n % 250 == 0:
            print(f"{n}/{len(todo)}", flush=True)
print("finished", flush=True)
