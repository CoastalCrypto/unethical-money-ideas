# Agent 2 — Content Mill SaaS Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A single Python script with two scheduled jobs — daily onboarding for new Gumroad subscribers and a Monday batch run that generates 5 video scripts + posting calendar per client via Ollama, uploads to Google Drive, and emails the bundle.

**Architecture:** Single monolith file (`content_mill_agent.py`) with job functions `run_onboarding()` and `run_weekly()`. SQLite tracks client state, delivery history, and run logs. Gumroad API for billing sync. Google Drive API + Gmail SMTP for delivery. All Ollama inference is local.

**Tech Stack:** Python 3.11+, requests, google-api-python-client, google-auth, ollama, reportlab, python-dotenv, smtplib (built-in), sqlite3 (built-in), Windows Task Scheduler

---

## Chunk 1: Project Setup & Database

### Task 1: Project skeleton and dependencies

**Files:**
- Create: `agent2/requirements.txt`
- Create: `agent2/.env.example`
- Create: `agent2/content_mill_agent.py` (skeleton)

- [ ] **Step 1: Create requirements.txt**

```
requests==2.31.0
google-auth==2.29.0
google-auth-oauthlib==1.2.0
google-api-python-client==2.130.0
ollama==0.2.1
reportlab==4.1.0
python-dotenv==1.0.1
```

- [ ] **Step 2: Create .env.example**

```env
# Gumroad
GUMROAD_ACCESS_TOKEN=your_token_here
GUMROAD_PRODUCT_ID=your_product_id_here

# Google
GOOGLE_SERVICE_ACCOUNT_JSON=path/to/service_account.json
GOOGLE_FORM_SPREADSHEET_ID=your_spreadsheet_id_here

# Email (Gmail SMTP)
GMAIL_ADDRESS=your@gmail.com
GMAIL_APP_PASSWORD=your_app_password_here

# Ollama
OLLAMA_URL=http://localhost:11434

# CoastalClaw
COASTALCLAW_URL=http://localhost:4747

# Alerting
TELEGRAM_BOT_TOKEN=your_token_here
TELEGRAM_CHAT_ID=your_chat_id_here

# Pricing
SUBSCRIPTION_PRICE_USD=150
```

- [ ] **Step 3: Create content_mill_agent.py skeleton**

```python
"""
Agent 2 — Content Mill SaaS
Two scheduled jobs:
  - Daily 9AM: run_onboarding()  — pick up new Gumroad subscribers
  - Monday 6AM: run_weekly()     — generate + deliver content bundles
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
DB_PATH  = BASE_DIR / "agent2.db"
OUT_DIR  = BASE_DIR / "output"
TMPL_DIR = BASE_DIR / "templates"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(BASE_DIR / "agent2.log"),
        logging.StreamHandler(),
    ]
)
log = logging.getLogger(__name__)

def load_config():
    return {
        "gumroad_token":      os.environ["GUMROAD_ACCESS_TOKEN"],
        "gumroad_product_id": os.environ["GUMROAD_PRODUCT_ID"],
        "google_sa_json":     os.environ["GOOGLE_SERVICE_ACCOUNT_JSON"],
        "form_sheet_id":      os.environ["GOOGLE_FORM_SPREADSHEET_ID"],
        "gmail_address":      os.environ["GMAIL_ADDRESS"],
        "gmail_password":     os.environ["GMAIL_APP_PASSWORD"],
        "ollama_url":         os.getenv("OLLAMA_URL", "http://localhost:11434"),
        "coastalclaw_url":    os.getenv("COASTALCLAW_URL", "http://localhost:4747"),
        "telegram_token":     os.getenv("TELEGRAM_BOT_TOKEN", ""),
        "telegram_chat":      os.getenv("TELEGRAM_CHAT_ID", ""),
    }

# ── Job stubs (filled in subsequent tasks) ───────────────────────────────────

def run_onboarding(cfg, conn): pass
def run_weekly(cfg, conn):     pass

# ── Main ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import sys
    job = sys.argv[1] if len(sys.argv) > 1 else "onboarding"
    cfg  = load_config()
    conn = sqlite3.connect(DB_PATH)
    try:
        if job == "onboarding":
            run_onboarding(cfg, conn)
        elif job == "weekly":
            run_weekly(cfg, conn)
        else:
            print(f"Unknown job: {job}. Use 'onboarding' or 'weekly'.")
    finally:
        conn.close()
```

- [ ] **Step 4: Create template files**

```bash
mkdir -p agent2/templates
```

Create `agent2/templates/welcome_email.txt`:
```
Subject: Welcome to Content Mill — let's get your content set up 🎬

Hi {name},

Welcome! Your Content Mill subscription is active.

To start generating your weekly content, please fill out this quick 4-question form:
{form_url}

It takes 2 minutes and tells us your niche, tone, and target audience so we can
tailor your scripts perfectly.

Your first content bundle will be ready the Monday after we receive your answers.
It'll land in your Google Drive folder: {drive_url}

Questions? Reply to this email.

— Content Mill
```

Create `agent2/templates/weekly_email.txt`:
```
Subject: Your content for week of {week_of} is ready 🎬

Hi {name},

Your weekly content bundle is ready:
👉 {drive_url}

This week's scripts:
{script1_preview}

Your posting calendar is in the same folder.

See you next Monday,
— Content Mill
```

Create `agent2/templates/script_prompt.txt`:
```
You are a short-form video scriptwriter.

Client: {name}
Niche: {niche}
Tone: {tone}
Platform: {platform}
Target audience: {target_audience}
Topics already used (do NOT repeat): {used_topics_last_30_days}

Write 5 video scripts for this week. Each script must be:
- 45–60 seconds when read aloud
- Start with a pattern-interrupt hook (first 3 words grab attention)
- Deliver one clear insight or tip
- End with a soft CTA ("follow for more" or "comment X if...")

Return JSON: [ {"title": "...", "hook": "...", "body": "...", "cta": "..."} ]
```

- [ ] **Step 5: Install dependencies**

```bash
cd agent2
pip install -r requirements.txt
```

- [ ] **Step 6: Commit**

```bash
git add agent2/
git commit -m "feat: agent2 project skeleton, templates, dependencies"
```

---

### Task 2: SQLite initialization

**Files:**
- Modify: `agent2/content_mill_agent.py` — add `init_db()`
- Create: `agent2/tests/test_db.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_db.py
import sqlite3, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from content_mill_agent import init_db

def test_init_db_creates_all_tables():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    tables = {r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'"
    ).fetchall()}
    assert tables == {"clients", "used_topics", "deliveries", "runs"}

def test_init_db_idempotent():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    init_db(conn)  # no error
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python -m pytest tests/test_db.py -v
```
Expected: FAIL

- [ ] **Step 3: Implement init_db()**

```python
def init_db(conn):
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS clients (
            gumroad_subscriber_id  TEXT PRIMARY KEY,
            email                  TEXT NOT NULL,
            name                   TEXT,
            niche                  TEXT,
            tone                   TEXT,
            platform               TEXT,
            target_audience        TEXT,
            drive_folder_id        TEXT,
            status                 TEXT DEFAULT 'pending_onboarding',
            subscribed_at          DATE,
            form_reminder_sent_at  DATE
        );
        CREATE TABLE IF NOT EXISTS used_topics (
            client_id  TEXT NOT NULL,
            topic      TEXT NOT NULL,
            used_on    DATE NOT NULL
        );
        CREATE TABLE IF NOT EXISTS deliveries (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            client_id   TEXT NOT NULL,
            week_of     DATE NOT NULL,
            drive_url   TEXT,
            sent_at     DATETIME,
            status      TEXT DEFAULT 'pending'
        );
        CREATE TABLE IF NOT EXISTS runs (
            run_id             INTEGER PRIMARY KEY AUTOINCREMENT,
            job                TEXT NOT NULL,
            started_at         DATETIME NOT NULL,
            finished_at        DATETIME,
            clients_processed  INTEGER DEFAULT 0,
            deliveries_sent    INTEGER DEFAULT 0,
            status             TEXT DEFAULT 'running',
            error_msg          TEXT
        );
    """)
    conn.commit()
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python -m pytest tests/test_db.py -v
```
Expected: 2 PASSED

- [ ] **Step 5: Commit**

```bash
git add agent2/content_mill_agent.py agent2/tests/test_db.py
git commit -m "feat: agent2 SQLite schema init"
```

---

## Chunk 2: Gumroad Billing Sync

### Task 3: Gumroad subscriber sync

**Files:**
- Modify: `agent2/content_mill_agent.py` — implement `sync_gumroad_subscribers()`
- Create: `agent2/tests/test_billing.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_billing.py
import sqlite3, sys, json
from pathlib import Path
from unittest.mock import patch, MagicMock
sys.path.insert(0, str(Path(__file__).parent.parent))
from content_mill_agent import init_db, sync_gumroad_subscribers

MOCK_SUBSCRIBERS = {
    "success": True,
    "subscribers": [
        {
            "id": "sub_001",
            "email": "alice@example.com",
            "purchaser_id": "sub_001",
            "created_at": "2026-03-28T10:00:00Z",
            "cancelled_at": None,
        },
        {
            "id": "sub_002",
            "email": "bob@example.com",
            "purchaser_id": "sub_002",
            "created_at": "2026-03-25T10:00:00Z",
            "cancelled_at": "2026-03-29T10:00:00Z",  # churned
        }
    ]
}

def test_sync_adds_new_subscribers():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    with patch("content_mill_agent.requests.get") as mock_get:
        mock_resp = MagicMock()
        mock_resp.json.return_value = MOCK_SUBSCRIBERS
        mock_resp.raise_for_status = MagicMock()
        mock_get.return_value = mock_resp
        new_ids = sync_gumroad_subscribers(conn, "fake_token", "prod_123")
    assert "sub_001" in new_ids
    client = conn.execute("SELECT status FROM clients WHERE gumroad_subscriber_id='sub_001'").fetchone()
    assert client[0] == "pending_onboarding"

def test_sync_marks_churned():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    conn.execute("INSERT INTO clients (gumroad_subscriber_id, email, status) VALUES ('sub_002','bob@example.com','ready')")
    conn.commit()
    with patch("content_mill_agent.requests.get") as mock_get:
        mock_resp = MagicMock()
        mock_resp.json.return_value = MOCK_SUBSCRIBERS
        mock_resp.raise_for_status = MagicMock()
        mock_get.return_value = mock_resp
        sync_gumroad_subscribers(conn, "fake_token", "prod_123")
    client = conn.execute("SELECT status FROM clients WHERE gumroad_subscriber_id='sub_002'").fetchone()
    assert client[0] == "churned"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
python -m pytest tests/test_billing.py -v
```
Expected: FAIL

- [ ] **Step 3: Implement sync_gumroad_subscribers()**

```python
GUMROAD_SUBS_URL = "https://api.gumroad.com/v2/products/{product_id}/subscribers"

def sync_gumroad_subscribers(conn, token, product_id):
    """Sync subscribers from Gumroad. Returns list of new subscriber IDs."""
    resp = requests.get(
        GUMROAD_SUBS_URL.format(product_id=product_id),
        headers={"Authorization": f"Bearer {token}"},
        timeout=15,
    )
    resp.raise_for_status()
    subscribers = resp.json().get("subscribers", [])

    new_ids = []
    today = str(date.today())

    for sub in subscribers:
        sid   = sub["id"]
        email = sub["email"]
        cancelled = sub.get("cancelled_at")

        existing = conn.execute(
            "SELECT status FROM clients WHERE gumroad_subscriber_id=?", (sid,)
        ).fetchone()

        if cancelled:
            if existing:
                conn.execute(
                    "UPDATE clients SET status='churned' WHERE gumroad_subscriber_id=?", (sid,)
                )
            continue

        if not existing:
            conn.execute(
                """INSERT INTO clients
                   (gumroad_subscriber_id, email, status, subscribed_at)
                   VALUES (?,?,?,?)""",
                (sid, email, "pending_onboarding", today)
            )
            new_ids.append(sid)
        elif existing[0] == "churned":
            # Resubscribed
            conn.execute(
                "UPDATE clients SET status='ready' WHERE gumroad_subscriber_id=?", (sid,)
            )

    conn.commit()
    log.info(f"Gumroad sync: {len(new_ids)} new, {len(subscribers)} total")
    return new_ids
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
python -m pytest tests/test_billing.py -v
```
Expected: 2 PASSED

- [ ] **Step 5: Commit**

```bash
git add agent2/content_mill_agent.py agent2/tests/test_billing.py
git commit -m "feat: agent2 Gumroad subscriber sync"
```

---

## Chunk 3: Onboarding Flow

### Task 4: Google Drive folder creation + welcome email

**Files:**
- Modify: `agent2/content_mill_agent.py` — implement `create_drive_folder()`, `send_email()`, `send_welcome_email()`
- Create: `agent2/tests/test_onboarding.py`

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_onboarding.py
import sqlite3, sys
from pathlib import Path
from unittest.mock import patch, MagicMock
sys.path.insert(0, str(Path(__file__).parent.parent))
from content_mill_agent import init_db, create_drive_folder, send_email

def test_create_drive_folder_returns_id():
    mock_service = MagicMock()
    mock_service.files.return_value.create.return_value.execute.return_value = {
        "id": "folder_abc"
    }
    folder_id = create_drive_folder(mock_service, "Alice — Content Mill", "alice@example.com")
    assert folder_id == "folder_abc"
    mock_service.files.return_value.create.assert_called_once()

def test_send_email_builds_message():
    with patch("content_mill_agent.smtplib.SMTP_SSL") as mock_smtp:
        mock_server = MagicMock()
        mock_smtp.return_value.__enter__.return_value = mock_server
        send_email(
            gmail_address="from@gmail.com",
            gmail_password="pass",
            to_address="to@example.com",
            subject="Test",
            body="Hello",
        )
    mock_server.login.assert_called_once()
    mock_server.send_message.assert_called_once()
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
python -m pytest tests/test_onboarding.py -v
```
Expected: FAIL

- [ ] **Step 3: Implement Drive + email helpers**

```python
from googleapiclient.discovery import build
from google.oauth2 import service_account

def get_drive_service(sa_json_path):
    creds = service_account.Credentials.from_service_account_file(
        sa_json_path,
        scopes=["https://www.googleapis.com/auth/drive"],
    )
    return build("drive", "v3", credentials=creds)

def get_sheets_service(sa_json_path):
    creds = service_account.Credentials.from_service_account_file(
        sa_json_path,
        scopes=["https://www.googleapis.com/auth/spreadsheets.readonly"],
    )
    return build("sheets", "v4", credentials=creds)

def create_drive_folder(drive_service, folder_name, share_with_email):
    """Create a Drive folder and share with client. Returns folder_id."""
    metadata = {
        "name": folder_name,
        "mimeType": "application/vnd.google-apps.folder",
    }
    folder = drive_service.files().create(body=metadata, fields="id").execute()
    folder_id = folder["id"]
    # Share with client as viewer
    drive_service.permissions().create(
        fileId=folder_id,
        body={"type": "user", "role": "reader", "emailAddress": share_with_email},
        sendNotificationEmail=False,
    ).execute()
    return folder_id

def send_email(gmail_address, gmail_password, to_address, subject, body):
    msg = MIMEMultipart()
    msg["From"]    = gmail_address
    msg["To"]      = to_address
    msg["Subject"] = subject
    msg.attach(MIMEText(body, "plain"))
    with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
        server.login(gmail_address, gmail_password)
        server.send_message(msg)

def send_welcome_email(cfg, client_email, client_name, drive_url, form_url):
    template = (TMPL_DIR / "welcome_email.txt").read_text()
    body = template.format(name=client_name or "there",
                           form_url=form_url, drive_url=drive_url)
    subject = "Welcome to Content Mill — let's get your content set up 🎬"
    send_email(cfg["gmail_address"], cfg["gmail_password"],
               client_email, subject, body)
    log.info(f"Welcome email sent to {client_email}")
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
python -m pytest tests/test_onboarding.py -v
```
Expected: 2 PASSED

- [ ] **Step 5: Implement run_onboarding()**

```python
GOOGLE_FORM_URL = "https://docs.google.com/forms/d/YOUR_FORM_ID/viewform"

def read_form_responses(sheets_service, spreadsheet_id):
    """Read Google Form responses from linked Sheet. Returns list of response dicts."""
    result = sheets_service.spreadsheets().values().get(
        spreadsheetId=spreadsheet_id,
        range="Form Responses 1!A:F",
    ).execute()
    rows = result.get("values", [])
    if len(rows) < 2:
        return []
    headers = [h.lower().replace(" ", "_") for h in rows[0]]
    return [dict(zip(headers, row)) for row in rows[1:]]

def run_onboarding(cfg, conn):
    """Daily 9AM job: pick up new subscribers, create Drive folders, send welcome emails."""
    start_ts = time.time()
    run_id = _start_run(conn, "onboarding")
    processed = 0

    try:
        new_ids = sync_gumroad_subscribers(conn, cfg["gumroad_token"], cfg["gumroad_product_id"])
        drive   = get_drive_service(cfg["google_sa_json"])
        sheets  = get_sheets_service(cfg["google_sa_json"])

        # Onboard newly discovered subscribers
        for sid in new_ids:
            client = conn.execute(
                "SELECT email, name FROM clients WHERE gumroad_subscriber_id=?", (sid,)
            ).fetchone()
            email, name = client
            display_name = name or email.split("@")[0]
            folder_name = f"{display_name} — Content Mill"
            try:
                folder_id = create_drive_folder(drive, folder_name, email)
                drive_url = f"https://drive.google.com/drive/folders/{folder_id}"
                conn.execute(
                    "UPDATE clients SET drive_folder_id=? WHERE gumroad_subscriber_id=?",
                    (folder_id, sid)
                )
                send_welcome_email(cfg, email, display_name, drive_url, GOOGLE_FORM_URL)
                processed += 1
            except Exception as e:
                log.warning(f"Onboarding failed for {email}: {e}")

        # Read Form responses → update client profiles
        responses = read_form_responses(sheets, cfg["form_sheet_id"])
        for resp in responses:
            email = resp.get("email_address", "")
            if not email:
                continue
            conn.execute(
                """UPDATE clients SET niche=?, tone=?, platform=?, target_audience=?,
                   status='ready' WHERE email=? AND status='pending_onboarding'""",
                (resp.get("niche"), resp.get("tone"),
                 resp.get("platform"), resp.get("target_audience"), email)
            )

        # Send reminders to clients pending > 3 days with no form response
        pending = conn.execute(
            """SELECT gumroad_subscriber_id, email, name, subscribed_at, form_reminder_sent_at
               FROM clients WHERE status='pending_onboarding'"""
        ).fetchall()
        for row in pending:
            sid, email, name, subscribed_at, reminder_sent = row
            if subscribed_at:
                days_waiting = (date.today() - date.fromisoformat(subscribed_at)).days
                if days_waiting >= 3 and not reminder_sent:
                    _send_form_reminder(cfg, email, name or email)
                    conn.execute(
                        "UPDATE clients SET form_reminder_sent_at=? WHERE gumroad_subscriber_id=?",
                        (str(date.today()), sid)
                    )

        conn.commit()
        _finish_run(conn, run_id, clients_processed=processed, status="ok")
    except Exception as e:
        _finish_run(conn, run_id, status="error", error_msg=str(e))
        raise

    _post_coastalclaw(cfg, "onboarding", "ok", processed, 0, int((time.time()-start_ts)*1000))

def _send_form_reminder(cfg, email, name):
    send_email(
        cfg["gmail_address"], cfg["gmail_password"], email,
        "Reminder: fill out your content preferences",
        f"Hi {name},\n\nJust a reminder to fill out your content preferences form so we can start generating your scripts:\n{GOOGLE_FORM_URL}\n\n— Content Mill"
    )
    log.info(f"Form reminder sent to {email}")
```

- [ ] **Step 6: Commit**

```bash
git add agent2/content_mill_agent.py agent2/tests/test_onboarding.py
git commit -m "feat: agent2 onboarding flow — Drive folder, welcome email, form response ingestion"
```

---

## Chunk 4: Content Generation

### Task 5: Ollama script generation

**Files:**
- Modify: `agent2/content_mill_agent.py` — implement `generate_scripts()`
- Create: `agent2/tests/test_generation.py`

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_generation.py
import sqlite3, sys, json
from pathlib import Path
from unittest.mock import patch, MagicMock
sys.path.insert(0, str(Path(__file__).parent.parent))
from content_mill_agent import init_db, generate_scripts

CLIENT = {
    "name": "Alice",
    "niche": "fitness",
    "tone": "motivational",
    "platform": "TikTok",
    "target_audience": "busy moms",
}
USED_TOPICS = ["Meal prep hacks", "Morning routines"]

MOCK_SCRIPTS = [
    {"title": "3 moves for busy moms", "hook": "No gym needed.", "body": "...", "cta": "Follow for more"},
    {"title": "10 min workout", "hook": "10 minutes changes everything.", "body": "...", "cta": "Comment 'ready'"},
    {"title": "Protein hack", "hook": "Stop buying protein bars.", "body": "...", "cta": "Follow for more"},
    {"title": "Sleep better", "hook": "Sleep is your superpower.", "body": "...", "cta": "Comment 'yes'"},
    {"title": "Mindset shift", "hook": "Your mindset is the problem.", "body": "...", "cta": "Follow for more"},
]

def test_generate_scripts_returns_5():
    with patch("content_mill_agent.requests.post") as mock_post:
        mock_resp = MagicMock()
        mock_resp.json.return_value = {
            "message": {"content": json.dumps(MOCK_SCRIPTS)}
        }
        mock_post.return_value = mock_resp
        scripts = generate_scripts(CLIENT, USED_TOPICS, "http://localhost:11434")
    assert len(scripts) == 5
    assert all("title" in s and "hook" in s for s in scripts)

def test_generate_scripts_retries_on_invalid_json():
    bad_resp = MagicMock()
    bad_resp.json.return_value = {"message": {"content": "not json"}}
    good_resp = MagicMock()
    good_resp.json.return_value = {"message": {"content": json.dumps(MOCK_SCRIPTS)}}
    with patch("content_mill_agent.requests.post", side_effect=[bad_resp, good_resp]), \
         patch("content_mill_agent.time.sleep"):
        scripts = generate_scripts(CLIENT, USED_TOPICS, "http://localhost:11434")
    assert len(scripts) == 5
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
python -m pytest tests/test_generation.py -v
```
Expected: FAIL

- [ ] **Step 3: Implement generate_scripts()**

```python
def generate_scripts(client, used_topics, ollama_url, retry=2):
    """Generate 5 video scripts via Ollama. Returns list of script dicts."""
    prompt_template = (TMPL_DIR / "script_prompt.txt").read_text()
    prompt = prompt_template.format(
        name=client["name"] or "",
        niche=client["niche"] or "",
        tone=client["tone"] or "engaging",
        platform=client["platform"] or "TikTok",
        target_audience=client["target_audience"] or "general audience",
        used_topics_last_30_days=", ".join(used_topics) if used_topics else "none",
    )

    for attempt in range(retry + 1):
        try:
            resp = requests.post(
                f"{ollama_url}/api/chat",
                json={
                    "model": "llama3.1:8b",
                    "messages": [{"role": "user", "content": prompt}],
                    "stream": False,
                },
                timeout=120,
            )
            content = resp.json()["message"]["content"]
            # Strip markdown code fences if present
            content = content.strip().strip("```json").strip("```").strip()
            scripts = json.loads(content)
            if isinstance(scripts, list) and len(scripts) >= 5:
                return scripts[:5]
            raise ValueError(f"Expected 5 scripts, got {len(scripts) if isinstance(scripts, list) else 'non-list'}")
        except Exception as e:
            log.warning(f"Script generation attempt {attempt+1} failed: {e}")
            if attempt < retry:
                time.sleep(10)

    raise RuntimeError(f"Ollama script generation failed after {retry+1} attempts")
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
python -m pytest tests/test_generation.py -v
```
Expected: 2 PASSED

- [ ] **Step 5: Commit**

```bash
git add agent2/content_mill_agent.py agent2/tests/test_generation.py
git commit -m "feat: agent2 Ollama script generation with retry"
```

---

### Task 6: Posting calendar PDF generation

**Files:**
- Modify: `agent2/content_mill_agent.py` — implement `make_calendar_pdf()`
- Create: `agent2/tests/test_calendar.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_calendar.py
import sys, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from content_mill_agent import make_calendar_pdf

SCRIPTS = [
    {"title": "Script 1", "hook": "Hook 1", "body": "Body 1", "cta": "CTA 1"},
    {"title": "Script 2", "hook": "Hook 2", "body": "Body 2", "cta": "CTA 2"},
    {"title": "Script 3", "hook": "Hook 3", "body": "Body 3", "cta": "CTA 3"},
    {"title": "Script 4", "hook": "Hook 4", "body": "Body 4", "cta": "CTA 4"},
    {"title": "Script 5", "hook": "Hook 5", "body": "Body 5", "cta": "CTA 5"},
]

def test_make_calendar_pdf_creates_file():
    with tempfile.TemporaryDirectory() as tmpdir:
        out_path = Path(tmpdir) / "calendar.pdf"
        make_calendar_pdf(
            scripts=SCRIPTS,
            platform="TikTok",
            week_of="2026-03-30",
            client_name="Alice",
            out_path=out_path,
        )
        assert out_path.exists()
        assert out_path.stat().st_size > 500  # non-empty PDF
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python -m pytest tests/test_calendar.py -v
```
Expected: FAIL

- [ ] **Step 3: Implement make_calendar_pdf()**

```python
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet

POSTING_SCHEDULES = {
    "TikTok":           ["Mon 7PM", "Wed 7PM", "Fri 7PM", "Sat 11AM", "Sun 9AM"],
    "Instagram Reels":  ["Tue 6PM", "Thu 6PM", "Fri 9PM", "Sat 10AM", "Sun 8PM"],
    "YouTube Shorts":   ["Mon 3PM", "Wed 3PM", "Fri 3PM", "Sat 12PM", "Sun 2PM"],
    "All":              ["Mon 7PM", "Wed 6PM", "Fri 7PM", "Sat 11AM", "Sun 9AM"],
}

def make_calendar_pdf(scripts, platform, week_of, client_name, out_path):
    schedule = POSTING_SCHEDULES.get(platform, POSTING_SCHEDULES["All"])
    doc = SimpleDocTemplate(str(out_path), pagesize=letter)
    styles = getSampleStyleSheet()
    elements = []

    elements.append(Paragraph(f"Content Calendar — Week of {week_of}", styles["Title"]))
    elements.append(Paragraph(f"Prepared for: {client_name} | Platform: {platform}", styles["Normal"]))
    elements.append(Spacer(1, 20))

    table_data = [["Day/Time", "Script Title", "Hook"]]
    for i, (slot, script) in enumerate(zip(schedule, scripts)):
        table_data.append([slot, script["title"], script["hook"][:60]])

    table = Table(table_data, colWidths=[100, 200, 220])
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1a1a2e")),
        ("TEXTCOLOR",  (0, 0), (-1, 0), colors.white),
        ("FONTNAME",   (0, 0), (-1, 0), "Helvetica-Bold"),
        ("GRID",       (0, 0), (-1, -1), 0.5, colors.grey),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f5f5f5")]),
        ("FONTSIZE",   (0, 0), (-1, -1), 10),
        ("PADDING",    (0, 0), (-1, -1), 6),
    ]))
    elements.append(table)
    doc.build(elements)
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python -m pytest tests/test_calendar.py -v
```
Expected: PASSED

- [ ] **Step 5: Commit**

```bash
git add agent2/content_mill_agent.py agent2/tests/test_calendar.py
git commit -m "feat: agent2 posting calendar PDF via ReportLab"
```

---

## Chunk 5: Weekly Delivery

### Task 7: Drive upload + weekly email delivery

**Files:**
- Modify: `agent2/content_mill_agent.py` — implement `upload_to_drive()`, `send_weekly_email()`, `deliver_to_client()`

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_generation.py`:

```python
def test_format_scripts_txt():
    from content_mill_agent import format_scripts_txt
    scripts = [{"title": "T1", "hook": "H1", "body": "B1", "cta": "C1"}]
    text = format_scripts_txt(scripts)
    assert "Script 1" in text
    assert "H1" in text
    assert "B1" in text
```

- [ ] **Step 2: Run test to verify it fails**

```bash
python -m pytest tests/test_generation.py::test_format_scripts_txt -v
```
Expected: FAIL

- [ ] **Step 3: Implement upload + delivery functions**

```python
from googleapiclient.http import MediaFileUpload

def format_scripts_txt(scripts):
    """Format 5 scripts as a clean text file for client delivery."""
    lines = []
    for i, s in enumerate(scripts, 1):
        lines += [
            f"── Script {i}: {s['title']} ──────────────────────────",
            f"HOOK: {s['hook']}",
            f"",
            s["body"],
            f"",
            f"CTA: {s['cta']}",
            f"",
        ]
    return "\n".join(lines)

def upload_to_drive(drive_service, parent_folder_id, file_path, file_name, mime_type):
    """Upload a file to Drive. Returns shareable URL."""
    metadata = {"name": file_name, "parents": [parent_folder_id]}
    media = MediaFileUpload(str(file_path), mimetype=mime_type)
    file = drive_service.files().create(
        body=metadata, media_body=media, fields="id,webViewLink"
    ).execute()
    return file["webViewLink"]

def deliver_to_client(cfg, conn, client, week_of):
    """
    Full delivery for one client:
    1. Generate scripts
    2. Make calendar PDF
    3. Create Drive subfolder, upload both files
    4. Send weekly email
    5. Log delivery
    """
    sid = client["gumroad_subscriber_id"]
    email = client["email"]
    name  = client["name"] or email.split("@")[0]
    used  = [r[0] for r in conn.execute(
        "SELECT topic FROM used_topics WHERE client_id=? AND used_on >= date('now','-30 days')",
        (sid,)
    ).fetchall()]

    # Generate
    scripts  = generate_scripts(client, used, cfg["ollama_url"])
    week_dir = OUT_DIR / sid / f"week_{week_of}"
    week_dir.mkdir(parents=True, exist_ok=True)

    # Write scripts.txt
    scripts_path = week_dir / "scripts.txt"
    scripts_path.write_text(format_scripts_txt(scripts))

    # Write calendar.pdf
    calendar_path = week_dir / "calendar.pdf"
    make_calendar_pdf(scripts, client["platform"] or "All", week_of, name, calendar_path)

    # Upload to Drive
    drive = get_drive_service(cfg["google_sa_json"])
    sub_metadata = {
        "name": f"Week of {week_of}",
        "mimeType": "application/vnd.google-apps.folder",
        "parents": [client["drive_folder_id"]],
    }
    sub_folder = drive.files().create(body=sub_metadata, fields="id").execute()
    sub_id = sub_folder["id"]

    upload_to_drive(drive, sub_id, scripts_path,  "scripts.txt",  "text/plain")
    drive_url = upload_to_drive(drive, sub_id, calendar_path, "calendar.pdf", "application/pdf")
    # Get parent folder URL
    folder_url = f"https://drive.google.com/drive/folders/{sub_id}"

    # Send email
    template = (TMPL_DIR / "weekly_email.txt").read_text()
    preview = scripts[0]["hook"][:120]
    body = template.format(name=name, week_of=week_of,
                           drive_url=folder_url, script1_preview=preview)
    send_email(cfg["gmail_address"], cfg["gmail_password"], email,
               f"Your content for week of {week_of} is ready 🎬", body)

    # Log delivery
    conn.execute(
        "INSERT INTO deliveries (client_id, week_of, drive_url, sent_at, status) VALUES (?,?,?,?,?)",
        (sid, week_of, folder_url, datetime.now().isoformat(), "delivered")
    )
    # Log used topics
    for s in scripts:
        conn.execute(
            "INSERT INTO used_topics (client_id, topic, used_on) VALUES (?,?,?)",
            (sid, s["title"], str(date.today()))
        )
    conn.commit()
    log.info(f"Delivered to {email} — week of {week_of}")
```

- [ ] **Step 4: Run the format_scripts_txt test**

```bash
python -m pytest tests/test_generation.py -v
```
Expected: All PASSED

- [ ] **Step 5: Commit**

```bash
git add agent2/content_mill_agent.py
git commit -m "feat: agent2 Drive upload + weekly email delivery"
```

---

### Task 8: run_weekly() orchestrator

**Files:**
- Modify: `agent2/content_mill_agent.py` — implement `run_weekly()`, run logging helpers

- [ ] **Step 1: Implement run logging helpers**

```python
def _start_run(conn, job):
    cur = conn.execute(
        "INSERT INTO runs (job, started_at, status) VALUES (?,?,?)",
        (job, datetime.now().isoformat(), "running")
    )
    conn.commit()
    return cur.lastrowid

def _finish_run(conn, run_id, clients_processed=0, deliveries_sent=0,
                status="ok", error_msg=None):
    conn.execute(
        """UPDATE runs SET finished_at=?, clients_processed=?, deliveries_sent=?,
           status=?, error_msg=? WHERE run_id=?""",
        (datetime.now().isoformat(), clients_processed, deliveries_sent,
         status, error_msg, run_id)
    )
    conn.commit()

def _post_coastalclaw(cfg, job, status, clients_processed, deliveries_sent, duration_ms):
    try:
        requests.post(f"{cfg['coastalclaw_url']}/api/agent-log", json={
            "agent": "agent2", "job": job, "status": status,
            "clients_processed": clients_processed,
            "deliveries_sent": deliveries_sent,
            "duration_ms": duration_ms,
        }, timeout=5)
    except Exception:
        pass
```

- [ ] **Step 2: Implement run_weekly()**

```python
def run_weekly(cfg, conn):
    """Monday 6AM job: generate + deliver content bundles to all ready clients."""
    start_ts = time.time()
    run_id = _start_run(conn, "weekly")
    week_of = str(date.today())
    delivered = 0
    failed = 0

    try:
        sync_gumroad_subscribers(conn, cfg["gumroad_token"], cfg["gumroad_product_id"])

        ready_clients = conn.execute(
            "SELECT * FROM clients WHERE status='ready'"
        ).fetchall()
        cols = [d[0] for d in conn.execute("SELECT * FROM clients LIMIT 0").description]

        for row in ready_clients:
            client = dict(zip(cols, row))
            try:
                deliver_to_client(cfg, conn, client, week_of)
                delivered += 1
            except Exception as e:
                log.warning(f"Delivery failed for {client['email']}: {e}")
                conn.execute(
                    "INSERT INTO deliveries (client_id, week_of, status) VALUES (?,?,?)",
                    (client["gumroad_subscriber_id"], week_of, "failed")
                )
                conn.commit()
                failed += 1

        status = "ok"
        if failed > 0:
            _alert_telegram(cfg, f"⚠️ Agent 2 weekly: {failed} deliveries failed, {delivered} succeeded")

        _finish_run(conn, run_id, clients_processed=len(ready_clients),
                    deliveries_sent=delivered, status=status)
    except Exception as e:
        _finish_run(conn, run_id, status="error", error_msg=str(e))
        _alert_telegram(cfg, f"🔴 Agent 2 weekly run failed: {e}")
        raise

    _post_coastalclaw(cfg, "weekly", "ok", len(ready_clients) if 'ready_clients' in dir() else 0,
                      delivered, int((time.time()-start_ts)*1000))

def _alert_telegram(cfg, message):
    token = cfg.get("telegram_token")
    chat  = cfg.get("telegram_chat")
    if not token or not chat:
        return
    try:
        requests.post(
            f"https://api.telegram.org/bot{token}/sendMessage",
            json={"chat_id": chat, "text": message},
            timeout=5,
        )
    except Exception:
        pass
```

- [ ] **Step 3: Run full test suite**

```bash
python -m pytest tests/ -v
```
Expected: All PASSED

- [ ] **Step 4: Commit**

```bash
git add agent2/content_mill_agent.py
git commit -m "feat: agent2 weekly orchestrator with per-client error isolation"
```

---

## Chunk 6: Scheduling & Final Integration

### Task 9: Windows Task Scheduler + final check

**Files:**
- Create: `agent2/setup_scheduler.bat`

- [ ] **Step 1: Create scheduler script**

```bat
@echo off
REM Run once as Administrator to register Agent 2 jobs
REM Usage: setup_scheduler.bat C:\path\to\python.exe C:\agent2

set PYTHON=%1
set AGENT_DIR=%2

REM Daily onboarding at 9:00 AM
schtasks /Create /TN "Agent2_Onboarding" ^
  /TR "%PYTHON% %AGENT_DIR%\content_mill_agent.py onboarding" ^
  /SC DAILY /ST 09:00 ^
  /RU SYSTEM /RL HIGHEST /F

REM Weekly content run every Monday at 6:00 AM
schtasks /Create /TN "Agent2_WeeklyRun" ^
  /TR "%PYTHON% %AGENT_DIR%\content_mill_agent.py weekly" ^
  /SC WEEKLY /D MON /ST 06:00 ^
  /RU SYSTEM /RL HIGHEST /F

echo Tasks created:
echo   Agent2_Onboarding  — daily 9:00 AM
echo   Agent2_WeeklyRun   — every Monday 6:00 AM
echo Verify in Task Scheduler: taskschd.msc
```

- [ ] **Step 2: Manual smoke test — onboarding job**

```bash
python content_mill_agent.py onboarding 2>&1 | head -30
```
Expected: Gumroad sync logged, no unhandled exceptions

- [ ] **Step 3: Register scheduler tasks**

```bash
# Run as Administrator in cmd.exe:
setup_scheduler.bat "C:\Users\John\AppData\Local\Programs\Python\Python314\python.exe" "C:\agent2"
schtasks /Query /TN "Agent2_Onboarding" /FO LIST
schtasks /Query /TN "Agent2_WeeklyRun" /FO LIST
```
Expected: Both tasks listed with status `Ready`

- [ ] **Step 4: Final test suite run**

```bash
python -m pytest tests/ -v --tb=short
```
Expected: All PASSED, 0 failures

- [ ] **Step 5: Push to GitHub**

```bash
git add agent2/setup_scheduler.bat
git commit -m "feat: agent2 Windows Task Scheduler setup"
git push origin main
```
