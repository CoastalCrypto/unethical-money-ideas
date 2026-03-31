# Agent 2 — Content Mill SaaS
**Date:** 2026-03-30
**Status:** Approved
**Owner:** Coastal Crypto

---

## Overview

A single Python script (`content_mill_agent.py`) that runs on two schedules — daily for onboarding new subscribers and weekly for content generation + delivery. Uses local Ollama to generate 5 short-form video scripts + a posting calendar for each paying client, delivered to a Google Drive folder + email every Monday. Zero human involvement after initial setup.

**Revenue model:** $150/month Gumroad subscription per client. 10 clients = $1,500/mo, 20 clients = $3,000/mo.

---

## Architecture

Two scheduled jobs, one file:

```
Schedule 1: Daily 9AM — Onboarding check
  Pull Gumroad subscribers → find new ones not in DB
  Create Drive folder → send welcome email + Google Form link
  Read Form responses via Sheets API → update client profile → set status = ready

Schedule 2: Monday 6AM — Weekly content run
  Sync Gumroad subscribers (detect churn/reactivation)
  For each ready client:
    Load profile (niche, tone, platform, audience, used_topics)
    Generate 5 scripts via Ollama (llama3.1:8b)
    Generate posting calendar PDF from template
    Upload to Drive subfolder "Week of [date]"
    Send weekly delivery email
    Log delivery to SQLite
  POST run summary to CoastalClaw :4747/api/agent-log
```

---

## File Layout

```
agent2/
  content_mill_agent.py       # single entry point — both jobs
  agent2.db                   # SQLite
  templates/
    welcome_email.txt
    weekly_email.txt
    script_prompt.txt         # Ollama prompt template
    calendar_template.pdf     # base PDF for posting schedule
  output/                     # local backup of all generated bundles
  .env
  requirements.txt
```

---

## SQLite Schema (agent2.db)

```sql
CREATE TABLE clients (
  gumroad_subscriber_id  TEXT PRIMARY KEY,
  email                  TEXT NOT NULL,
  name                   TEXT,
  niche                  TEXT,
  tone                   TEXT,   -- 'motivational'|'educational'|'entertaining'|'professional'
  platform               TEXT,   -- 'TikTok'|'Instagram'|'YouTube Shorts'|'All'
  target_audience        TEXT,
  drive_folder_id        TEXT,
  status                 TEXT DEFAULT 'pending_onboarding',
                                 -- 'pending_onboarding'|'ready'|'churned'
  subscribed_at          DATE,
  form_reminder_sent_at  DATE
);

CREATE TABLE used_topics (
  client_id  TEXT NOT NULL,
  topic      TEXT NOT NULL,
  used_on    DATE NOT NULL
);

CREATE TABLE deliveries (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id   TEXT NOT NULL,
  week_of     DATE NOT NULL,
  drive_url   TEXT,
  sent_at     DATETIME,
  status      TEXT DEFAULT 'pending'  -- 'pending'|'delivered'|'failed'|'pending_upload'
);

CREATE TABLE runs (
  run_id           INTEGER PRIMARY KEY AUTOINCREMENT,
  job              TEXT NOT NULL,     -- 'onboarding'|'weekly'
  started_at       DATETIME NOT NULL,
  finished_at      DATETIME,
  clients_processed INTEGER DEFAULT 0,
  deliveries_sent   INTEGER DEFAULT 0,
  status           TEXT DEFAULT 'running',
  error_msg        TEXT
);
```

---

## Content Generation

### Ollama Script Prompt Template

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

| | |
|---|---|
| **Model** | `llama3.1:8b` |
| **Time/client** | ~45 seconds |
| **Cost** | $0 (fully local) |

After each run, script titles are written to `used_topics` to prevent repeats in future weeks.

### Posting Calendar

Built from a static template — maps 5 scripts to platform-optimal posting times:

| Platform | Schedule |
|---|---|
| TikTok | Mon 7PM · Wed 7PM · Fri 7PM · Sat 11AM · Sun 9AM |
| Instagram Reels | Tue 6PM · Thu 6PM · Fri 9PM · Sat 10AM · Sun 8PM |
| YouTube Shorts | Mon 3PM · Wed 3PM · Fri 3PM · Sat 12PM · Sun 2PM |

Delivered as a PDF titled "Your Content Calendar — Week of [date]".

---

## Client Onboarding Flow

1. Daily 9AM job pulls Gumroad subscribers not in `clients` table
2. Create Google Drive folder: `"[ClientName] — Content Mill"` — share with client email (viewer)
3. Store `drive_folder_id` in SQLite
4. Send welcome email with Google Form link (4 questions: niche, tone, platform, audience)
5. Daily job reads new Google Form responses via Sheets API → updates client profile → sets `status = ready`
6. If no Form response after 3 days → send reminder email → log `form_reminder_sent_at`
7. Client picked up by next Monday run once `status = ready`

---

## Weekly Delivery Flow

Per client:
1. Create Drive subfolder: `"Week of [date]"`
2. Upload `scripts.txt` — 5 scripts formatted cleanly
3. Upload `calendar.pdf` — posting schedule
4. Get shareable folder URL
5. Send weekly email — subject: `"Your content for week of [date] is ready 🎬"`, body includes Drive link + 3-line preview of Script 1 hook

**Sent via:** Gmail SMTP with app password — free up to 500 emails/day, no SendGrid needed.

---

## Billing Sync (Gumroad)

Checked on every run:

| Event | Action |
|---|---|
| New subscriber | Add to `clients`, status = `pending_onboarding`, send welcome email |
| Cancelled | Set status = `churned`, skip on Monday runs, Drive folder kept |
| Payment failed | Gumroad retries automatically — agent skips if still unpaid on Monday |
| Resubscribed | Set status back to `ready`, same Drive folder reused |

---

## Error Handling

| Failure | Behaviour |
|---|---|
| Ollama timeout | Retry once after 10s → mark delivery `failed` → skip client this week → Telegram alert |
| Drive upload fails | Retry 3× → save bundle to `output/` → mark `pending_upload` → retry next day |
| Email bounces | Log bounced address → Drive still uploaded → flag in CoastalClaw log |
| Form not completed | Resend reminder after 3 days → skip from Monday run until complete |
| CoastalClaw offline | Log locally — agent continues unaffected |

**Principle:** a failure for one client never blocks other clients.

---

## Configuration (.env)

```env
# Gumroad
GUMROAD_ACCESS_TOKEN=...
GUMROAD_PRODUCT_ID=...

# Google
GOOGLE_SERVICE_ACCOUNT_JSON=path/to/service_account.json
GOOGLE_FORM_SPREADSHEET_ID=...

# Email (Gmail SMTP)
GMAIL_ADDRESS=...
GMAIL_APP_PASSWORD=...

# Ollama
OLLAMA_URL=http://localhost:11434

# CoastalClaw
COASTALCLAW_URL=http://localhost:4747

# Alerting
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...

# Pricing
SUBSCRIPTION_PRICE_USD=150
```

---

## Scheduling

| Job | Schedule | Tool |
|---|---|---|
| Onboarding check | Daily 9:00 AM | Windows Task Scheduler |
| Weekly content run | Every Monday 6:00 AM | Windows Task Scheduler |

---

## CoastalClaw Integration

| Endpoint | When | Payload |
|---|---|---|
| `POST :4747/api/agent-log` | After every run | `{ agent, job, status, clients_processed, deliveries_sent, duration_ms }` |

---

## Revenue Projection

| Clients | Monthly Revenue |
|---|---|
| 5 | $750 |
| 10 | $1,500 |
| 20 | $3,000 |
| 50 | $7,500 |

Weekly run takes ~6 minutes per client. 20 clients = ~2 hours total Monday morning.

---

## Dependencies

```
google-auth
google-api-python-client
ollama
reportlab                # PDF generation
requests
python-dotenv
sqlite3                  # built-in
smtplib                  # built-in
```

---

## Out of Scope (Phase 2)

- Thumbnail generation (DALL-E / Midjourney)
- Caption generation
- Client-facing dashboard to view/download bundles
- Automatic social media posting via Buffer/Later API
- Tiered pricing ($97 scripts-only / $150 scripts+calendar / $250 full service)
