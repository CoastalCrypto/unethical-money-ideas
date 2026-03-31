# Agent 3 — Lead Brokerage
**Date:** 2026-03-30
**Status:** Approved
**Owner:** Coastal Crypto

---

## Overview

Two Python scripts (`lead_scraper.py` + `reply_monitor.py`) that run on separate schedules. The scraper finds local businesses with weak online presence via Google Places, extracts contact emails via Playwright, scores fit with Ollama, and drip-emails a 3-step sequence. The monitor polls Gmail IMAP every 4 hours, classifies replies with Ollama, and delivers a lead card PDF + invoice template to the operator on every hot reply. Zero human involvement until a lead says yes.

**Revenue model:** Operator sells content packages ($300–$800/mo) to businesses that reply interested. Agent handles all prospecting and qualification.

---

## Architecture

Two independent scripts, one database:

```
Schedule 1: Daily 4AM — lead_scraper.py
  Pull Google Places results (geo × niche, rating 3.5–4.3)
  Playwright email extraction (homepage + /contact)
  Ollama fit scoring (llama3.1:8b) — skip score < 3
  Insert new prospects → SQLite
  Send Day 0 email to new qualified prospects
  Send Day 3 / Day 7 follow-ups to prospects in sequence
  POST run summary to CoastalClaw :4747/api/agent-log

Schedule 2: Every 4 hours — reply_monitor.py
  Poll Gmail IMAP for replies to sent sequences
  Ollama sentiment classification (interested/not_interested/unsubscribe)
  On interested → generate lead card PDF + invoice template → email operator
  On unsubscribe → mark do_not_contact, stop sequence
  POST run summary to CoastalClaw :4747/api/agent-log
```

---

## File Layout

```
agent3/
  lead_scraper.py           # scrape + enrich + email sequences
  reply_monitor.py          # IMAP poll + classify + lead card delivery
  agent3.db                 # SQLite
  templates/
    email_day0.txt          # cold pitch
    email_day3.txt          # follow-up
    email_day7.txt          # final nudge
    lead_card_template.py   # ReportLab PDF generator
    invoice_template.py     # ReportLab invoice generator
  output/                   # local copies of generated lead cards
  .env
  requirements.txt
```

---

## SQLite Schema (agent3.db)

```sql
CREATE TABLE prospects (
  place_id       TEXT PRIMARY KEY,
  name           TEXT NOT NULL,
  email          TEXT,
  phone          TEXT,
  website        TEXT,
  geo            TEXT NOT NULL,
  niche          TEXT NOT NULL,
  rating         REAL,
  fit_score      INTEGER,          -- Ollama 1–5
  fit_reason     TEXT,
  status         TEXT DEFAULT 'pending_email',
                                   -- 'pending_email'|'sequence_active'
                                   -- |'replied_interested'
                                   -- |'replied_not_interested'
                                   -- |'do_not_contact'|'converted'
  scraped_at     DATE NOT NULL
);

CREATE TABLE emails_sent (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  place_id       TEXT NOT NULL,
  sequence_day   INTEGER NOT NULL,  -- 0, 3, 7
  sent_at        DATETIME NOT NULL,
  message_id     TEXT               -- Gmail Message-ID for reply threading
);

CREATE TABLE replies (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  place_id       TEXT NOT NULL,
  received_at    DATETIME NOT NULL,
  snippet        TEXT,
  sentiment      TEXT,              -- 'interested'|'not_interested'|'unsubscribe'
  lead_card_sent INTEGER DEFAULT 0
);

CREATE TABLE runs (
  run_id          INTEGER PRIMARY KEY AUTOINCREMENT,
  job             TEXT NOT NULL,    -- 'scrape'|'email'|'monitor'
  started_at      DATETIME NOT NULL,
  finished_at     DATETIME,
  prospects_added INTEGER DEFAULT 0,
  emails_sent     INTEGER DEFAULT 0,
  replies_found   INTEGER DEFAULT 0,
  status          TEXT DEFAULT 'running',
  error_msg       TEXT
);
```

---

## Scraping & Enrichment

### Source — Local Business Contacts

| | |
|---|---|
| **API** | Google Places Text Search |
| **Query pattern** | `"web design Dallas TX"`, `"social media agency Houston TX"` |
| **Filter** | Rating 3.5–4.3 — needs help, not already polished |
| **Fields** | name, address, phone, website, rating, place_id |
| **Email extraction** | Playwright visits homepage + `/contact` — regex for mailto + visible email patterns |
| **Rate limit** | 3 req/sec (Places), 1 req/5sec (Playwright) |

### Ollama Fit Scoring

```
Score this business 1–5 for content agency fit:
Name: {name}
Rating: {rating}
Category: {category}
Website snippet: {website_text_snippet}

5 = clearly needs content help, small team, service business
1 = has in-house marketing, large brand, or irrelevant niche

Return JSON: {"score": N, "reason": "..."}
```

| | |
|---|---|
| **Model** | `llama3.1:8b` |
| **Threshold** | Skip score < 3 |
| **Fallback** | Ollama offline → include all scraped prospects with `fit_score = NULL` |

---

## Email Sequences

### Templates

| Day | Subject | Angle |
|-----|---------|-------|
| 0 | `Quick question about your content` | Noticed a gap, share what's working for similar businesses |
| 3 | `One thing that doubled bookings for [niche] businesses` | Social proof + soft pitch, asks for 15 min |
| 7 | `Last one from me` | Final nudge, offer free audit to lower friction |

All emails personalized with `{business_name}`, `{niche}`, `{city}`.

**Sent via:** Gmail SMTP with app password — free up to 500/day.

**Sequence enforcement:** 3-day gaps checked against `emails_sent` table. No email sent twice to same address. Sequence stops on any reply (any sentiment).

### Ollama Reply Classification

```
Classify this email reply sentiment:
Subject: {subject}
Body: {body}

Options: interested / not_interested / unsubscribe

Return JSON: {"sentiment": "...", "reason": "..."}
```

---

## Lead Card Delivery

When `reply_monitor.py` classifies a reply as `interested`, it generates and emails the operator:

**Lead Card PDF (ReportLab):**
```
[Business Name] — Lead Card
Rating: 4.1 ★  |  Niche: HVAC  |  City: Dallas TX
Contact: owner@hvacbiz.com  |  Phone: (214) 555-0100
Fit Score: 4/5 — "Small team, no social presence, service business"
Reply snippet: "Yes, we've been looking for someone..."
Suggested pitch: Content package for trades businesses — $500/mo
```

**Invoice Template PDF (ReportLab):** Pre-filled with business name, suggested package price, operator payment details. Operator edits and sends.

**Operator email subject:** `Hot lead: [Business Name] — [City] [Niche]`

---

## Error Handling

| Failure | Behaviour |
|---------|-----------|
| Google Places rate limit | Exponential backoff (2s, 4s, 8s) → skip geo this run → continue others |
| Email extraction fails | Log, mark `email = NULL`, skip from email sequence |
| Ollama offline | Skip fit scoring → include all prospects with `fit_score = NULL` |
| Gmail SMTP reject | Retry 2× → mark failed → retry next scheduled run |
| Reply IMAP poll fails | Log warning → continue → retry next 4-hour cycle |
| CoastalClaw offline | Log locally — agent continues unaffected |

**Principle:** scraper failure never blocks emailer; emailer failure never blocks monitor.

---

## Configuration (.env)

```env
# Google
GOOGLE_PLACES_API_KEY=...

# Email (Gmail SMTP + IMAP)
GMAIL_ADDRESS=...
GMAIL_APP_PASSWORD=...

# Operator delivery
OPERATOR_EMAIL=...

# Ollama
OLLAMA_URL=http://localhost:11434

# CoastalClaw
COASTALCLAW_URL=http://localhost:4747

# Alerting
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...

# Targets
TARGET_GEOS=Dallas TX,Houston TX,Austin TX
TARGET_NICHES=HVAC,plumbing,roofing,landscaping,web design
```

---

## Scheduling

| Job | Schedule | Tool |
|-----|----------|------|
| `lead_scraper.py` | Daily 4:00 AM | Windows Task Scheduler |
| `reply_monitor.py` | Every 4 hours (6AM, 10AM, 2PM, 6PM) | Windows Task Scheduler |

---

## CoastalClaw Integration

| Endpoint | When | Payload |
|---|---|---|
| `POST :4747/api/agent-log` | After every run | `{ agent, job, status, prospects_added, emails_sent, replies_found, duration_ms }` |

---

## Revenue Model

Agent qualifies leads. Operator closes and delivers content packages.

| Package | Price |
|---------|-------|
| Scripts only | $300/mo |
| Scripts + calendar | $500/mo |
| Full content service | $800/mo |

Conversion rate target: 1 close per 50 prospects contacted.

---

## Dependencies

```
playwright          # email extraction
requests            # Google Places API
sqlite3             # built-in
python-dotenv       # .env loading
ollama              # fit scoring + reply classification
reportlab           # lead card + invoice PDF generation
smtplib             # built-in — Gmail SMTP
imaplib             # built-in — Gmail IMAP reply polling
```

---

## Out of Scope (Phase 2)

- CRM dashboard to view prospect pipeline
- Auto-scheduling discovery calls via Calendly API
- SMS sequences via Twilio
- Multi-operator routing (assign leads to team members)
