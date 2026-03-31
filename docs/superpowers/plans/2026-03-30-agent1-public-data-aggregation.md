# Agent 1 — Public Data Aggregation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A single Python script that daily scrapes business + property data, packages it into geo/niche CSVs, auto-publishes to Gumroad, and reports to CoastalClaw.

**Architecture:** Single monolith file (`dirty_data_agent.py`) with clearly named stage functions. SQLite for deduplication and run state. External services (Google Places, Playwright, Gumroad, Ollama) are called inline per stage. Stage failures are isolated — one bad source never stops the run.

**Tech Stack:** Python 3.11+, requests, playwright, sqlite3, pandas, ollama, python-dotenv, Windows Task Scheduler

---

## Chunk 1: Project Setup & Database

### Task 1: Create project skeleton and requirements

**Files:**
- Create: `agent1/requirements.txt`
- Create: `agent1/.env.example`
- Create: `agent1/dirty_data_agent.py` (skeleton only)

- [ ] **Step 1: Create requirements.txt**

```
requests==2.31.0
playwright==1.44.0
pandas==2.2.2
python-dotenv==1.0.1
ollama==0.2.1
reportlab==4.1.0
```

- [ ] **Step 2: Create .env.example**

```env
# API Keys
GOOGLE_PLACES_API_KEY=your_key_here
GUMROAD_ACCESS_TOKEN=your_token_here

# CoastalClaw
COASTALCLAW_URL=http://localhost:4747

# Alerting
TELEGRAM_BOT_TOKEN=your_token_here
TELEGRAM_CHAT_ID=your_chat_id_here

# Ollama
OLLAMA_URL=http://localhost:11434

# Targets — comma-separated, add more without code changes
TARGET_GEOS=Dallas TX,Houston TX,Austin TX,Phoenix AZ
TARGET_NICHES=HVAC,plumbing,roofing,landscaping,electrical
RE_COUNTIES=Dallas County TX,Harris County TX,Maricopa County AZ
```

- [ ] **Step 3: Create dirty_data_agent.py skeleton**

```python
"""
Agent 1 — Public Data Aggregation & Resale
Runs daily via Windows Task Scheduler at 3AM.
Pipeline: SCRAPE → CLEAN → PACKAGE → PUBLISH → LOG
"""
import os, sqlite3, json, time, logging
from datetime import date, datetime
from pathlib import Path
import requests
import pandas as pd
from dotenv import load_dotenv

load_dotenv()

BASE_DIR = Path(__file__).parent
DB_PATH  = BASE_DIR / "agent1.db"
OUT_DIR  = BASE_DIR / "output"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(BASE_DIR / "agent1.log"),
        logging.StreamHandler(),
    ]
)
log = logging.getLogger(__name__)

# ── Config ──────────────────────────────────────────────────────────────────

def load_config():
    return {
        "places_key":      os.environ["GOOGLE_PLACES_API_KEY"],
        "gumroad_token":   os.environ["GUMROAD_ACCESS_TOKEN"],
        "coastalclaw_url": os.getenv("COASTALCLAW_URL", "http://localhost:4747"),
        "telegram_token":  os.getenv("TELEGRAM_BOT_TOKEN", ""),
        "telegram_chat":   os.getenv("TELEGRAM_CHAT_ID", ""),
        "ollama_url":      os.getenv("OLLAMA_URL", "http://localhost:11434"),
        "geos":   [g.strip() for g in os.environ["TARGET_GEOS"].split(",")],
        "niches": [n.strip() for n in os.environ["TARGET_NICHES"].split(",")],
        "re_counties": [c.strip() for c in os.environ["RE_COUNTIES"].split(",")],
    }

# ── Stages (stubs — filled in subsequent tasks) ─────────────────────────────

def stage_scrape(cfg, conn): pass
def stage_clean(cfg, conn):  pass
def stage_package(cfg):      pass
def stage_publish(cfg, conn): pass
def stage_log(cfg, conn, run_id, results): pass

# ── Main ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    cfg  = load_config()
    conn = sqlite3.connect(DB_PATH)
    try:
        stage_scrape(cfg, conn)
        stage_clean(cfg, conn)
        stage_package(cfg)
        stage_publish(cfg, conn)
        stage_log(cfg, conn, run_id=None, results={})
    finally:
        conn.close()
```

- [ ] **Step 4: Install dependencies**

```bash
cd agent1
pip install -r requirements.txt
playwright install chromium
```

- [ ] **Step 5: Commit**

```bash
git add agent1/requirements.txt agent1/.env.example agent1/dirty_data_agent.py
git commit -m "feat: agent1 project skeleton and dependencies"
```

---

### Task 2: SQLite initialization

**Files:**
- Modify: `agent1/dirty_data_agent.py` — add `init_db()`
- Create: `agent1/tests/test_db.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_db.py
import sqlite3, pytest, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from dirty_data_agent import init_db

def test_init_db_creates_tables():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    tables = {r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'"
    ).fetchall()}
    assert tables == {"seen_ids", "listings", "runs"}
    conn.close()

def test_init_db_idempotent():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    init_db(conn)  # should not raise
    conn.close()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd agent1
python -m pytest tests/test_db.py -v
```
Expected: FAIL — `ImportError: cannot import name 'init_db'`

- [ ] **Step 3: Implement init_db()**

Add to `dirty_data_agent.py` after imports:

```python
def init_db(conn):
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS seen_ids (
            source_id  TEXT PRIMARY KEY,
            source     TEXT NOT NULL,
            first_seen DATE NOT NULL,
            last_seen  DATE NOT NULL
        );
        CREATE TABLE IF NOT EXISTS listings (
            gumroad_id    TEXT PRIMARY KEY,
            product_name  TEXT NOT NULL,
            geo           TEXT NOT NULL,
            niche         TEXT NOT NULL,
            row_count     INTEGER NOT NULL,
            last_updated  DATE NOT NULL,
            status        TEXT DEFAULT 'live'
        );
        CREATE TABLE IF NOT EXISTS runs (
            run_id            INTEGER PRIMARY KEY AUTOINCREMENT,
            started_at        DATETIME NOT NULL,
            finished_at       DATETIME,
            new_rows          INTEGER DEFAULT 0,
            products_updated  INTEGER DEFAULT 0,
            status            TEXT DEFAULT 'running',
            error_msg         TEXT
        );
    """)
    conn.commit()
```

Update `__main__` to call `init_db(conn)` before stages.

- [ ] **Step 4: Run test to verify it passes**

```bash
python -m pytest tests/test_db.py -v
```
Expected: 2 PASSED

- [ ] **Step 5: Commit**

```bash
git add agent1/dirty_data_agent.py agent1/tests/test_db.py
git commit -m "feat: agent1 SQLite schema init"
```

---

## Chunk 2: Stage 1 — Scraper

### Task 3: Google Places scraper

**Files:**
- Modify: `agent1/dirty_data_agent.py` — implement `scrape_places()`
- Create: `agent1/tests/test_scraper.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_scraper.py
import sqlite3, pytest, sys
from pathlib import Path
from unittest.mock import patch, MagicMock
sys.path.insert(0, str(Path(__file__).parent.parent))
from dirty_data_agent import scrape_places, init_db

MOCK_PLACES_RESPONSE = {
    "results": [
        {
            "place_id": "abc123",
            "name": "Dallas HVAC Co",
            "formatted_address": "123 Main St, Dallas, TX",
            "formatted_phone_number": "214-555-0100",
            "website": "https://dallashvac.com",
            "rating": 4.2,
            "user_ratings_total": 87,
            "types": ["plumber"],
        }
    ],
    "status": "OK",
    "next_page_token": None,
}

def test_scrape_places_returns_rows():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    with patch("dirty_data_agent.requests.get") as mock_get:
        mock_resp = MagicMock()
        mock_resp.json.return_value = MOCK_PLACES_RESPONSE
        mock_resp.raise_for_status = MagicMock()
        mock_get.return_value = mock_resp
        rows = scrape_places("HVAC", "Dallas TX", "fake_key")
    assert len(rows) == 1
    assert rows[0]["place_id"] == "abc123"
    assert rows[0]["name"] == "Dallas HVAC Co"
    conn.close()

def test_scrape_places_rate_limit_retries():
    with patch("dirty_data_agent.requests.get") as mock_get, \
         patch("dirty_data_agent.time.sleep"):
        mock_resp_429 = MagicMock()
        mock_resp_429.status_code = 429
        mock_resp_429.raise_for_status.side_effect = Exception("429")
        mock_resp_ok = MagicMock()
        mock_resp_ok.json.return_value = MOCK_PLACES_RESPONSE
        mock_resp_ok.raise_for_status = MagicMock()
        mock_get.side_effect = [Exception("429"), mock_resp_ok]
        rows = scrape_places("HVAC", "Dallas TX", "fake_key")
    assert len(rows) == 1
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python -m pytest tests/test_scraper.py -v
```
Expected: FAIL — `ImportError: cannot import name 'scrape_places'`

- [ ] **Step 3: Implement scrape_places()**

```python
PLACES_URL = "https://maps.googleapis.com/maps/api/place/textsearch/json"

def scrape_places(niche, geo, api_key, max_results=300):
    """Fetch businesses from Google Places Text Search. Returns list of row dicts."""
    rows = []
    params = {
        "query": f"{niche} in {geo}",
        "key": api_key,
    }
    backoff = 2
    while len(rows) < max_results:
        try:
            resp = requests.get(PLACES_URL, params=params, timeout=10)
            resp.raise_for_status()
            data = resp.json()
        except Exception as e:
            log.warning(f"Places API error ({niche}/{geo}): {e} — retrying in {backoff}s")
            time.sleep(backoff)
            backoff = min(backoff * 2, 8)
            break  # skip source on persistent error

        for r in data.get("results", []):
            rows.append({
                "place_id":     r.get("place_id"),
                "name":         r.get("name"),
                "address":      r.get("formatted_address"),
                "phone":        r.get("formatted_phone_number", ""),
                "website":      r.get("website", ""),
                "rating":       r.get("rating", 0),
                "review_count": r.get("user_ratings_total", 0),
                "category":     r.get("types", [""])[0],
                "geo":          geo,
                "niche":        niche,
                "source":       "places",
            })
        token = data.get("next_page_token")
        if not token:
            break
        time.sleep(2)  # Places API requires delay before next_page_token is valid
        params = {"pagetoken": token, "key": api_key}

    log.info(f"Places scraped {len(rows)} rows for {niche}/{geo}")
    return rows
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python -m pytest tests/test_scraper.py -v
```
Expected: 2 PASSED

- [ ] **Step 5: Commit**

```bash
git add agent1/dirty_data_agent.py agent1/tests/test_scraper.py
git commit -m "feat: agent1 Google Places scraper with retry"
```

---

### Task 4: County assessor + Zillow scrapers (Playwright)

**Files:**
- Modify: `agent1/dirty_data_agent.py` — implement `scrape_assessor()`, `scrape_zillow()`

Note: Playwright scrapers depend on live county websites that change over time. Write integration-style tests that mock `playwright.sync_api` rather than hitting real sites. The actual CSS selectors must be calibrated per county by running against the real site once during setup.

- [ ] **Step 1: Write tests for assessor scraper**

Add to `tests/test_scraper.py`:

```python
def test_scrape_assessor_skips_on_block():
    """If assessor returns 403/429, function returns empty list without crashing."""
    from unittest.mock import patch, MagicMock
    with patch("dirty_data_agent.sync_playwright") as mock_pw:
        mock_pw.return_value.__enter__.return_value.chromium.launch.side_effect = Exception("blocked")
        from dirty_data_agent import scrape_assessor
        rows = scrape_assessor("Dallas County TX")
    assert rows == []
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python -m pytest tests/test_scraper.py::test_scrape_assessor_skips_on_block -v
```
Expected: FAIL

- [ ] **Step 3: Implement scrape_assessor() and scrape_zillow()**

```python
from playwright.sync_api import sync_playwright

# County assessor URL map — extend as needed
ASSESSOR_URLS = {
    "Dallas County TX":  "https://www.dallascad.org/SearchAddr.aspx",
    "Harris County TX":  "https://hcad.org/property-search/",
    "Maricopa County AZ": "https://mcassessor.maricopa.gov/",
}

def scrape_assessor(county):
    """Scrape county assessor records. Returns list of row dicts."""
    url = ASSESSOR_URLS.get(county)
    if not url:
        log.warning(f"No assessor URL configured for {county}")
        return []
    rows = []
    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch(headless=True)
            page = browser.new_page()
            page.goto(url, timeout=30000)
            # NOTE: Selectors below are placeholders.
            # Run `playwright codegen <url>` to get real selectors for each county.
            results = page.query_selector_all(".property-row, tr.result-row")
            for el in results:
                rows.append({
                    "parcel_id":        _safe_text(el, ".parcel-id"),
                    "owner_name":       _safe_text(el, ".owner"),
                    "property_address": _safe_text(el, ".prop-addr"),
                    "mailing_address":  _safe_text(el, ".mail-addr"),
                    "assessed_value":   _safe_text(el, ".assessed"),
                    "last_sale_date":   _safe_text(el, ".sale-date"),
                    "last_sale_price":  _safe_text(el, ".sale-price"),
                    "lot_size":         _safe_text(el, ".lot-size"),
                    "year_built":       _safe_text(el, ".year-built"),
                    "county":           county,
                    "source":           "assessor",
                })
                time.sleep(1 / 3)  # 1 req/3sec
            browser.close()
    except Exception as e:
        log.warning(f"Assessor scrape failed for {county}: {e}")
        return []
    log.info(f"Assessor scraped {len(rows)} rows for {county}")
    return rows

def scrape_zillow(county):
    """Scrape Zillow listing data for county. Returns list of row dicts."""
    rows = []
    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch(headless=True)
            context = browser.new_context(
                user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            )
            page = context.new_page()
            city_slug = county.replace(" County", "").replace(" ", "-").lower()
            page.goto(f"https://www.zillow.com/homes/{city_slug}/", timeout=30000)
            time.sleep(2)
            cards = page.query_selector_all("article[data-test='property-card']")
            for card in cards:
                rows.append({
                    "property_address": _safe_text(card, "address"),
                    "zestimate":        _safe_text(card, "[data-test='property-card-price']"),
                    "days_on_market":   _safe_text(card, ".StyledPropertyCardDataArea-anchor"),
                    "listing_status":   _safe_text(card, ".StyledPropertyCardBadge"),
                    "county":           county,
                    "source":           "zillow",
                })
                time.sleep(1 / 5)  # 1 req/5sec
            browser.close()
    except Exception as e:
        log.warning(f"Zillow scrape failed for {county}: {e}")
        return []
    log.info(f"Zillow scraped {len(rows)} rows for {county}")
    return rows

def _safe_text(el, selector):
    try:
        return el.query_selector(selector).inner_text().strip()
    except Exception:
        return ""
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python -m pytest tests/test_scraper.py -v
```
Expected: All PASSED

- [ ] **Step 5: Commit**

```bash
git add agent1/dirty_data_agent.py
git commit -m "feat: agent1 Playwright assessor + Zillow scrapers"
```

---

### Task 5: Wire stage_scrape()

**Files:**
- Modify: `agent1/dirty_data_agent.py` — implement `stage_scrape()`

- [ ] **Step 1: Implement stage_scrape()**

Replace the `stage_scrape` stub:

```python
def stage_scrape(cfg, conn):
    """Stage 1: Collect raw rows from all sources. Returns dict of raw row lists."""
    raw = {"local_biz": [], "real_estate": []}

    # Source A — Google Places (geo × niche)
    for geo in cfg["geos"]:
        for niche in cfg["niches"]:
            rows = scrape_places(niche, geo, cfg["places_key"])
            raw["local_biz"].extend(rows)

    # Source B — County assessor + Zillow (county)
    for county in cfg["re_counties"]:
        assessor_rows = scrape_assessor(county)
        zillow_rows   = scrape_zillow(county)
        raw["real_estate"].extend(assessor_rows)
        raw["real_estate"].extend(zillow_rows)

    log.info(f"Scrape complete — {len(raw['local_biz'])} biz rows, {len(raw['real_estate'])} RE rows")
    return raw
```

Update `__main__` to capture the return value: `raw = stage_scrape(cfg, conn)`

- [ ] **Step 2: Commit**

```bash
git add agent1/dirty_data_agent.py
git commit -m "feat: agent1 stage_scrape orchestration"
```

---

## Chunk 3: Stage 2 — Cleaner

### Task 6: Deduplication via seen_ids

**Files:**
- Modify: `agent1/dirty_data_agent.py` — implement `deduplicate()`
- Create: `agent1/tests/test_cleaner.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_cleaner.py
import sqlite3, pytest, sys
from pathlib import Path
from datetime import date
sys.path.insert(0, str(Path(__file__).parent.parent))
from dirty_data_agent import init_db, deduplicate

ROWS = [
    {"place_id": "abc", "source": "places", "name": "Biz A", "geo": "Dallas TX", "niche": "HVAC"},
    {"place_id": "def", "source": "places", "name": "Biz B", "geo": "Dallas TX", "niche": "HVAC"},
    {"place_id": "abc", "source": "places", "name": "Biz A", "geo": "Dallas TX", "niche": "HVAC"},  # dupe
]

def test_deduplicate_removes_seen():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    new, count = deduplicate(conn, ROWS, id_field="place_id")
    assert count == 2        # 2 new rows
    assert len(new) == 2

def test_deduplicate_updates_last_seen():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    deduplicate(conn, ROWS[:1], id_field="place_id")  # insert abc
    _, count = deduplicate(conn, ROWS[:1], id_field="place_id")  # re-see abc
    assert count == 0        # 0 new rows
    row = conn.execute("SELECT last_seen FROM seen_ids WHERE source_id='abc'").fetchone()
    assert row[0] == str(date.today())
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python -m pytest tests/test_cleaner.py -v
```
Expected: FAIL

- [ ] **Step 3: Implement deduplicate()**

```python
def deduplicate(conn, rows, id_field="place_id"):
    """
    Filter rows to only new source_ids. Update last_seen for re-seen ids.
    Returns (new_rows, new_count).
    """
    today = str(date.today())
    new_rows = []
    for row in rows:
        sid = row.get(id_field) or row.get("parcel_id")
        if not sid:
            continue
        source = row.get("source", "unknown")
        existing = conn.execute(
            "SELECT source_id FROM seen_ids WHERE source_id=?", (sid,)
        ).fetchone()
        if existing:
            conn.execute(
                "UPDATE seen_ids SET last_seen=? WHERE source_id=?", (today, sid)
            )
        else:
            conn.execute(
                "INSERT INTO seen_ids (source_id, source, first_seen, last_seen) VALUES (?,?,?,?)",
                (sid, source, today, today)
            )
            new_rows.append(row)
    conn.commit()
    return new_rows, len(new_rows)
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python -m pytest tests/test_cleaner.py -v
```
Expected: 2 PASSED

- [ ] **Step 5: Commit**

```bash
git add agent1/dirty_data_agent.py agent1/tests/test_cleaner.py
git commit -m "feat: agent1 deduplication via seen_ids"
```

---

### Task 7: Ollama enrichment pass

**Files:**
- Modify: `agent1/dirty_data_agent.py` — implement `enrich_with_ollama()`

- [ ] **Step 1: Write the failing test**

Add to `tests/test_cleaner.py`:

```python
def test_enrich_fills_missing_phone():
    from unittest.mock import patch
    rows = [{"name": "Test Biz", "address": "123 Main St Dallas TX", "phone": "", "website": ""}]
    mock_response = {"phone": "214-555-9999", "website": ""}
    with patch("dirty_data_agent.requests.post") as mock_post:
        mock_resp = MagicMock()
        mock_resp.json.return_value = {
            "message": {"content": json.dumps(mock_response)}
        }
        mock_post.return_value = mock_resp
        from dirty_data_agent import enrich_with_ollama
        enriched = enrich_with_ollama(rows, ollama_url="http://localhost:11434")
    assert enriched[0]["phone"] == "214-555-9999"

def test_enrich_skips_when_ollama_offline():
    from unittest.mock import patch
    rows = [{"name": "Test Biz", "phone": ""}]
    with patch("dirty_data_agent.requests.post", side_effect=ConnectionError("offline")):
        from dirty_data_agent import enrich_with_ollama
        result = enrich_with_ollama(rows, ollama_url="http://localhost:11434")
    assert result == rows  # unchanged
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python -m pytest tests/test_cleaner.py::test_enrich_fills_missing_phone tests/test_cleaner.py::test_enrich_skips_when_ollama_offline -v
```
Expected: FAIL

- [ ] **Step 3: Implement enrich_with_ollama()**

```python
ENRICH_PROMPT = """You are a business data enrichment assistant.
Given a business record with some missing fields, infer the most likely values.
Only fill fields that are empty. Do not change non-empty fields.

Record:
{record_json}

Return ONLY valid JSON with the same keys, filling in empty values where possible."""

def enrich_with_ollama(rows, ollama_url="http://localhost:11434"):
    """Fill missing fields using Ollama llama3.2:3b. Skips gracefully if offline."""
    enriched = []
    incomplete = [r for r in rows if not r.get("phone") or not r.get("website")]
    complete   = [r for r in rows if r.get("phone") and r.get("website")]

    if not incomplete:
        return rows

    for row in incomplete:
        try:
            payload = {
                "model": "llama3.2:3b",
                "messages": [{"role": "user", "content": ENRICH_PROMPT.format(
                    record_json=json.dumps(row, indent=2)
                )}],
                "stream": False,
            }
            resp = requests.post(
                f"{ollama_url}/api/chat", json=payload, timeout=10
            )
            data = json.loads(resp.json()["message"]["content"])
            row.update({k: v for k, v in data.items() if not row.get(k) and v})
        except Exception as e:
            log.debug(f"Ollama enrichment skipped for {row.get('name')}: {e}")
        enriched.append(row)

    return complete + enriched
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python -m pytest tests/test_cleaner.py -v
```
Expected: All PASSED

- [ ] **Step 5: Implement stage_clean() wrapper**

```python
def stage_clean(cfg, conn, raw):
    """Stage 2: Deduplicate and enrich raw rows."""
    new_biz, biz_count = deduplicate(conn, raw["local_biz"], id_field="place_id")
    new_re,  re_count  = deduplicate(conn, raw["real_estate"], id_field="parcel_id")

    new_biz = enrich_with_ollama(new_biz, cfg["ollama_url"])

    log.info(f"Clean complete — {biz_count} new biz, {re_count} new RE rows")
    return {"local_biz": new_biz, "real_estate": new_re,
            "new_rows": biz_count + re_count}
```

- [ ] **Step 6: Commit**

```bash
git add agent1/dirty_data_agent.py agent1/tests/test_cleaner.py
git commit -m "feat: agent1 Ollama enrichment pass"
```

---

## Chunk 4: Stage 3 — Packager

### Task 8: CSV packaging and pricing logic

**Files:**
- Modify: `agent1/dirty_data_agent.py` — implement `calc_price()`, `make_filename()`, `package_csvs()`
- Create: `agent1/tests/test_packager.py`

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_packager.py
import sys, json
from pathlib import Path
import pytest
sys.path.insert(0, str(Path(__file__).parent.parent))
from dirty_data_agent import calc_price, make_filename, package_csvs

def test_calc_price_tiers():
    assert calc_price(50)  == 29_00   # in cents
    assert calc_price(199) == 29_00
    assert calc_price(200) == 39_00
    assert calc_price(499) == 39_00
    assert calc_price(500) == 49_00
    assert calc_price(999) == 49_00

def test_make_filename():
    assert make_filename("Dallas TX", "HVAC", "2026-03-30") == \
        "dallas_tx_hvac_2026-03-30.csv"
    assert make_filename("Houston TX", "plumbing", "2026-03-30") == \
        "houston_tx_plumbing_2026-03-30.csv"

def test_package_csvs_creates_files(tmp_path):
    rows = [
        {"name": "A", "address": "1 Main", "phone": "555", "geo": "Dallas TX", "niche": "HVAC"},
        {"name": "B", "address": "2 Main", "phone": "556", "geo": "Dallas TX", "niche": "HVAC"},
        {"name": "C", "address": "3 Main", "phone": "557", "geo": "Dallas TX", "niche": "plumbing"},
    ]
    out_dir = tmp_path / "output" / "local_biz"
    out_dir.mkdir(parents=True)
    manifest = package_csvs(rows, out_dir, "2026-03-30")
    assert len(manifest) == 2  # 2 geo+niche combos
    for entry in manifest:
        assert Path(entry["path"]).exists()
        assert entry["row_count"] > 0
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
python -m pytest tests/test_packager.py -v
```
Expected: FAIL

- [ ] **Step 3: Implement packaging functions**

```python
import pandas as pd
import re

def calc_price(row_count):
    """Returns price in cents."""
    if row_count < 200:
        return 29_00
    elif row_count < 500:
        return 39_00
    return 49_00

def make_filename(geo, niche, run_date):
    slug = re.sub(r"[^a-z0-9]+", "_", f"{geo} {niche}".lower()).strip("_")
    return f"{slug}_{run_date}.csv"

def package_csvs(rows, out_dir, run_date):
    """
    Slice rows by geo+niche, write CSVs, return manifest list.
    Each manifest entry: {geo, niche, path, row_count, price_cents, filename}
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    df = pd.DataFrame(rows)
    manifest = []

    for (geo, niche), group in df.groupby(["geo", "niche"]):
        filename = make_filename(geo, niche, run_date)
        csv_path = out_dir / filename
        group.drop(columns=["geo", "niche", "source"], errors="ignore").to_csv(
            csv_path, index=False
        )
        manifest.append({
            "geo":         geo,
            "niche":       niche,
            "filename":    filename,
            "path":        str(csv_path),
            "row_count":   len(group),
            "price_cents": calc_price(len(group)),
        })
        log.info(f"Packaged {geo}/{niche} → {len(group)} rows")

    return manifest
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
python -m pytest tests/test_packager.py -v
```
Expected: 3 PASSED

- [ ] **Step 5: Implement stage_package()**

```python
def stage_package(cfg, clean_data):
    """Stage 3: Slice into CSVs and write manifest.json."""
    run_date = str(date.today())
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    biz_manifest = package_csvs(
        clean_data["local_biz"],
        OUT_DIR / "local_biz",
        run_date
    )
    re_manifest = package_csvs(
        clean_data["real_estate"],
        OUT_DIR / "real_estate",
        run_date
    )

    manifest = {"date": run_date, "files": biz_manifest + re_manifest}
    manifest_path = OUT_DIR / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2))
    log.info(f"Package complete — {len(manifest['files'])} products")
    return manifest
```

- [ ] **Step 6: Commit**

```bash
git add agent1/dirty_data_agent.py agent1/tests/test_packager.py
git commit -m "feat: agent1 CSV packager with pricing tiers"
```

---

## Chunk 5: Stage 4 — Publisher

### Task 9: Gumroad product diff and publish

**Files:**
- Modify: `agent1/dirty_data_agent.py` — implement `diff_manifest()`, `publish_product()`
- Create: `agent1/tests/test_publisher.py`

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_publisher.py
import sqlite3, pytest, sys, json
from pathlib import Path
from unittest.mock import patch, MagicMock
sys.path.insert(0, str(Path(__file__).parent.parent))
from dirty_data_agent import init_db, diff_manifest, publish_product

def test_diff_manifest_new_product():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    manifest_files = [
        {"geo": "Dallas TX", "niche": "HVAC", "row_count": 200,
         "price_cents": 39_00, "path": "/tmp/test.csv", "filename": "test.csv"}
    ]
    new, updated = diff_manifest(conn, manifest_files)
    assert len(new) == 1
    assert len(updated) == 0

def test_diff_manifest_updated_product():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    conn.execute(
        "INSERT INTO listings VALUES (?,?,?,?,?,?,?)",
        ("gum_123", "Dallas HVAC", "Dallas TX", "HVAC", 150, "2026-03-29", "live")
    )
    conn.commit()
    manifest_files = [
        {"geo": "Dallas TX", "niche": "HVAC", "row_count": 200,
         "price_cents": 39_00, "path": "/tmp/test.csv", "filename": "test.csv"}
    ]
    new, updated = diff_manifest(conn, manifest_files)
    assert len(new) == 0
    assert len(updated) == 1

def test_publish_product_posts_to_gumroad():
    with patch("dirty_data_agent.requests.post") as mock_post, \
         patch("builtins.open", MagicMock()):
        mock_resp = MagicMock()
        mock_resp.json.return_value = {"success": True, "product": {"id": "gum_new"}}
        mock_resp.raise_for_status = MagicMock()
        mock_post.return_value = mock_resp
        product_id = publish_product(
            {"geo": "Dallas TX", "niche": "HVAC", "row_count": 200,
             "price_cents": 39_00, "path": "/tmp/test.csv"},
            token="fake_token", existing_id=None
        )
    assert product_id == "gum_new"
    mock_post.assert_called_once()
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
python -m pytest tests/test_publisher.py -v
```
Expected: FAIL

- [ ] **Step 3: Implement diff and publish**

```python
GUMROAD_API = "https://api.gumroad.com/v2/products"

def diff_manifest(conn, manifest_files):
    """Compare manifest to listings table. Returns (new_files, updated_files)."""
    new, updated = [], []
    for f in manifest_files:
        existing = conn.execute(
            "SELECT gumroad_id, row_count FROM listings WHERE geo=? AND niche=?",
            (f["geo"], f["niche"])
        ).fetchone()
        if not existing:
            new.append(f)
        elif existing[1] != f["row_count"]:
            updated.append({**f, "gumroad_id": existing[0]})
    return new, updated

def _listing_title(geo, niche, row_count):
    today = date.today().strftime("%b %d")
    return f"{geo} {niche} Contacts — {row_count} rows (Updated {today})"

def _listing_description(geo, niche, row_count):
    return (
        f"Fresh {niche} business contacts in {geo}.\n"
        f"{row_count} verified records with name, address, phone, website, rating.\n"
        f"Updated {date.today()}. CSV format, ready to import."
    )

def publish_product(entry, token, existing_id=None, retry=3):
    """Create or update a Gumroad product. Returns gumroad_id on success."""
    title = _listing_title(entry["geo"], entry["niche"], entry["row_count"])
    price = entry["price_cents"]

    for attempt in range(retry):
        try:
            if existing_id:
                url = f"{GUMROAD_API}/{existing_id}"
                method = requests.put
            else:
                url = GUMROAD_API
                method = requests.post

            with open(entry["path"], "rb") as f:
                resp = method(
                    url,
                    headers={"Authorization": f"Bearer {token}"},
                    data={
                        "name": title,
                        "price": price,
                        "description": _listing_description(entry["geo"], entry["niche"], entry["row_count"]),
                        "published": True,
                    },
                    files={"file": (entry["filename"] if "filename" in entry else Path(entry["path"]).name, f)},
                    timeout=30,
                )
            resp.raise_for_status()
            data = resp.json()
            if data.get("success"):
                return data["product"]["id"]
            raise Exception(f"Gumroad error: {data}")
        except Exception as e:
            log.warning(f"Gumroad publish attempt {attempt+1} failed: {e}")
            if attempt < retry - 1:
                time.sleep(5)

    log.error(f"Gumroad publish failed after {retry} attempts for {entry['geo']}/{entry['niche']}")
    return None

def stage_publish(cfg, conn, manifest):
    """Stage 4: Diff manifest vs DB, create/update Gumroad products."""
    new_files, updated_files = diff_manifest(conn, manifest["files"])
    products_updated = 0
    today = str(date.today())

    for entry in new_files:
        gumroad_id = publish_product(entry, cfg["gumroad_token"])
        if gumroad_id:
            conn.execute(
                "INSERT OR REPLACE INTO listings VALUES (?,?,?,?,?,?,?)",
                (gumroad_id, _listing_title(entry["geo"], entry["niche"], entry["row_count"]),
                 entry["geo"], entry["niche"], entry["row_count"], today, "live")
            )
            products_updated += 1
        else:
            conn.execute(
                "INSERT OR REPLACE INTO listings VALUES (?,?,?,?,?,?,?)",
                (f"pending_{entry['geo']}_{entry['niche']}",
                 _listing_title(entry["geo"], entry["niche"], entry["row_count"]),
                 entry["geo"], entry["niche"], entry["row_count"], today, "pending_upload")
            )

    for entry in updated_files:
        gumroad_id = publish_product(entry, cfg["gumroad_token"], existing_id=entry["gumroad_id"])
        if gumroad_id:
            conn.execute(
                "UPDATE listings SET row_count=?, last_updated=?, status='live' WHERE gumroad_id=?",
                (entry["row_count"], today, entry["gumroad_id"])
            )
            products_updated += 1
        else:
            conn.execute(
                "UPDATE listings SET status='pending_upload' WHERE gumroad_id=?",
                (entry["gumroad_id"],)
            )

    conn.commit()
    log.info(f"Publish complete — {products_updated} products updated")
    return products_updated
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
python -m pytest tests/test_publisher.py -v
```
Expected: 3 PASSED

- [ ] **Step 5: Commit**

```bash
git add agent1/dirty_data_agent.py agent1/tests/test_publisher.py
git commit -m "feat: agent1 Gumroad publish with manifest diff and retry"
```

---

## Chunk 6: Stage 5 — Logger, Alerts & Orchestrator

### Task 10: Run logging and CoastalClaw POST

**Files:**
- Modify: `agent1/dirty_data_agent.py` — implement `log_run()`, `alert_telegram()`, `post_coastalclaw()`
- Create: `agent1/tests/test_logger.py`

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_logger.py
import sqlite3, pytest, sys
from pathlib import Path
from unittest.mock import patch, MagicMock
sys.path.insert(0, str(Path(__file__).parent.parent))
from dirty_data_agent import init_db, start_run, finish_run, post_coastalclaw

def test_start_run_inserts_record():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    run_id = start_run(conn)
    row = conn.execute("SELECT status FROM runs WHERE run_id=?", (run_id,)).fetchone()
    assert row[0] == "running"

def test_finish_run_updates_record():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    run_id = start_run(conn)
    finish_run(conn, run_id, new_rows=10, products_updated=3, status="ok")
    row = conn.execute(
        "SELECT status, new_rows, products_updated FROM runs WHERE run_id=?", (run_id,)
    ).fetchone()
    assert row == ("ok", 10, 3)

def test_post_coastalclaw_silent_on_failure():
    with patch("dirty_data_agent.requests.post", side_effect=ConnectionError("offline")):
        post_coastalclaw("http://localhost:4747", {"agent": "agent1", "status": "ok"})
    # should not raise
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
python -m pytest tests/test_logger.py -v
```
Expected: FAIL

- [ ] **Step 3: Implement logging functions**

```python
def start_run(conn):
    cur = conn.execute(
        "INSERT INTO runs (started_at, status) VALUES (?, 'running')",
        (datetime.now().isoformat(),)
    )
    conn.commit()
    return cur.lastrowid

def finish_run(conn, run_id, new_rows=0, products_updated=0, status="ok", error_msg=None):
    conn.execute(
        """UPDATE runs SET finished_at=?, new_rows=?, products_updated=?,
           status=?, error_msg=? WHERE run_id=?""",
        (datetime.now().isoformat(), new_rows, products_updated, status, error_msg, run_id)
    )
    conn.commit()

def post_coastalclaw(url, payload):
    try:
        requests.post(f"{url}/api/agent-log", json=payload, timeout=5)
    except Exception as e:
        log.debug(f"CoastalClaw offline: {e}")

def alert_telegram(token, chat_id, message):
    if not token or not chat_id:
        return
    try:
        requests.post(
            f"https://api.telegram.org/bot{token}/sendMessage",
            json={"chat_id": chat_id, "text": message},
            timeout=5,
        )
    except Exception as e:
        log.debug(f"Telegram alert failed: {e}")
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
python -m pytest tests/test_logger.py -v
```
Expected: 3 PASSED

- [ ] **Step 5: Commit**

```bash
git add agent1/dirty_data_agent.py agent1/tests/test_logger.py
git commit -m "feat: agent1 run logging, CoastalClaw POST, Telegram alerts"
```

---

### Task 11: Wire the main orchestrator

**Files:**
- Modify: `agent1/dirty_data_agent.py` — finalize `__main__` block

- [ ] **Step 1: Implement full main orchestrator**

Replace the `__main__` block:

```python
if __name__ == "__main__":
    import traceback
    start_ts = time.time()
    cfg  = load_config()
    conn = sqlite3.connect(DB_PATH)
    init_db(conn)
    run_id = start_run(conn)
    new_rows = 0
    products_updated = 0

    try:
        raw          = stage_scrape(cfg, conn)
        clean_data   = stage_clean(cfg, conn, raw)
        manifest     = stage_package(cfg, clean_data)
        products_updated = stage_publish(cfg, conn, manifest)
        new_rows     = clean_data["new_rows"]

        finish_run(conn, run_id, new_rows=new_rows,
                   products_updated=products_updated, status="ok")

        if new_rows == 0:
            alert_telegram(cfg["telegram_token"], cfg["telegram_chat"],
                           "⚠️ Agent 1: 0 new rows this run")

    except Exception as e:
        err = traceback.format_exc()
        log.error(f"Run failed: {err}")
        finish_run(conn, run_id, status="error", error_msg=str(e))
        alert_telegram(cfg["telegram_token"], cfg["telegram_chat"],
                       f"🔴 Agent 1 run failed: {e}")
    finally:
        duration_ms = int((time.time() - start_ts) * 1000)
        post_coastalclaw(cfg["coastalclaw_url"], {
            "agent": "agent1",
            "status": "ok" if new_rows >= 0 else "error",
            "new_rows": new_rows,
            "products_updated": products_updated,
            "duration_ms": duration_ms,
        })
        conn.close()
```

- [ ] **Step 2: Run full test suite**

```bash
python -m pytest tests/ -v
```
Expected: All PASSED

- [ ] **Step 3: Commit**

```bash
git add agent1/dirty_data_agent.py
git commit -m "feat: agent1 main orchestrator with error isolation"
```

---

### Task 12: Windows Task Scheduler setup

**Files:**
- Create: `agent1/setup_scheduler.bat`

- [ ] **Step 1: Create scheduler script**

```bat
@echo off
REM Run this once as Administrator to register Agent 1 in Windows Task Scheduler
REM Usage: setup_scheduler.bat C:\path\to\python.exe C:\agent1

set PYTHON=%1
set AGENT_DIR=%2

schtasks /Create /TN "Agent1_DailyRun" ^
  /TR "%PYTHON% %AGENT_DIR%\dirty_data_agent.py" ^
  /SC DAILY /ST 03:00 ^
  /RU SYSTEM ^
  /RL HIGHEST ^
  /F

echo Task created: Agent1_DailyRun — runs daily at 3:00 AM
echo Verify in Task Scheduler: taskschd.msc
```

- [ ] **Step 2: Verify task registration**

```bash
# Run as Administrator in cmd.exe:
setup_scheduler.bat "C:\Users\John\AppData\Local\Programs\Python\Python314\python.exe" "C:\agent1"
schtasks /Query /TN "Agent1_DailyRun" /FO LIST
```
Expected: Task listed with status `Ready`, next run `3:00 AM tomorrow`

- [ ] **Step 3: Do a manual test run**

```bash
python C:\agent1\dirty_data_agent.py
```
Expected: No unhandled exceptions. `agent1.log` shows stages completing. `output/manifest.json` created.

- [ ] **Step 4: Commit**

```bash
git add agent1/setup_scheduler.bat
git commit -m "feat: agent1 Windows Task Scheduler setup script"
```

---

### Task 13: Final integration check and push

- [ ] **Step 1: Run full test suite one final time**

```bash
cd agent1
python -m pytest tests/ -v --tb=short
```
Expected: All PASSED, 0 failures

- [ ] **Step 2: Check log output is clean on dry run**

```bash
python dirty_data_agent.py 2>&1 | head -50
```
Expected: Stage transitions logged, no stack traces

- [ ] **Step 3: Push to GitHub**

```bash
git push origin main
```
