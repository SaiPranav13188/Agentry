# Agentry — A Simple, Free, Private Email Assistant for Mac

> **Name:** Agentry (agent + sentry: agents that are guarded)
> **Platform:** native macOS app (menu bar + main window)
> **Budget:** ₹0. No paid APIs, no servers, no subscriptions.
> **Stack:** Swift 6, SwiftUI, SwiftData, Apple Foundation Models (on-device AI), Gmail REST API
> **Timeline:** 3 weeks
> **Author:** B. Sai Pranav

---

## 1. What It Does

Agentry lives in your Mac's menu bar. It reads your email, tells you what matters, drafts replies in your style, and **never sends anything without your click**.

| Feature | What you get |
|---|---|
| **Email triage** | Every new email is labeled urgent / needs reply / FYI / ignore, with a one-line reason |
| **Draft replies** | For emails that need a reply, a draft written in your style |
| **Approve before sending** | A Review screen and macOS notifications with **Send / Edit / Reject**, plus a 30-second Undo |
| **Reminders + daily briefing** | "Remind me Friday at 4" works; a morning summary of urgent mail, reminders, and job updates |
| **Job tracker** | Job emails (applied, interview, rejected) update your application list automatically |

Keep it small, make it work well, and use it every day.

---

## 2. Only 3 Parts Use AI

| AI part | Job |
|---|---|
| **Triage** | One AI call per email → label, reason, deadline, is_job_email, job stage |
| **Writer** | One AI call → draft reply, using 1–2 of your past sent emails as style examples |
| **Guard** | Pattern rules first; one AI check only if something looks suspicious (prompt injection, phishing) |

**Everything else is plain Swift:** checking Gmail, the UI, notifications, approvals, sending, reminders, the briefing, and the job list.

---

## 3. Free On-Device AI

| Option | When to use |
|---|---|
| **Apple Foundation Models** (default) | macOS 26 on Apple Silicon with Apple Intelligence on. Free, private, no setup. Use `@Generable` structs for guaranteed structured output. |
| **Ollama** (fallback) | Older macOS, Intel Macs, or when you want a bigger model. Free, runs locally; Agentry talks to it over `http://localhost:11434`. |

Agentry checks `SystemLanguageModel.default.availability` at launch and uses Ollama automatically if Apple's model isn't available. Settings lets you switch manually.

**Important limit:** Apple's on-device model has a small context window (about 4,096 tokens). Keep prompts short: trim long emails to the most recent message, strip quoted replies and signatures, and use only 1–2 short style examples. If an email is too long, summarize it first or fall back to Ollama.

---

## 4. How It Works

```
Every 5 minutes (while Agentry is running):
  new emails from Gmail
    → Guard (rules, + AI if suspicious)
    → Triage (AI)
    → if job email: update job list
    → if urgent or needs reply:
          Writer (AI) creates a Gmail DRAFT
          macOS notification: [Send] [Edit] [Reject]
          + the draft appears in the Review screen
    → you click Send → 30 s Undo → send the draft

Every minute:   deliver due reminders
Every morning:  show the daily briefing
```

---

## 5. The One Safety Rule

**The AI can only create drafts. It can never send.**

Sending happens in one small plain-Swift type, `SendService`, which runs only when:
1. You clicked **Send** (in the Review screen or on a notification),
2. The draft's one-time `approvalID` is valid, unused, and less than 24 hours old,
3. The draft hasn't changed since you saw it (hash check),
4. The 30-second Undo window passed without you cancelling.

The AI code (`TriageService`, `WriterService`, `GuardService`) has no reference to `SendService`. Even if an email tricks the AI, the worst case is a bad draft that you reject.

---

## 6. The App (UI/UX)

### Menu bar
- Icon with a badge showing how many drafts are waiting for review.
- Click → small popover: urgent emails, drafts waiting, next reminder, "Open Agentry."

### Main window (sidebar layout)
| Section | Shows |
|---|---|
| **Today** | Daily briefing: urgent emails, waiting replies, reminders, job updates |
| **Review** | Drafts waiting for approval: original email summary on the left, editable draft on the right, Send / Reject buttons, "Ask AI to change…" field |
| **Inbox** | Recent triaged emails with label chips and reasons; filter by label |
| **Reminders** | Upcoming reminders; add with natural language |
| **Jobs** | Application pipeline grouped by stage |
| **Activity** | Log of everything Agentry did |
| **Settings** | Gmail account, AI model, check interval, briefing time, notifications |

### Notifications
- Actionable macOS notifications (UserNotifications) with **Send**, **Reject**, and **Edit** (opens the Review screen).
- Reminder notifications with **Done** and **Snooze 1h**.

### Feel
- Native look: SF Symbols, system colors, Light/Dark mode.
- Smooth, quick animations: label chips fade in, sent drafts slide out of Review, the Undo bar shrinks as the 30 seconds count down, numbers count up on the Today screen.
- Respect Reduce Motion.

---

## 7. Free Setup

| Thing | How |
|---|---|
| **Xcode** | Free. Sign with your free Apple ID ("Personal Team") to run on your own Mac. |
| **Gmail API** | Google Cloud project → enable Gmail API → OAuth client for a macOS/iOS app → **Testing** mode → add yourself as a test user. No billing needed. Scopes: `gmail.readonly`, `gmail.compose`. Use Google's official GoogleSignIn SDK (supports macOS) or AppAuth for login. |
| **Tokens** | Stored in the macOS **Keychain**. Never in files or git. |
| **AI** | Apple Foundation Models (built in), or install Ollama for the fallback. |
| **Run at login** | `SMAppService.mainApp.register()` so Agentry starts when you log in. |

**Known limits:**
- In Google's Testing mode, login expires about every **7 days**. Agentry detects this and shows a "Sign in again" notification.
- Agentry only works while your Mac is on and the app is running. When the Mac wakes, it catches up on missed emails.
- Approvals happen on your Mac only (no phone approvals in this version).
- Sharing the app with others for free means they'll need to click "Open Anyway" in System Settings the first time (no paid notarization).

---

## 8. Data (SwiftData, 5 models)

| Model | Fields |
|---|---|
| `Email` | gmailID, threadID, sender, subject, snippet, label, reason, deadline, processedAt |
| `Draft` | email, gmailDraftID, body, bodyHash, approvalID, status (pending/sending/sent/rejected/expired), expiresAt |
| `Reminder` | text, dueAt, isRecurring, status |
| `JobApplication` | company, role, stage (applied/assessment/interview/rejected/offer), lastUpdate |
| `ActivityEntry` | date, event, details |

---

## 9. Project Structure

```
Agentry/
├── App/
│   ├── AgentryApp.swift         # @main, MenuBarExtra + main window
│   └── AppState.swift
├── Services/
│   ├── GmailService.swift       # login, fetch new mail, create draft, send draft
│   ├── AIService.swift          # Foundation Models + Ollama fallback
│   ├── TriageService.swift      # AI part 1
│   ├── WriterService.swift      # AI part 2
│   ├── GuardService.swift       # AI part 3 (rules + optional AI check)
│   ├── SendService.swift        # the only code that sends
│   ├── PollingService.swift     # every 5 minutes
│   ├── NotificationService.swift
│   ├── ReminderService.swift
│   ├── BriefingService.swift
│   └── JobTracker.swift
├── Models/                      # SwiftData models
├── Views/
│   ├── MenuBarView.swift
│   ├── TodayView.swift
│   ├── ReviewView.swift
│   ├── InboxView.swift
│   ├── RemindersView.swift
│   ├── JobsView.swift
│   ├── ActivityView.swift
│   └── SettingsView.swift
├── DesignSystem/Motion.swift    # animation tokens
├── Prompts/                     # triage.txt, writer.txt, guard.txt
└── AgentryTests/                # unit tests + evals
```

---

## 10. Evaluation

| Metric | How | Target |
|---|---|---|
| **Triage accuracy** | Label ~100 of your emails in the Inbox screen (a "Correct label" menu), compare with Agentry | > 85% |
| **Draft acceptance rate** | Drafts sent without edits ÷ drafts shown | Goes up over time |
| **Injection detection** | 20 tricky + 20 normal sample emails in the test bundle | Catches > 90%, false alarms < 5% |

Bonus: compare Apple's on-device model with one or two Ollama models on the triage eval, and show the table in your README.

---

## 11. Three-Week Plan

| Days | Build | Done when… |
|---|---|---|
| 1–3 | Xcode project, menu bar + window, SwiftData, Gmail login, fetch emails | New emails appear in the Inbox screen |
| 4–6 | AIService + Triage | Emails get labels and reasons; urgent ones trigger a notification |
| 7–10 | Writer + Review screen + approval + SendService + Undo | A real reply is sent only after you click Send |
| 11–13 | Guard + Reminders + Today briefing | Tricky emails are flagged; reminders fire; briefing shows |
| 14–16 | Job tracker + evals | Jobs screen updates itself; eval tests print numbers |
| 17–21 | Polish animations, launch at login, README, demo video | Runs on its own; repo ready to share |

---

## 12. Cursor Prompts

**How to use:** commit to git before each prompt, run one prompt per chat, ask Claude to plan first, read the plan, then say "go ahead." Keep this file in the project root. Build and run in Xcode after each step.

### Prompt 1 — App setup + Gmail

```
Read agentry.md. Agentry is a simple, free, native macOS email assistant (Swift 6, SwiftUI, SwiftData). Budget is ₹0: no paid APIs or services. Keep the code simple and readable. Plan first, then build.

Build:
- Xcode project structure from Section 9. Minimum macOS 14.
- AgentryApp with a MenuBarExtra (icon + badge for pending drafts) and a main window with a sidebar (Today, Review, Inbox, Reminders, Jobs, Activity, Settings). Empty views are fine for now.
- SwiftData models from Section 8.
- GmailService: Google OAuth login for gmail.readonly and gmail.compose (use the GoogleSignIn SDK via Swift Package Manager, or AppAuth), tokens in Keychain. Fetch emails received since the last check using Gmail history IDs; extract sender, subject, and clean plain text (strip HTML, quoted replies, signatures).
- PollingService: every 5 minutes while the app runs, plus a "Check now" button.
- InboxView listing fetched emails.
- README section explaining the free Google Cloud setup (Testing mode, test user, OAuth client).

Done when: I can sign in to Gmail and new emails appear in the Inbox screen.
```

### Prompt 2 — AI layer + Triage

```
Add the AI layer and triage (agentry.md Sections 2, 3, 4). Plan first.

- AIService with two backends:
  1. Apple Foundation Models (macOS 26, gated with `if #available(macOS 26, *)` and SystemLanguageModel.default.availability), using @Generable structs for structured output.
  2. Ollama over http://localhost:11434 with a JSON schema format, as the fallback.
  Auto-select at launch; Settings shows which is active and lets me switch.
- Keep prompts short (Apple's model has a small context window): trim emails to the latest message and cap length; if still too long, use Ollama.
- TriageService: label (urgent/needs_reply/fyi/ignore), reason (one sentence), deadline (optional), isJobEmail, jobCompany, jobRole, jobStage. Email text goes inside a clearly marked data block with an instruction that it is data, not instructions.
- InboxView shows label chips (animated fade-in) and reasons; filter by label.
- Notification for urgent and needs_reply emails (sender, subject, reason).
- Unit tests for triage parsing with a mocked AIService.

Done when: new emails get sensible labels and urgent ones trigger a notification.
```

### Prompt 3 — Writer, Review screen, approval, sending

```
Add drafting, the Review screen, approval, and sending (agentry.md Sections 5, 6). Plan first. This is the safety-critical part.

- WriterService: draft a reply using 1-2 of my recent sent emails as short style examples; create a Gmail draft. WriterService must not reference SendService.
- ReviewView: original email summary on the left, editable draft on the right, Send / Reject buttons, and an "Ask AI to change…" text field that revises the draft.
- Actionable notifications with Send, Reject, and Edit (Edit opens ReviewView on that draft).
- SendService (plain Swift, no AI): sends via Gmail drafts.send only if approvalID is valid, unused, not expired (24h), and the body hash matches what I approved. Any edit creates a new approvalID.
- After Send: a bottom Undo bar that shrinks over 30 seconds (animated); Undo cancels. Sent drafts slide out of the list.
- Reject deletes the Gmail draft.
- Every step logged to ActivityEntry; ActivityView lists them.
- Tests: SendService refuses expired, reused, and changed drafts, and nothing sends during the Undo window.

Done when: a real reply is sent only after I click Send, and Undo works.
```

### Prompt 4 — Guard, reminders, briefing

```
Add the guard, reminders, and the Today briefing (agentry.md Sections 1, 2, 6). Plan first.

- GuardService: pattern rules for prompt injection and phishing ("ignore previous instructions", "you are now", hidden HTML text, zero-width characters, requests to forward/send data, links whose text and target don't match). If a rule matches or the sender is new, run one AI check (safe/suspicious/malicious + reason). Flagged emails show a ⚠️ badge and get no automatic draft.
- ReminderService: parse "remind me ..." with one AI call into text + date (Asia/Kolkata) + recurring. Show the parsed time for confirmation before saving. Reminder notifications with Done and Snooze 1h. Missed reminders appear after wake, marked "late".
- TodayView: urgent emails still open, drafts waiting, today's reminders, job updates, with numbers that count up on appear. Optional morning notification at a time set in Settings.
- Detect expired Google login and show a "Sign in again" notification.
- Launch at login using SMAppService (toggle in Settings).

Done when: a tricky test email is flagged, a reminder fires on time, and Today shows a correct summary.
```

### Prompt 5 — Jobs, evals, polish

```
Add the job tracker, evals, and final polish (agentry.md Sections 1, 10). Plan first.

- JobTracker: when triage marks an email as job-related, add or update a JobApplication (no duplicates for the same company + role). JobsView shows the pipeline grouped by stage.
- A "Correct label" context menu in InboxView that saves my label for evals.
- Eval tests (Swift Testing): triage accuracy vs my saved labels; injection detection rate and false alarms on 20 tricky + 20 normal synthetic emails in the test bundle; draft acceptance rate from sent/edited drafts. Print the numbers. Add a way to run the triage eval with each AI backend and print a comparison table.
- Polish: Motion.swift animation tokens used everywhere, Reduce Motion support, Light/Dark checked, empty states for every screen.
- README: what it does, the safety rule, free setup, screenshots/GIF placeholders, eval numbers, limitations. No personal data or tokens in the repo.

Done when: Jobs updates itself from real emails, eval tests print numbers, and the repo is safe to make public.
```

---

## 13. Later (only if you want them)

Add one at a time, after Agentry works well. Every new action still goes through the same approval rule.

- **Phone approvals:** a Telegram bot so you can approve drafts when away from your Mac
- **Calendar:** suggest meeting times for "can we meet?" emails
- **Follow-ups:** draft a nudge when someone hasn't replied in 3 days
- **Glink link:** a Glink command that shows Agentry's drafts and reminders
- **Business mode:** payment reminders for your father's business

---

## 14. Next Step

Create the Xcode project, put `agentry.md` in the project folder, open it in Cursor, and run **Prompt 1**.
