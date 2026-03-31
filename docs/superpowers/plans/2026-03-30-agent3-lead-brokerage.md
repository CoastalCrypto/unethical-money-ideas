# Agent 3 — Lead Brokerage Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two Python scripts — `lead_scraper.py` finds local businesses via Google Places, extracts emails via Playwright, scores fit with Ollama, and sends 3-email drip sequences; `reply_monitor.py` polls Gmail IMAP, classifies replies with Ollama, and emails the operator a lead card PDF + invoice template on hot replies.

**Architecture:** Two independent scripts share `agent3.db`. The scraper runs daily at 4AM; the monitor runs every 4 hours. Each failure is isolated — no crashed prospect blocks the others. Ollama is optional — scoring skips gracefully if offline.

**Tech Stack:** Python 3.11+, requests, playwright, sqlite3, ollama, reportlab, python-dotenv, smtplib (built-in), imaplib (built-in), Windows Task Scheduler

---

## Chunk 1: Project Setup & Database

### Task 1: Project skeleton and dependencies

**Files:**
- Create: `agent3/requirements.txt`
- Create: `agent3/.env.example`
- Create: `agent3/lead_scraper.py` (skeleton)
- Create: `agent3/reply_monitor.py` (skeleton)

- [ ] **Step 1: Create requirements.txt**

```
requests==2.31.0
playwright==1.44.0
python-dotenv==1.0.1
ollama==0.2.1
reportlab==4.1.0
pandas==2.2.2
```

- [ ] **Step 2: Create .env.example**

```env
# Google
GOOGLE_PLACES_API_KEY=your_key_here

# Email (Gmail SMTP + IMAP)
GMAIL_ADDRESS=your@gmail.com
GMAIL_APP_PASSWORD=your_app_password_here

# Operator delivery
OPERATOR_EMAIL=you@yourdomain.com

# Ollama
OLLAMA_URL=http://localhost:11434

# CoastalClaw
COASTALCLAW_URL=http://localhost:4747

# Alerting
TELEGRAM_BOT_TOKEN=your_token_here
TELEGRAM_CHAT_ID=your_chat_id_here

# Targets
TARGET_GEOS=Dallas TX,Houston TX,Austin TX
TARGET_NICHES=HVAC,plumbing,roofing,landscaping,web design
```

- [ ] **Step 3: Create lead_scraper.py skeleton**

```python
"""
Agent 3 — Lead Scraper
Runs daily at 4AM via Windows Task Scheduler.
Pipeline: SCRAPE → SCORE → EMAIL SEQUENCE
"""
import os, sqlite3, json, time, logging, smtplib
from datetime import date, datetime
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from pathlib import Path
import requests
from dotenv import load_dotenv

load_dotenv()

BASE_DIR = Path(__file__).parent
DB_PATH  = BASE_DIR / "agent3.db"
OUT_DIR  = BASE_DIR / "output"
TMPL_DIR = BASE_DIR / "templates"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(BASE_DIR / "agent3.log"),
        logging.StreamHandler(),
    ]
)
log = logging.getLogger(__name__)

def load_config():
    return {
        "places_key":      os.environ["GOOGLE_PLACES_API_KEY"],
        "gmail_address":   os.environ["GMAIL_ADDRESS"],
        "gmail_password":  os.environ["GMAIL_APP_PASSWORD"],
        "operator_email":  os.environ["OPERATOR_EMAIL"],
        "ollama_url":      os.getenv("OLLAMA_URL", "http://localhost:11434"),
        "coastalclaw_url": os.getenv("COASTALCLAW_URL", "http://localhost:4747"),
        "telegram_token":  os.getenv("TELEGRAM_BOT_TOKEN", ""),
        "telegram_chat":   os.getenv("TELEGRAM_CHAT_ID", ""),
        "geos":   [g.strip() for g in os.environ["TARGET_GEOS"].split(",")],
        "niches": [n.strip() for n in os.environ["TARGET_NICHES"].split(",")],
    }

if __name__ == "__main__":
    cfg  = load_config()
    conn = sqlite3.connect(DB_PATH)
    try:
        pass  # stages wired in subsequent tasks
    finally:
        conn.close()
```

- [ ] **Step 4: Create reply_monitor.py skeleton**

```python
"""
Agent 3 — Reply Monitor
Runs every 4 hours via Windows Task Scheduler.
Pipeline: POLL IMAP → CLASSIFY → DELIVER LEAD CARD
"""
import os, sqlite3, json, time, logging, imaplib, email as email_lib, smtplib
from datetime import datetime
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email import encoders
from pathlib import Path
import requests
from dotenv import load_dotenv

load_dotenv()

BASE_DIR = Path(__file__).parent
DB_PATH  = BASE_DIR / "agent3.db"
OUT_DIR  = BASE_DIR / "output"
TMPL_DIR = BASE_DIR / "templates"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(BASE_DIR / "agent3.log"),
        logging.StreamHandler(),
    ]
)
log = logging.getLogger(__name__)

def load_config():
    return {
        "gmail_address":   os.environ["GMAIL_ADDRESS"],
        "gmail_password":  os.environ["GMAIL_APP_PASSWORD"],
        "operator_email":  os.environ["OPERATOR_EMAIL"],
        "ollama_url":      os.getenv("OLLAMA_URL", "http://localhost:11434"),
        "coastalclaw_url": os.getenv("COASTALCLAW_URL", "http://localhost:4747"),
        "telegram_token":  os.getenv("TELEGRAM_BOT_TOKEN", ""),
        "telegram_chat":   os.getenv("TELEGRAM_CHAT_ID", ""),
    }

if __name__ == "__main__":
    cfg  = load_config()
    conn = sqlite3.connect(DB_PATH)
    try:
        pass  # stages wired in subsequent tasks
    finally:
        conn.close()
```

- [ ] **Step 5: Create email templates**

```bash
mkdir -p agent3/templates
```

`agent3/templates/email_day0.txt`:
```
Subject: Quick question about {business_name}'s content

Hi there,

I came across {business_name} and noticed you're doing great work in {niche} in {city}.

I work with {niche} businesses on short-form video content — the kind that brings in
new customers without needing a big budget or production team.

Worth a 10-minute call to see if it's a fit?

— {sender_name}
```

`agent3/templates/email_day3.txt`:
```
Subject: One thing that doubled bookings for {niche} businesses

Hi again,

Quick follow-up. I've been helping a few {niche} businesses in Texas with short-form
video — one added 3 new bookings a week just from a TikTok series we put together.

I'd love to show you what that looked like and see if something similar could work
for {business_name}.

Interested in a quick 15-minute chat this week?

— {sender_name}
```

`agent3/templates/email_day7.txt`:
```
Subject: Last one from me — free audit for {business_name}

Hi,

Last message, I promise.

I'd like to offer a free 15-minute content audit for {business_name} — I'll look at
your online presence and tell you exactly what content would move the needle most,
with zero obligation.

Reply with a time that works and I'll make it happen.

— {sender_name}
```

- [ ] **Step 6: Install dependencies**

```bash
cd agent3
pip install -r requirements.txt
playwright install chromium
```

- [ ] **Step 7: Commit**

```bash
git add agent3/
git commit -m "feat: agent3 project skeleton, templates, dependencies"
```

---

### Task 2: SQLite initialization

**Files:**
- Modify: `agent3/lead_scraper.py` — add `init_db()`
- Create: `agent3/tests/test_db.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_db.py
import sqlite3, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from lead_scraper import init_db

def test_init_db_creates_all_tables():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    tables = {r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'"
    ).fetchall()}
    assert tables == {"prospects", "emails_sent", "replies", "runs"}

def test_init_db_idempotent():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    init_db(conn)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python -m pytest tests/test_db.py -v
```
Expected: FAIL

- [ ] **Step 3: Implement init_db() in lead_scraper.py**

```python
def init_db(conn):
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS prospects (
            place_id        TEXT PRIMARY KEY,
            name            TEXT NOT NULL,
            email           TEXT,
            phone           TEXT,
            website         TEXT,
            geo             TEXT NOT NULL,
            niche           TEXT NOT NULL,
            rating          REAL,
            fit_score       INTEGER,
            fit_reason      TEXT,
            status          TEXT DEFAULT 'pending_email',
            scraped_at      DATE NOT NULL
        );
        CREATE TABLE IF NOT EXISTS emails_sent (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            place_id        TEXT NOT NULL,
            sequence_day    INTEGER NOT NULL,
            sent_at         DATETIME NOT NULL,
            message_id      TEXT
        );
        CREATE TABLE IF NOT EXISTS replies (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            place_id        TEXT NOT NULL,
            received_at     DATETIME NOT NULL,
            snippet         TEXT,
            sentiment       TEXT,
            lead_card_sent  INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS runs (
            run_id              INTEGER PRIMARY KEY AUTOINCREMENT,
            job                 TEXT NOT NULL,
            started_at          DATETIME NOT NULL,
            finished_at         DATETIME,
            prospects_added     INTEGER DEFAULT 0,
            emails_sent         INTEGER DEFAULT 0,
            replies_found       INTEGER DEFAULT 0,
            status              TEXT DEFAULT 'running',
            error_msg           TEXT
        );
    """)
    conn.commit()
```

Also add `init_db` import to `reply_monitor.py`:
```python
# Add near top of reply_monitor.py
import sys
sys.path.insert(0, str(BASE_DIR))
from lead_scraper import init_db
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python -m pytest tests/test_db.py -v
```
Expected: 2 PASSED

- [ ] **Step 5: Commit**

```bash
git add agent3/lead_scraper.py agent3/reply_monitor.py agent3/tests/test_db.py
git commit -m "feat: agent3 SQLite schema init"
```

---

## Chunk 2: Scraper & Email Extraction

### Task 3: Google Places scraper (rating filter 3.5–4.3)

**Files:**
- Modify: `agent3/lead_scraper.py` — implement `scrape_places_leads()`
- Create: `agent3/tests/test_scraper.py`

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_scraper.py
import sqlite3, sys, json
from pathlib import Path
from unittest.mock import patch, MagicMock
sys.path.insert(0, str(Path(__file__).parent.parent))
from lead_scraper import init_db, scrape_places_leads

MOCK_PLACES = {
    "results": [
        {"place_id": "g1", "name": "Good HVAC", "rating": 4.0,
         "formatted_address": "1 Main, Dallas TX",
         "formatted_phone_number": "214-555-0001",
         "website": "https://goodhvac.com", "types": ["hvac_contractor"]},
        {"place_id": "g2", "name": "Too Good LLC", "rating": 4.8,  # filtered out
         "formatted_address": "2 Main, Dallas TX",
         "formatted_phone_number": "", "website": "", "types": ["hvac_contractor"]},
        {"place_id": "g3", "name": "Too Bad HVAC", "rating": 2.9,  # filtered out
         "formatted_address": "3 Main, Dallas TX",
         "formatted_phone_number": "", "website": "", "types": ["hvac_contractor"]},
    ],
    "status": "OK"
}

def test_scrape_filters_by_rating():
    with patch("lead_scraper.requests.get") as mock_get:
        mock_resp = MagicMock()
        mock_resp.json.return_value = MOCK_PLACES
        mock_resp.raise_for_status = MagicMock()
        mock_get.return_value = mock_resp
        rows = scrape_places_leads("HVAC", "Dallas TX", "fake_key")
    # Only rating 3.5–4.3 passes
    assert len(rows) == 1
    assert rows[0]["place_id"] == "g1"

def test_scrape_skips_existing_prospects():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    conn.execute(
        "INSERT INTO prospects (place_id, name, geo, niche, scraped_at) VALUES ('g1','Good HVAC','Dallas TX','HVAC','2026-03-29')"
    )
    conn.commit()
    with patch("lead_scraper.requests.get") as mock_get:
        mock_resp = MagicMock()
        mock_resp.json.return_value = MOCK_PLACES
        mock_resp.raise_for_status = MagicMock()
        mock_get.return_value = mock_resp
        rows = scrape_places_leads("HVAC", "Dallas TX", "fake_key", conn=conn)
    assert len(rows) == 0  # g1 already seen
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
python -m pytest tests/test_scraper.py -v
```
Expected: FAIL

- [ ] **Step 3: Implement scrape_places_leads()**

```python
PLACES_URL = "https://maps.googleapis.com/maps/api/place/textsearch/json"
RATING_MIN = 3.5
RATING_MAX = 4.3

def scrape_places_leads(niche, geo, api_key, conn=None, max_results=200):
    """
    Fetch businesses from Google Places, filtered to rating 3.5–4.3.
    If conn provided, skips place_ids already in prospects table.
    """
    existing_ids = set()
    if conn:
        existing_ids = {r[0] for r in conn.execute("SELECT place_id FROM prospects").fetchall()}

    rows = []
    params = {"query": f"{niche} in {geo}", "key": api_key}
    backoff = 2

    while len(rows) < max_results:
        try:
            resp = requests.get(PLACES_URL, params=params, timeout=10)
            resp.raise_for_status()
            data = resp.json()
        except Exception as e:
            log.warning(f"Places API error ({niche}/{geo}): {e}")
            time.sleep(backoff)
            backoff = min(backoff * 2, 8)
            break

        for r in data.get("results", []):
            pid    = r.get("place_id")
            rating = r.get("rating", 0)
            if pid in existing_ids:
                continue
            if not (RATING_MIN <= rating <= RATING_MAX):
                continue
            rows.append({
                "place_id": pid,
                "name":     r.get("name"),
                "phone":    r.get("formatted_phone_number", ""),
                "website":  r.get("website", ""),
                "address":  r.get("formatted_address", ""),
                "rating":   rating,
                "category": (r.get("types") or [""])[0],
                "geo":      geo,
                "niche":    niche,
            })

        token = data.get("next_page_token")
        if not token:
            break
        time.sleep(2)
        params = {"pagetoken": token, "key": api_key}

    log.info(f"Places scraped {len(rows)} leads for {niche}/{geo}")
    return rows
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
python -m pytest tests/test_scraper.py -v
```
Expected: 2 PASSED

- [ ] **Step 5: Commit**

```bash
git add agent3/lead_scraper.py agent3/tests/test_scraper.py
git commit -m "feat: agent3 Google Places scraper with rating filter 3.5-4.3"
```

---

### Task 4: Playwright email extraction

**Files:**
- Modify: `agent3/lead_scraper.py` — implement `extract_email_from_site()`

- [ ] **Step 1: Write the failing test**

Add to `tests/test_scraper.py`:

```python
def test_extract_email_finds_mailto():
    from unittest.mock import patch, MagicMock
    from lead_scraper import extract_email_from_site

    mock_page = MagicMock()
    mock_page.content.return_value = '<a href="mailto:owner@biz.com">Contact</a>'
    mock_page.goto = MagicMock()

    with patch("lead_scraper.sync_playwright") as mock_pw:
        mock_browser = MagicMock()
        mock_pw.return_value.__enter__.return_value.chromium.launch.return_value = mock_browser
        mock_browser.new_page.return_value = mock_page
        email = extract_email_from_site("https://biz.com")

    assert email == "owner@biz.com"

def test_extract_email_returns_none_on_failure():
    from lead_scraper import extract_email_from_site
    with patch("lead_scraper.sync_playwright") as mock_pw:
        mock_pw.return_value.__enter__.return_value.chromium.launch.side_effect = Exception("blocked")
        email = extract_email_from_site("https://biz.com")
    assert email is None
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
python -m pytest tests/test_scraper.py::test_extract_email_finds_mailto tests/test_scraper.py::test_extract_email_returns_none_on_failure -v
```
Expected: FAIL

- [ ] **Step 3: Implement extract_email_from_site()**

```python
import re
from playwright.sync_api import sync_playwright

EMAIL_RE = re.compile(r"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}")

def extract_email_from_site(website_url, timeout_ms=15000):
    """
    Visit homepage + /contact page, find first email address.
    Returns email string or None.
    """
    if not website_url:
        return None
    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch(headless=True)
            page = browser.new_page()
            pages_to_check = [website_url, website_url.rstrip("/") + "/contact"]
            for url in pages_to_check:
                try:
                    page.goto(url, timeout=timeout_ms)
                    html = page.content()
                    # mailto links first
                    mailto = re.search(r'mailto:([^"\'>\s]+)', html)
                    if mailto:
                        browser.close()
                        return mailto.group(1).split("?")[0]
                    # visible email pattern
                    match = EMAIL_RE.search(html)
                    if match:
                        email = match.group(0)
                        # exclude generic/system emails
                        if not any(skip in email.lower() for skip in
                                   ["example", "domain", "email", "noreply", "schema"]):
                            browser.close()
                            return email
                except Exception:
                    continue
            browser.close()
    except Exception as e:
        log.debug(f"Email extraction failed for {website_url}: {e}")
    return None
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
python -m pytest tests/test_scraper.py -v
```
Expected: All PASSED

- [ ] **Step 5: Commit**

```bash
git add agent3/lead_scraper.py
git commit -m "feat: agent3 Playwright email extraction from homepage and /contact"
```

---

## Chunk 3: Fit Scoring & Email Sequences

### Task 5: Ollama fit scoring

**Files:**
- Modify: `agent3/lead_scraper.py` — implement `score_fit()`
- Create: `agent3/tests/test_scoring.py`

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_scoring.py
import sys, json
from pathlib import Path
from unittest.mock import patch, MagicMock
sys.path.insert(0, str(Path(__file__).parent.parent))
from lead_scraper import score_fit

PROSPECT = {
    "name": "Dallas HVAC Co",
    "rating": 4.0,
    "category": "hvac_contractor",
    "website": "https://dallashvac.com",
}

def test_score_fit_returns_score_and_reason():
    mock_resp = MagicMock()
    mock_resp.json.return_value = {
        "message": {"content": json.dumps({"score": 4, "reason": "Small team service biz"})}
    }
    with patch("lead_scraper.requests.post", return_value=mock_resp):
        score, reason = score_fit(PROSPECT, "http://localhost:11434")
    assert score == 4
    assert "Small" in reason

def test_score_fit_returns_none_when_offline():
    with patch("lead_scraper.requests.post", side_effect=ConnectionError):
        score, reason = score_fit(PROSPECT, "http://localhost:11434")
    assert score is None
    assert reason is None
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
python -m pytest tests/test_scoring.py -v
```
Expected: FAIL

- [ ] **Step 3: Implement score_fit()**

```python
FIT_PROMPT = """Score this business 1-5 for content agency fit:
Name: {name}
Rating: {rating}
Category: {category}
Website snippet: {website}

5 = clearly needs content help, small team, service business
1 = has in-house marketing, large brand, or irrelevant niche

Return ONLY valid JSON: {{"score": N, "reason": "..."}}"""

def score_fit(prospect, ollama_url):
    """Score prospect fit 1-5 via Ollama. Returns (score, reason) or (None, None) if offline."""
    try:
        resp = requests.post(
            f"{ollama_url}/api/chat",
            json={
                "model": "llama3.1:8b",
                "messages": [{"role": "user", "content": FIT_PROMPT.format(
                    name=prospect.get("name", ""),
                    rating=prospect.get("rating", ""),
                    category=prospect.get("category", ""),
                    website=prospect.get("website", "")[:200],
                )}],
                "stream": False,
            },
            timeout=30,
        )
        content = resp.json()["message"]["content"].strip().strip("```json").strip("```").strip()
        data = json.loads(content)
        return int(data["score"]), data.get("reason", "")
    except Exception as e:
        log.debug(f"Fit scoring failed for {prospect.get('name')}: {e}")
        return None, None
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
python -m pytest tests/test_scoring.py -v
```
Expected: 2 PASSED

- [ ] **Step 5: Commit**

```bash
git add agent3/lead_scraper.py agent3/tests/test_scoring.py
git commit -m "feat: agent3 Ollama fit scoring with offline fallback"
```

---

### Task 6: Email sequence sender

**Files:**
- Modify: `agent3/lead_scraper.py` — implement `send_sequence_email()`, `run_email_sequences()`
- Create: `agent3/tests/test_sequences.py`

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_sequences.py
import sqlite3, sys
from pathlib import Path
from unittest.mock import patch, MagicMock
sys.path.insert(0, str(Path(__file__).parent.parent))
from lead_scraper import init_db, send_sequence_email, run_email_sequences

def test_send_sequence_email_sends_smtp():
    with patch("lead_scraper.smtplib.SMTP_SSL") as mock_smtp:
        mock_server = MagicMock()
        mock_smtp.return_value.__enter__.return_value = mock_server
        send_sequence_email(
            gmail_address="from@gmail.com",
            gmail_password="pass",
            to_address="biz@example.com",
            subject="Test",
            body="Hello {business_name}",
            business_name="TestBiz",
        )
    mock_server.send_message.assert_called_once()

def test_run_email_sequences_sends_day0_to_new():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    conn.execute(
        "INSERT INTO prospects VALUES ('p1','TestBiz','biz@ex.com','555','https://biz.com','Dallas TX','HVAC',4.0,4,'Good fit','pending_email','2026-03-30')"
    )
    conn.commit()
    with patch("lead_scraper.send_sequence_email") as mock_send:
        run_email_sequences(conn, {"gmail_address": "x", "gmail_password": "x"}, "John")
    mock_send.assert_called_once()
    status = conn.execute("SELECT status FROM prospects WHERE place_id='p1'").fetchone()[0]
    assert status == "sequence_active"

def test_run_email_sequences_respects_3_day_gap():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    conn.execute(
        "INSERT INTO prospects VALUES ('p1','TestBiz','biz@ex.com','555','https://biz.com','Dallas TX','HVAC',4.0,4,'Good fit','sequence_active','2026-03-28')"
    )
    # Day 0 sent today — day 3 not due yet
    conn.execute(
        "INSERT INTO emails_sent (place_id, sequence_day, sent_at) VALUES ('p1', 0, '2026-03-30T06:00:00')"
    )
    conn.commit()
    with patch("lead_scraper.send_sequence_email") as mock_send:
        run_email_sequences(conn, {"gmail_address": "x", "gmail_password": "x"}, "John")
    mock_send.assert_not_called()
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
python -m pytest tests/test_sequences.py -v
```
Expected: FAIL

- [ ] **Step 3: Implement email sequence functions**

```python
def send_sequence_email(gmail_address, gmail_password, to_address,
                        subject, body, **kwargs):
    """Send a single email via Gmail SMTP. kwargs used for template substitution."""
    body = body.format(**{k: v or "" for k, v in kwargs.items()})
    subject = subject.format(**{k: v or "" for k, v in kwargs.items()})
    msg = MIMEMultipart()
    msg["From"]    = gmail_address
    msg["To"]      = to_address
    msg["Subject"] = subject
    msg.attach(MIMEText(body, "plain"))
    with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
        server.login(gmail_address, gmail_password)
        server.send_message(msg)

SEQUENCE = [
    (0,  "email_day0.txt"),
    (3,  "email_day3.txt"),
    (7,  "email_day7.txt"),
]

def run_email_sequences(conn, cfg, sender_name="Content Agency"):
    """
    Send next due email in sequence to each eligible prospect.
    Rules:
    - pending_email + fit_score >= 3 (or None) → send day 0
    - sequence_active → send day 3 or 7 if enough days have passed
    - do_not_contact / replied_* → skip
    """
    sent_count = 0
    today = datetime.now()

    # Day 0: brand-new prospects
    new_prospects = conn.execute(
        "SELECT * FROM prospects WHERE status='pending_email' AND email IS NOT NULL "
        "AND (fit_score IS NULL OR fit_score >= 3)"
    ).fetchall()
    cols = [d[0] for d in conn.execute("SELECT * FROM prospects LIMIT 0").description]

    for row in new_prospects:
        p = dict(zip(cols, row))
        _send_day(conn, cfg, p, day=0, sender_name=sender_name)
        conn.execute(
            "UPDATE prospects SET status='sequence_active' WHERE place_id=?", (p["place_id"],)
        )
        conn.commit()
        sent_count += 1

    # Day 3 / Day 7: active sequences
    active = conn.execute(
        "SELECT * FROM prospects WHERE status='sequence_active' AND email IS NOT NULL"
    ).fetchall()
    for row in active:
        p = dict(zip(cols, row))
        last = conn.execute(
            "SELECT sequence_day, sent_at FROM emails_sent WHERE place_id=? ORDER BY sent_at DESC LIMIT 1",
            (p["place_id"],)
        ).fetchone()
        if not last:
            continue
        last_day, last_sent_at = last
        days_since = (today - datetime.fromisoformat(last_sent_at)).days

        for day, _ in SEQUENCE:
            if day > last_day and days_since >= (day - last_day):
                _send_day(conn, cfg, p, day=day, sender_name=sender_name)
                sent_count += 1
                break

    log.info(f"Email sequences: {sent_count} emails sent")
    return sent_count

def _send_day(conn, cfg, prospect, day, sender_name):
    template_file = dict(SEQUENCE)[day]
    template = (TMPL_DIR / template_file).read_text()
    city = prospect["geo"].split(",")[0].strip() if "," in prospect["geo"] else prospect["geo"]
    subject_line = template.split("\n")[0].replace("Subject: ", "")
    body = "\n".join(template.split("\n")[1:]).strip()
    try:
        send_sequence_email(
            gmail_address=cfg["gmail_address"],
            gmail_password=cfg["gmail_password"],
            to_address=prospect["email"],
            subject=subject_line,
            body=body,
            business_name=prospect["name"],
            niche=prospect["niche"],
            city=city,
            sender_name=sender_name,
        )
        conn.execute(
            "INSERT INTO emails_sent (place_id, sequence_day, sent_at) VALUES (?,?,?)",
            (prospect["place_id"], day, datetime.now().isoformat())
        )
        conn.commit()
        log.info(f"Sent day {day} email to {prospect['email']}")
    except Exception as e:
        log.warning(f"Email send failed (day {day}) to {prospect.get('email')}: {e}")
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
python -m pytest tests/test_sequences.py -v
```
Expected: 3 PASSED

- [ ] **Step 5: Commit**

```bash
git add agent3/lead_scraper.py agent3/tests/test_sequences.py
git commit -m "feat: agent3 3-email drip sequences with 3-day gap enforcement"
```

---

### Task 7: Wire lead_scraper.py main

**Files:**
- Modify: `agent3/lead_scraper.py` — implement `run_scraper()` orchestrator

- [ ] **Step 1: Implement run logging helpers**

```python
def _start_run(conn, job):
    cur = conn.execute(
        "INSERT INTO runs (job, started_at) VALUES (?,?)",
        (job, datetime.now().isoformat())
    )
    conn.commit()
    return cur.lastrowid

def _finish_run(conn, run_id, prospects_added=0, emails_sent=0,
                status="ok", error_msg=None):
    conn.execute(
        """UPDATE runs SET finished_at=?, prospects_added=?, emails_sent=?,
           status=?, error_msg=? WHERE run_id=?""",
        (datetime.now().isoformat(), prospects_added, emails_sent,
         status, error_msg, run_id)
    )
    conn.commit()

def _post_coastalclaw(cfg, job, status, prospects_added, emails_sent, duration_ms):
    try:
        requests.post(f"{cfg['coastalclaw_url']}/api/agent-log", json={
            "agent": "agent3", "job": job, "status": status,
            "prospects_added": prospects_added,
            "emails_sent": emails_sent,
            "duration_ms": duration_ms,
        }, timeout=5)
    except Exception:
        pass
```

- [ ] **Step 2: Implement run_scraper()**

```python
def run_scraper(cfg, conn):
    """Daily 4AM: scrape → score → insert → send sequences."""
    start_ts = time.time()
    run_id = _start_run(conn, "scrape")
    prospects_added = 0
    emails_sent = 0

    try:
        for geo in cfg["geos"]:
            for niche in cfg["niches"]:
                try:
                    rows = scrape_places_leads(niche, geo, cfg["places_key"], conn=conn)
                    for r in rows:
                        # Email extraction
                        email = extract_email_from_site(r.get("website"))
                        fit_score, fit_reason = score_fit(r, cfg["ollama_url"])

                        conn.execute(
                            """INSERT OR IGNORE INTO prospects
                               (place_id, name, email, phone, website, geo, niche,
                                rating, fit_score, fit_reason, status, scraped_at)
                               VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
                            (r["place_id"], r["name"], email, r.get("phone"),
                             r.get("website"), geo, niche, r.get("rating"),
                             fit_score, fit_reason,
                             "pending_email" if (fit_score is None or fit_score >= 3) else "skipped",
                             str(date.today()))
                        )
                        conn.commit()
                        prospects_added += 1
                except Exception as e:
                    log.warning(f"Scrape failed for {niche}/{geo}: {e}")

        emails_sent = run_email_sequences(conn, cfg)
        _finish_run(conn, run_id, prospects_added=prospects_added,
                    emails_sent=emails_sent, status="ok")

    except Exception as e:
        _finish_run(conn, run_id, status="error", error_msg=str(e))
        raise

    _post_coastalclaw(cfg, "scrape", "ok", prospects_added, emails_sent,
                      int((time.time()-start_ts)*1000))
```

- [ ] **Step 3: Update __main__ to call run_scraper()**

```python
if __name__ == "__main__":
    cfg  = load_config()
    conn = sqlite3.connect(DB_PATH)
    init_db(conn)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    try:
        run_scraper(cfg, conn)
    finally:
        conn.close()
```

- [ ] **Step 4: Commit**

```bash
git add agent3/lead_scraper.py
git commit -m "feat: agent3 lead_scraper main orchestrator"
```

---

## Chunk 4: Reply Monitor & Lead Card Delivery

### Task 8: Gmail IMAP reply polling + Ollama sentiment classification

**Files:**
- Modify: `agent3/reply_monitor.py` — implement `poll_replies()`, `classify_reply()`
- Create: `agent3/tests/test_monitor.py`

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_monitor.py
import sqlite3, sys, json
from pathlib import Path
from unittest.mock import patch, MagicMock
sys.path.insert(0, str(Path(__file__).parent.parent))
from lead_scraper import init_db
from reply_monitor import classify_reply, process_reply

def test_classify_reply_interested():
    mock_resp = MagicMock()
    mock_resp.json.return_value = {
        "message": {"content": json.dumps({"sentiment": "interested", "reason": "wants call"})}
    }
    with patch("reply_monitor.requests.post", return_value=mock_resp):
        sentiment = classify_reply("Yes, let's chat!", "http://localhost:11434")
    assert sentiment == "interested"

def test_classify_reply_unsubscribe():
    mock_resp = MagicMock()
    mock_resp.json.return_value = {
        "message": {"content": json.dumps({"sentiment": "unsubscribe", "reason": "opted out"})}
    }
    with patch("reply_monitor.requests.post", return_value=mock_resp):
        sentiment = classify_reply("Please remove me from your list", "http://localhost:11434")
    assert sentiment == "unsubscribe"

def test_process_reply_marks_do_not_contact_on_unsubscribe():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    conn.execute(
        "INSERT INTO prospects (place_id,name,email,geo,niche,scraped_at,status) "
        "VALUES ('p1','Biz','biz@ex.com','Dallas TX','HVAC','2026-03-30','sequence_active')"
    )
    conn.commit()
    with patch("reply_monitor.classify_reply", return_value="unsubscribe"), \
         patch("reply_monitor.deliver_lead_card"):
        process_reply(conn, {"ollama_url": "x"}, "biz@ex.com",
                      "Remove me", "Please unsubscribe", operator_cfg={})
    status = conn.execute("SELECT status FROM prospects WHERE place_id='p1'").fetchone()[0]
    assert status == "do_not_contact"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
python -m pytest tests/test_monitor.py -v
```
Expected: FAIL

- [ ] **Step 3: Implement classify_reply() and process_reply() in reply_monitor.py**

```python
CLASSIFY_PROMPT = """Classify this email reply sentiment:
Subject: {subject}
Body: {body}

Options: interested / not_interested / unsubscribe

Return ONLY valid JSON: {{"sentiment": "...", "reason": "..."}}"""

def classify_reply(body, ollama_url, subject=""):
    """Classify reply sentiment via Ollama. Returns sentiment string."""
    try:
        resp = requests.post(
            f"{ollama_url}/api/chat",
            json={
                "model": "llama3.1:8b",
                "messages": [{"role": "user", "content": CLASSIFY_PROMPT.format(
                    subject=subject[:200], body=body[:500]
                )}],
                "stream": False,
            },
            timeout=30,
        )
        content = resp.json()["message"]["content"].strip().strip("```json").strip("```").strip()
        data = json.loads(content)
        return data.get("sentiment", "not_interested")
    except Exception as e:
        log.warning(f"Reply classification failed: {e}")
        return "not_interested"

def process_reply(conn, cfg, from_email, subject, body, operator_cfg):
    """Handle a single reply: classify, update DB, deliver lead card if interested."""
    prospect = conn.execute(
        "SELECT * FROM prospects WHERE email=?", (from_email,)
    ).fetchone()
    if not prospect:
        log.debug(f"No prospect found for reply from {from_email}")
        return

    cols = [d[0] for d in conn.execute("SELECT * FROM prospects LIMIT 0").description]
    p = dict(zip(cols, prospect))

    sentiment = classify_reply(body, cfg["ollama_url"], subject=subject)

    conn.execute(
        "INSERT INTO replies (place_id, received_at, snippet, sentiment) VALUES (?,?,?,?)",
        (p["place_id"], datetime.now().isoformat(), body[:300], sentiment)
    )

    if sentiment == "unsubscribe":
        conn.execute(
            "UPDATE prospects SET status='do_not_contact' WHERE place_id=?", (p["place_id"],)
        )
    elif sentiment == "interested":
        conn.execute(
            "UPDATE prospects SET status='replied_interested' WHERE place_id=?", (p["place_id"],)
        )
        deliver_lead_card(conn, p, body, operator_cfg)
    else:
        conn.execute(
            "UPDATE prospects SET status='replied_not_interested' WHERE place_id=?", (p["place_id"],)
        )

    conn.commit()
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
python -m pytest tests/test_monitor.py -v
```
Expected: 3 PASSED

- [ ] **Step 5: Commit**

```bash
git add agent3/reply_monitor.py agent3/tests/test_monitor.py
git commit -m "feat: agent3 IMAP reply polling and Ollama sentiment classification"
```

---

### Task 9: Lead card PDF generation + operator delivery

**Files:**
- Modify: `agent3/reply_monitor.py` — implement `make_lead_card_pdf()`, `deliver_lead_card()`
- Create: `agent3/tests/test_lead_card.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_lead_card.py
import sys, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from reply_monitor import make_lead_card_pdf

PROSPECT = {
    "place_id": "p1",
    "name": "Dallas HVAC Co",
    "email": "owner@dallashvac.com",
    "phone": "214-555-0001",
    "geo": "Dallas TX",
    "niche": "HVAC",
    "rating": 4.0,
    "fit_score": 4,
    "fit_reason": "Small service team, no social presence",
}

def test_make_lead_card_creates_pdf():
    with tempfile.TemporaryDirectory() as tmpdir:
        out_path = Path(tmpdir) / "lead_card.pdf"
        make_lead_card_pdf(PROSPECT, reply_snippet="Yes, let's chat!", out_path=out_path)
        assert out_path.exists()
        assert out_path.stat().st_size > 500
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python -m pytest tests/test_lead_card.py -v
```
Expected: FAIL

- [ ] **Step 3: Implement make_lead_card_pdf() and deliver_lead_card()**

```python
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle

def make_lead_card_pdf(prospect, reply_snippet, out_path):
    """Generate a one-page lead card PDF for operator review."""
    doc = SimpleDocTemplate(str(out_path), pagesize=letter,
                            topMargin=40, bottomMargin=40,
                            leftMargin=50, rightMargin=50)
    styles = getSampleStyleSheet()
    bold = ParagraphStyle("bold", parent=styles["Normal"], fontName="Helvetica-Bold")
    elements = []

    elements.append(Paragraph("🔥 HOT LEAD", ParagraphStyle(
        "title", parent=styles["Title"],
        textColor=colors.HexColor("#e63946"), fontSize=24
    )))
    elements.append(Spacer(1, 10))
    elements.append(Paragraph(f"{prospect['name']} — {prospect['geo']} {prospect['niche']}", styles["Heading2"]))
    elements.append(Spacer(1, 16))

    data = [
        ["Rating", f"{prospect.get('rating', 'N/A')} ★"],
        ["Email", prospect.get("email", "N/A")],
        ["Phone", prospect.get("phone", "N/A")],
        ["Fit Score", f"{prospect.get('fit_score', 'N/A')}/5"],
        ["Fit Reason", prospect.get("fit_reason", "N/A")],
        ["Reply", reply_snippet[:200] if reply_snippet else "N/A"],
    ]
    table = Table(data, colWidths=[120, 350])
    table.setStyle(TableStyle([
        ("FONTNAME",   (0, 0), (0, -1), "Helvetica-Bold"),
        ("GRID",       (0, 0), (-1, -1), 0.5, colors.lightgrey),
        ("ROWBACKGROUNDS", (0, 0), (-1, -1), [colors.white, colors.HexColor("#f9f9f9")]),
        ("PADDING",    (0, 0), (-1, -1), 8),
    ]))
    elements.append(table)
    elements.append(Spacer(1, 20))
    elements.append(Paragraph("Suggested pitch: Content package for service businesses — $300–$800/mo", bold))
    doc.build(elements)

def deliver_lead_card(conn, prospect, reply_snippet, cfg):
    """Generate lead card PDF and email to operator."""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    pdf_path = OUT_DIR / f"lead_{prospect['place_id']}_{date.today()}.pdf"
    make_lead_card_pdf(prospect, reply_snippet=reply_snippet, out_path=pdf_path)

    msg = MIMEMultipart()
    msg["From"]    = cfg["gmail_address"]
    msg["To"]      = cfg["operator_email"]
    msg["Subject"] = f"Hot lead: {prospect['name']} — {prospect['geo']} {prospect['niche']}"
    msg.attach(MIMEText(
        f"New interested reply from {prospect['name']} ({prospect['email']}).\n\n"
        f"Reply snippet: {reply_snippet[:300]}\n\n"
        f"Lead card attached.",
        "plain"
    ))
    with open(pdf_path, "rb") as f:
        part = MIMEBase("application", "octet-stream")
        part.set_payload(f.read())
        encoders.encode_base64(part)
        part.add_header("Content-Disposition", f'attachment; filename="lead_card.pdf"')
        msg.attach(part)

    with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
        server.login(cfg["gmail_address"], cfg["gmail_password"])
        server.send_message(msg)

    conn.execute(
        "UPDATE replies SET lead_card_sent=1 WHERE place_id=? ORDER BY id DESC LIMIT 1",
        (prospect["place_id"],)
    )
    conn.commit()
    log.info(f"Lead card delivered for {prospect['name']}")
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python -m pytest tests/test_lead_card.py -v
```
Expected: PASSED

- [ ] **Step 5: Commit**

```bash
git add agent3/reply_monitor.py agent3/tests/test_lead_card.py
git commit -m "feat: agent3 lead card PDF generation and operator delivery"
```

---

### Task 10: Wire reply_monitor.py main

**Files:**
- Modify: `agent3/reply_monitor.py` — implement `poll_and_process()` + `__main__`

- [ ] **Step 1: Implement poll_and_process()**

```python
def poll_and_process(cfg, conn):
    """Poll Gmail IMAP for replies. Process each one."""
    start_ts = time.time()
    run_id = _start_run(conn, "monitor")
    replies_found = 0

    try:
        mail = imaplib.IMAP4_SSL("imap.gmail.com")
        mail.login(cfg["gmail_address"], cfg["gmail_password"])
        mail.select("INBOX")

        # Search for unseen emails (replies will appear as new messages in INBOX)
        _, msg_ids = mail.search(None, "UNSEEN")
        for mid in msg_ids[0].split():
            _, msg_data = mail.fetch(mid, "(RFC822)")
            raw = msg_data[0][1]
            msg = email_lib.message_from_bytes(raw)

            from_addr = email_lib.utils.parseaddr(msg["From"])[1]
            subject   = msg.get("Subject", "")
            body = ""
            if msg.is_multipart():
                for part in msg.walk():
                    if part.get_content_type() == "text/plain":
                        body = part.get_payload(decode=True).decode("utf-8", errors="ignore")
                        break
            else:
                body = msg.get_payload(decode=True).decode("utf-8", errors="ignore")

            process_reply(conn, cfg, from_addr, subject, body, cfg)
            replies_found += 1

        mail.logout()
        _finish_run(conn, run_id, replies_found=replies_found, status="ok")
    except Exception as e:
        _finish_run(conn, run_id, status="error", error_msg=str(e))
        log.error(f"Reply monitor failed: {e}")

    _post_coastalclaw(cfg, "monitor", "ok", 0, 0, replies_found,
                      int((time.time()-start_ts)*1000))

def _start_run(conn, job):
    cur = conn.execute(
        "INSERT INTO runs (job, started_at) VALUES (?,?)",
        (job, datetime.now().isoformat())
    )
    conn.commit()
    return cur.lastrowid

def _finish_run(conn, run_id, replies_found=0, status="ok", error_msg=None):
    conn.execute(
        """UPDATE runs SET finished_at=?, replies_found=?, status=?, error_msg=?
           WHERE run_id=?""",
        (datetime.now().isoformat(), replies_found, status, error_msg, run_id)
    )
    conn.commit()

def _post_coastalclaw(cfg, job, status, prospects_added, emails_sent, replies_found, duration_ms):
    try:
        requests.post(f"{cfg['coastalclaw_url']}/api/agent-log", json={
            "agent": "agent3", "job": job, "status": status,
            "prospects_added": prospects_added,
            "emails_sent": emails_sent,
            "replies_found": replies_found,
            "duration_ms": duration_ms,
        }, timeout=5)
    except Exception:
        pass
```

- [ ] **Step 2: Update __main__ in reply_monitor.py**

```python
if __name__ == "__main__":
    cfg  = load_config()
    conn = sqlite3.connect(DB_PATH)
    init_db(conn)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    try:
        poll_and_process(cfg, conn)
    finally:
        conn.close()
```

- [ ] **Step 3: Commit**

```bash
git add agent3/reply_monitor.py
git commit -m "feat: agent3 reply_monitor IMAP polling orchestrator"
```

---

## Chunk 5: Scheduling & Final Integration

### Task 11: Windows Task Scheduler + final checks

**Files:**
- Create: `agent3/setup_scheduler.bat`

- [ ] **Step 1: Create scheduler script**

```bat
@echo off
REM Run once as Administrator to register Agent 3 jobs
REM Usage: setup_scheduler.bat C:\path\to\python.exe C:\agent3

set PYTHON=%1
set AGENT_DIR=%2

REM Daily scraper at 4:00 AM
schtasks /Create /TN "Agent3_LeadScraper" ^
  /TR "%PYTHON% %AGENT_DIR%\lead_scraper.py" ^
  /SC DAILY /ST 04:00 ^
  /RU SYSTEM /RL HIGHEST /F

REM Reply monitor every 4 hours
schtasks /Create /TN "Agent3_ReplyMonitor_6AM"  /TR "%PYTHON% %AGENT_DIR%\reply_monitor.py" /SC DAILY /ST 06:00 /RU SYSTEM /RL HIGHEST /F
schtasks /Create /TN "Agent3_ReplyMonitor_10AM" /TR "%PYTHON% %AGENT_DIR%\reply_monitor.py" /SC DAILY /ST 10:00 /RU SYSTEM /RL HIGHEST /F
schtasks /Create /TN "Agent3_ReplyMonitor_2PM"  /TR "%PYTHON% %AGENT_DIR%\reply_monitor.py" /SC DAILY /ST 14:00 /RU SYSTEM /RL HIGHEST /F
schtasks /Create /TN "Agent3_ReplyMonitor_6PM"  /TR "%PYTHON% %AGENT_DIR%\reply_monitor.py" /SC DAILY /ST 18:00 /RU SYSTEM /RL HIGHEST /F

echo Tasks created:
echo   Agent3_LeadScraper     — daily 4:00 AM
echo   Agent3_ReplyMonitor_*  — 6AM, 10AM, 2PM, 6PM
echo Verify in Task Scheduler: taskschd.msc
```

- [ ] **Step 2: Run full test suite**

```bash
cd agent3
python -m pytest tests/ -v --tb=short
```
Expected: All PASSED, 0 failures

- [ ] **Step 3: Manual smoke test — lead scraper**

```bash
python lead_scraper.py 2>&1 | head -30
```
Expected: Places API calls logged, no unhandled exceptions

- [ ] **Step 4: Register scheduler tasks**

```bash
# Run as Administrator in cmd.exe:
setup_scheduler.bat "C:\Users\John\AppData\Local\Programs\Python\Python314\python.exe" "C:\agent3"
schtasks /Query /TN "Agent3_LeadScraper" /FO LIST
```
Expected: Task listed with status `Ready`

- [ ] **Step 5: Push to GitHub**

```bash
git add agent3/setup_scheduler.bat
git commit -m "feat: agent3 Windows Task Scheduler setup"
git push origin main
```
