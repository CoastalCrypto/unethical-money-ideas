# Agent 1 — Public Data Aggregation & Resale
**Date:** 2026-03-30
**Status:** Approved
**Owner:** Coastal Crypto

---

## Overview

A single Python script (`dirty_data_agent.py`) that runs daily, scrapes publicly available business and property data, packages it into geo+niche CSV files, and auto-publishes them as paid Gumroad products. Reports run status back to CoastalClaw Core on `:4747`. Zero human involvement after initial setup.

**Revenue model:** $29–$49 per CSV download on Gumroad. 23 products at launch, scales by adding geos to `.env`.

---

## Architecture

Single-file pipeline, 5 sequential stages:

```
Windows Task Scheduler (3AM daily)
  ↓
1. SCRAPE   — fetch raw data from Google Places API + county public records
  ↓
2. CLEAN    — deduplicate via SQLite, validate fields, enrich missing values via Ollama
  ↓
3. PACKAGE  — slice by geo+niche into CSVs, write manifest.json
  ↓
4. PUBLISH  — diff manifest vs Gumroad listings table, create/update products via Gumroad API
  ↓
5. LOG      — write run summary to SQLite, POST to CoastalClaw :4747/api/agent-log, alert on error
```

---

## File Layout

```
agent1/
  dirty_data_agent.py     # single entry point — all 5 stages
  agent1.db               # SQLite — seen_ids, listings, runs
  output/
    local_biz/            # dallas_tx_hvac_contractors_2026-03-30.csv ...
    real_estate/          # dallas_county_tx_owners_2026-03-30.csv ...
    manifest.json         # file list + row counts + date
  .env                    # secrets + config (never committed)
  requirements.txt
```

---

## Data Sources

### Source A — Local Business Contacts

| | |
|---|---|
| **Primary** | Google Places Text Search API |
| **Endpoint** | `maps.googleapis.com/maps/api/place/textsearch` |
| **Query pattern** | `"HVAC contractors in Dallas TX"` |
| **Cost** | ~$5/run at 300 results · $17/1000 results |
| **Rate limit** | 3 req/sec |
| **Fields** | name, address, phone, website, rating, review_count, category, place_id |
| **Secondary** | State secretary of state public registry (Playwright scrape, free) |
| **Fields** | legal_name, owner_name, registered_address, formed_date, status |
| **Merge key** | phone number |

### Source B — Real Estate & Property Owners

| | |
|---|---|
| **Primary** | County assessor public records (Playwright scrape, free by law) |
| **Rate limit** | 1 req/3sec |
| **Fields** | owner_name, mailing_address, property_address, assessed_value, last_sale_date, last_sale_price, lot_size, year_built, parcel_id |
| **Secondary** | Zillow public listing data (Playwright + stealth scrape, free) |
| **Rate limit** | 1 req/5sec |
| **Fields** | zestimate, days_on_market, listing_status, price_history |
| **Merge key** | parcel_id / property_address |

### Ollama Enrichment Pass
After scraping, rows with missing fields are passed to local `llama3.2:3b` via a structured prompt. Runs entirely offline, ~200ms/row. If Ollama is unreachable, enrichment is skipped and rows are published as-is.

---

## Configuration (.env)

```env
# API Keys
GOOGLE_PLACES_API_KEY=...
GUMROAD_ACCESS_TOKEN=...

# CoastalClaw
COASTALCLAW_URL=http://localhost:4747

# Alerting
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...

# Ollama
OLLAMA_URL=http://localhost:11434

# Targets — add more without code changes
TARGET_GEOS=Dallas TX,Houston TX,Austin TX,Phoenix AZ
TARGET_NICHES=HVAC,plumbing,roofing,landscaping,electrical
RE_COUNTIES=Dallas County TX,Harris County TX,Maricopa County AZ
```

---

## SQLite Schema (agent1.db)

```sql
CREATE TABLE seen_ids (
  source_id TEXT PRIMARY KEY,
  source    TEXT NOT NULL,  -- 'places' | 'registry' | 'assessor' | 'zillow'
  first_seen DATE NOT NULL,
  last_seen  DATE NOT NULL
);

CREATE TABLE listings (
  gumroad_id    TEXT PRIMARY KEY,
  product_name  TEXT NOT NULL,
  geo           TEXT NOT NULL,
  niche         TEXT NOT NULL,
  row_count     INTEGER NOT NULL,
  last_updated  DATE NOT NULL,
  status        TEXT DEFAULT 'live'  -- 'live' | 'pending_upload'
);

CREATE TABLE runs (
  run_id           INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at       DATETIME NOT NULL,
  finished_at      DATETIME,
  new_rows         INTEGER DEFAULT 0,
  products_updated INTEGER DEFAULT 0,
  status           TEXT DEFAULT 'running',  -- 'running' | 'ok' | 'error'
  error_msg        TEXT
);
```

---

## Packaging & Pricing Logic

Each `(geo × niche)` pair becomes one Gumroad product. Filename pattern:
`{geo_slug}_{niche_slug}_{YYYY-MM-DD}.csv`

Auto-pricing by row count:
- < 200 rows → $29
- 200–499 rows → $39
- 500+ rows → $49

Listing title auto-updates to: `"Dallas HVAC Contacts — 347 rows (Updated Mar 30)"`

**Products at launch (default config):** 4 geos × 5 niches = 20 local biz + 3 real estate = **23 products**

---

## Gumroad Publish Flow

1. Diff `manifest.json` vs `listings` table — find new or row-count-changed products
2. **New product:** `POST api.gumroad.com/v2/products` — name, price, description, upload CSV
3. **Updated product:** `PUT` to update file + title with new row count + date
4. Update `listings` table — new `row_count`, `last_updated`
5. Retry failed uploads 3× with 5s gap → on persistent failure mark `status = 'pending_upload'`, retry next run

---

## Error Handling

| Failure | Behaviour |
|---|---|
| API rate limit | Exponential backoff (2s, 4s, 8s) → skip source for this run → log warning |
| Bot detection (403/429) | Skip that page/county → log → continue remaining sources |
| Gumroad API error | Retry 3× → mark `pending_upload` → retry next run |
| 0 new rows | Not an error — log warning, send alert, listings unchanged |
| Ollama offline | Skip enrichment — publish rows as-is |
| CoastalClaw offline | Log locally — agent continues unaffected |

**Principle:** a failure in one source or one stage never crashes the full run.

---

## Scheduling

- **Tool:** Windows Task Scheduler
- **Schedule:** Daily at 3:00 AM
- **Settings:** Run whether logged on or not · Wake to run: YES
- **Command:** `python C:\agent1\dirty_data_agent.py`

---

## CoastalClaw Integration

Agent 1 is a peripheral agent — runs independently, reports in via two endpoints:

| Endpoint | When | Payload |
|---|---|---|
| `POST :4747/api/agent-log` | After every run | `{ agent, status, new_rows, products_updated, duration_ms }` |
| `GET :4747/api/config` | Phase 2 — pull TARGET_GEOS remotely | replaces .env config |

CoastalClaw being offline never blocks the agent.

---

## Revenue Projection

| Metric | Value |
|---|---|
| Products at launch | 23 |
| Avg sales/product/month | 2 |
| Avg price | $35 |
| **Monthly passive revenue** | **~$1,610** |
| Growth lever | Add geos/niches to `.env` — linear scaling |

---

## Dependencies

```
playwright          # headless scraping
requests            # Google Places API + Gumroad API
sqlite3             # built-in
python-dotenv       # .env loading
ollama              # local enrichment (pip install ollama)
pandas              # CSV packaging
```

---

## Out of Scope (Phase 2)

- Subscription API for live data access
- Web dashboard for managing geos/niches
- Remote config via CoastalClaw instead of `.env`
- Auto-scaling to new counties based on sales data
