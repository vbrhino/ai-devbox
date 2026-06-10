#!/usr/bin/env python3
"""
Deal Agent — AI Price Comparison Tool
Zoekt de beste prijzen via SearXNG + Hermes AI.
Gebruik: python3 deal-agent.py "Lay-Z-Spa Palm Springs"
"""
import json, re, sys, urllib.parse, requests, os
from bs4 import BeautifulSoup

SEARXNG = os.environ.get("SEARXNG_URL", "http://192.168.4.78:8888")
OLLAMA = os.environ.get("OLLAMA_URL", "http://localhost:11434")
MODEL = "hermes3:8b"
CACHE = {}

def ask(prompt, system="Je helpt met prijsvergelijking.", temp=0.15):
    key = prompt[:80]
    if key in CACHE: return CACHE[key]
    try:
        r = requests.post(f"{OLLAMA}/api/chat", json={
            "model": MODEL, "stream": False,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": prompt},
            ],
            "options": {"temperature": temp, "num_predict": 1024},
        }, timeout=60)
        result = r.json()["message"]["content"]
        CACHE[key] = result
        return result
    except: return ""

def fetch(url):
    try:
        return requests.get(url, timeout=10, headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }).text
    except: return None

def search(query, max_r=8):
    try:
        r = requests.get(f"{SEARXNG}/search", params={
            "q": query, "format": "json", "language": "nl-NL",
            "categories": "general,shopping", "pageno": 1,
        }, timeout=15)
        return r.json().get("results", [])[:max_r]
    except: return []

def parse_jsonld(html):
    prices = []
    soup = BeautifulSoup(html, "lxml") if html else BeautifulSoup("", "lxml")
    for script in soup.find_all("script", type="application/ld+json"):
        try:
            data = json.loads(script.string)
            items = data.get("@graph", [data]) if isinstance(data, dict) else [data]
            for item in (items if isinstance(items, list) else [items]):
                off = item.get("offers", {})
                if isinstance(off, dict):
                    p = off.get("price", ""); prices.append(float(p))
                elif isinstance(off, list):
                    for o in off:
                        p = o.get("price", ""); prices.append(float(p))
        except: continue
    return prices

def hermes_extract_price(html_text, product):
    r = ask(
        f"Product: {product}\n\n{html_text[:2000]}\n\nWat is de verkoopprijs? Alleen €bedrag of ONDUIDELIJK.",
        "Alleen €bedrag of ONDUIDELIJK.", 0.1)
    m = re.search(r'€?\s*(\d+[.,]?\d*)', r)
    if m:
        v = float(m.group(1).replace(',','.'))
        if 20 < v < 5000: return round(v), f"€{m.group(1)}"
    return None, None

def search_item(item):
    """Zoek naar een product via SearXNG + Hermes."""
    print(f"\n{'='*60}")
    print(f"  🔍 '{item}'")
    print('='*60)
    
    # Stap 1: Vind URLs
    queries = [f"{item} kopen", f"{item} prijs", f"{item} aanbieding"]
    all_urls = []; seen = set()
    for q in queries:
        for r in search(q, 6):
            url = r.get("url","")
            key = url.split("?")[0]
            if key not in seen and url.startswith("http"):
                seen.add(key)
                all_urls.append({"url": url, "title": r.get("title","?")})
    
    print(f"   {len(all_urls)} URLs gevonden")
    if not all_urls:
        print("   ❌ Geen resultaten")
        return
    
    # Stap 2: Hermes selecteert
    url_list = "\n".join(f"{i+1}. {r['title'][:50]} — {r['url'][:60]}" 
                        for i,r in enumerate(all_urls[:12]))
    sel = ask(
        f"Product: {item}\n\nURLs:\n{url_list}\n\nWelke zijn echte webwinkels? Alleen nummers, komma-gescheiden.",
        "Alleen nummers.", 0.1)
    
    selected = []
    for s in re.findall(r'\d+', sel):
        idx = int(s)-1
        if 0 <= idx < len(all_urls): selected.append(all_urls[idx])
    if not selected: selected = all_urls[:5]
    print(f"   {len(selected)} winkels geselecteerd\n")
    
    # Stap 3: Bezoek + prijzen
    results = []
    for store in selected:
        print(f"   📡 {store['title'][:40]}...", end=" ", flush=True)
        html = fetch(store["url"])
        
        if html:
            prices = parse_jsonld(html)
            if prices:
                p = prices[0]
                results.append({"winkel": store['title'][:50], "prijs": f"€{p:.0f}", "price_val": p, "url": store['url'], "bron": "JSON-LD"})
                print(f"✅ €{p:.0f}")
            else:
                soup = BeautifulSoup(html, "lxml")
                for t in soup(["script","style"]): t.decompose()
                text = soup.get_text()[:3000]
                val, s = hermes_extract_price(text, item)
                if val:
                    results.append({"winkel": store['title'][:50], "prijs": s, "price_val": val, "url": store['url'], "bron": "Hermes"})
                    print(f"✅ {s}")
                else:
                    print("❌ geen prijs")
        else:
            print("⏳")
    
    if not results:
        print("\n   ❌ Geen prijzen gevonden.")
        return
    
    results.sort(key=lambda x: x.get("price_val", 99999))
    
    print(f"\n📊 {len(results)} prijzen gevonden:")
    for i, r in enumerate(results, 1):
        print(f"  {i}. {r['prijs']:>8}  @ {r['winkel'][:40]}")
        print(f"     🔗 {r['url']}")
    
    # Eindrapport
    data = json.dumps(results, indent=2, ensure_ascii=False)
    report = ask(
        f"Product: {item}\n\nGevonden:\n{data}\n\n"
        "Eindrapport in NL:\n"
        "## 🏆 Beste deal\n## 📊 Tabel\n## 💡 Advies\nWees precies met bedragen.",
        "Je geeft een helder advies.", 0.3)
    print(f"\n{'='*60}")
    print(report)
    print('='*60)

if __name__ == "__main__":
    item = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else input("Zoek: ")
    search_item(item)
