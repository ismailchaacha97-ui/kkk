#!/usr/bin/env python3
"""
Extend data/fomc_dates.csv and data/macro_dates.csv by scraping primary sources.
Stdlib only. Best-effort: always eyeball the diff before trusting it.

Sources:
  FOMC : https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm
         (statement press-release URLs embed announcement date: monetaryYYYYMMDDa.htm)
  CPI  : https://www.bls.gov/schedule/news_release/cpi.htm
  NFP  : https://www.bls.gov/ces/publications/news-release-schedule.htm

Run: python fetch_calendars.py   (writes data/*.csv, keeps backup *.bak)
"""
import csv
import os
import re
import urllib.request

UA = {"User-Agent": "Mozilla/5.0 (research calendar fetch; educational use)"}
BASE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(BASE, "data")

FED_URL = "https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm"
CPI_URL = "https://www.bls.gov/schedule/news_release/cpi.htm"
NFP_URL = "https://www.bls.gov/ces/publications/news-release-schedule.htm"

MONTHS = {m: i + 1 for i, m in enumerate(
    ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"])}


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


# ---------------- FOMC ----------------
def fetch_fomc():
    html = get(FED_URL)
    # Statement links: monetary20260318a.htm / monetary20260318a1.htm
    hits = re.findall(r"monetary(\d{8})a1?\.htm", html)
    dates = sorted({f"{h[:4]}-{h[4:6]}-{h[6:]}" for h in hits})
    return dates  # announcement date = statement date (2nd day of meeting)


# ---------------- BLS ----------------
def parse_mdy(text, default_year=None):
    """Parse 'Mar. 11, 2026' / 'March 6' / 'Friday, March 6' -> date str or None."""
    t = text.strip()
    m = re.search(r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2})(?:,?\s+(\d{4}))?",
                  t, re.I)
    if not m:
        return None
    mon = MONTHS[m.group(1).lower()[:3]]
    day = int(m.group(2))
    year = int(m.group(3)) if m.group(3) else default_year
    if not year:
        return None
    return f"{year:04d}-{mon:02d}-{day:02d}"


def fetch_cpi():
    html = get(CPI_URL)
    # rows look like: <td>February 2026</td>... <td>Mar 11, 2026</td>
    cells = re.findall(r"<td[^>]*>(.*?)</td>", html, re.S)
    out = []
    for c in cells:
        c = re.sub(r"<[^>]+>", "", c).strip()
        d = parse_mdy(c)
        if d:
            out.append(d)
    # page mixes reference months and release dates; release dates always carry a year
    return sorted(set(out))


def fetch_nfp():
    html = get(NFP_URL)
    text = re.sub(r"<[^>]+>", " ", html)
    # find current-schedule year context
    years = re.findall(r"20\d{2}", text)
    year = int(sorted(set(years))[-1]) if years else None
    # Employment Situation column entries like 'Friday, March 6' near 'January 9, 2026'
    out = []
    for m in re.finditer(
            r"(?:Monday|Tuesday|Wednesday|Thursday|Friday)\s*,?\s*"
            r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2})(?:,?\s+(20\d{2}))?",
            text, re.I):
        mon = MONTHS[m.group(1).lower()[:3]]
        day = int(m.group(2))
        y = int(m.group(3)) if m.group(3) else year
        if y:
            out.append(f"{y:04d}-{mon:02d}-{day:02d}")
    return sorted(set(out))


# ---------------- merge/write ----------------
def read_existing(path):
    rows = {}
    if os.path.exists(path):
        with open(path) as f:
            for r in csv.DictReader(f):
                rows[r["date"]] = r
    return rows


def write_csv(path, rows):
    if os.path.exists(path):
        os.replace(path, path + ".bak")
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)


def main():
    os.makedirs(DATA, exist_ok=True)
    try:
        fomc = fetch_fomc()
        print(f"FOMC scraped: {len(fomc)} dates ({fomc[0]}..{fomc[-1]})" if fomc else "FOMC: none found")
    except Exception as e:
        print(f"FOMC fetch failed: {e}")
        fomc = []
    try:
        cpi = fetch_cpi()
        print(f"CPI scraped: {len(cpi)} dates" if cpi else "CPI: none found")
    except Exception as e:
        print(f"CPI fetch failed: {e}")
        cpi = []
    try:
        nfp = fetch_nfp()
        print(f"NFP scraped: {len(nfp)} dates" if nfp else "NFP: none found")
    except Exception as e:
        print(f"NFP fetch failed: {e}")
        nfp = []

    if fomc:
        ex = read_existing(os.path.join(DATA, "fomc_dates.csv"))
        for d in fomc:
            ex.setdefault(d, {"date": d, "sep": "", "notes": "scraped federalreserve.gov — VERIFY"})
        rows = [ex[d] for d in sorted(ex)]
        write_csv(os.path.join(DATA, "fomc_dates.csv"), rows)
        print(f"fomc_dates.csv: {len(rows)} rows (backup .bak kept)")

    if cpi or nfp:
        ex = read_existing(os.path.join(DATA, "macro_dates.csv"))
        for d in cpi:
            ex.setdefault(d, {"date": d, "event": "CPI", "release_time_et": "08:30",
                              "notes": "scraped bls.gov — VERIFY"})
        for d in nfp:
            if d in ex and ex[d].get("event") == "CPI":
                ex[d]["event"] = "CPI+NFP"
            else:
                ex.setdefault(d, {"date": d, "event": "NFP", "release_time_et": "08:30",
                                  "notes": "scraped bls.gov — VERIFY"})
        rows = [ex[d] for d in sorted(ex)]
        write_csv(os.path.join(DATA, "macro_dates.csv"), rows)
        print(f"macro_dates.csv: {len(rows)} rows (backup .bak kept)")

    print("Done. Eyeball the diffs — scraped rows are marked VERIFY.")


if __name__ == "__main__":
    main()
