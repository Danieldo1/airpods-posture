# Non-Technical README Implementation Plan

> **For a separate docs agent (not the walkthrough Codex task):** REQUIRED SKILL: Use `repo-user-docs` (`/Users/Daniel_1/.codex/skills/repo-user-docs/SKILL.md`). Write for someone who has never opened Xcode. Do **not** implement the in-app walkthrough. Do **not** commit unless the operator asks.

**Goal:** Make `README.md` a first-run guide for ordinary Mac users, and move today’s developer material to `docs/developer.md` so nothing is lost.

**Architecture:** One short user README at the repo root. One developer file that keeps Info.plist, build commands, detection math, and project layout. Every user-facing claim must be true in the current UI copy or settings defaults.

**Tech Stack:** Markdown only. No app code changes. No new dependencies.

## Operator prompt

Paste this as the docs-agent task. This plan file is the source of truth.

```xml
<task>
Implement docs/superpowers/plans/2026-09-06-nontechnical-readme.md in /Users/Daniel_1/Desktop/mac-posture.
Rewrite README.md for non-technical users and move the current developer content to docs/developer.md.
Follow the plan. Do not invent features. Do not edit Swift sources.
</task>

<completeness_contract>
Finish both files. README must be usable without knowing what Swift, IMU, or Info.plist are. docs/developer.md must still contain build, plist, detection, and layout so developers are not worse off.
</completeness_contract>

<action_safety>
No commits, no branches, no Swift/UI edits, no walkthrough implementation.
Do not delete technical facts — relocate them.
If the in-app How it works walkthrough is not in the tree yet, describe first-run from the actual UI (menu-bar icon, Set Neutral Posture, Options). Do not document a tour that does not exist.
</action_safety>
```

## Locked product decisions

| Decision | Value |
|---|---|
| User doc | `README.md` only. Do **not** create `docs/user-guide/` |
| Developer doc | `docs/developer.md` — cut/paste from the current README, then tidy headings |
| Audience of README | Someone who just downloaded or built AirPosture and wants to use it |
| Code in README | None, except the two install commands below |
| Tone | Plain, short paragraphs, numbered first-run steps |
| Formulas | None. No LaTeX. No pitch/roll/yaw |
| Walkthrough mention | Only if `Walkthrough.swift` / footer **How it works** already exist when you write. Otherwise omit |

### Commands allowed in README

```bash
make run
make install
```

Explain in a sentence that `make run` builds and opens the app, and `make install` puts it in `/Applications`. Do not document SwiftPM flags, module caches, or ColorSelector commit hashes in README.

---

## Global Constraints

- Evidence first: UI strings, settings defaults, and `README.md` as it exists today. Do not invent banner text, defaults, or hardware support.
- Compatible headphones (from current README): AirPods Pro, AirPods Max, AirPods 3 / 4, and other Apple headphones with spatial audio head tracking. Original AirPods and AirPods 2 stay Disconnected.
- macOS 14.0+ is a user requirement (say “macOS 14 Sonoma or later”).
- Privacy: processing is local; no accounts; analytics file may be mentioned in developer docs, not as a user task.
- If a behavior is not visible in code/copy, write “AirPosture does not show this in the app” or omit it. Do not guess.

### Defaults you may state (verify in `AirPostureSettings` / tracker if unsure)

| Thing | Default |
|---|---|
| Tracking | On |
| Desk / Sofa | Desk |
| Warning style | Glow |
| Early visual cue | On |
| Sound | Pop |
| Break reminders | Off |
| Sit-up chime | Off |
| Ignore slouch when I turn | On |
| Snooze Esc | 15 minutes during a warning overlay |

---

## File structure

- Create: `docs/developer.md` — current technical README, reorganized.
- Modify: `README.md` — user guide only, with a one-line link to `docs/developer.md`.
- Do **not** modify Swift, pbxproj, tests, or the walkthrough plan.

---

### Task 1: Inventory (do not write the README yet)

**Files to read (enough; do not dump the whole repo):**

- `README.md`
- `Sources/AirPostureMac/MenuBarView.swift`
- `Sources/AirPostureMac/AirPostureSettings.swift` (defaults and control titles)
- `Sources/AirPostureMac/AlertService.swift` (banner titles only)
- `Sources/AirPostureMac/PostureTrackingManager.swift` (`coachingCaption`, connection, calibrate)
- `Sources/AirPostureCore/BreakReminder.swift` (break banner titles)
- `Resources/Info.plist` (permission prompt wording)

If `Sources/AirPostureCore/Walkthrough.swift` exists, read it and mention **How it works** in README First 5 minutes.

- [ ] **Step 1: List every user-visible control and banner you will document**

Write the list in your working notes, not as a new repo file. Include: menu-bar icon, popover header, avatar, coach line, This week, History, Set Neutral Posture, Options groups, snooze, Quit, break countdown, overlays, Esc snooze.

- [ ] **Step 2: Confirm you will not document** IMU, ellipse math, α = 0.4, Swift 6.1, `CMHeadphoneMotionManager`, restricted entitlements, ColorSelector hashes.

---

### Task 2: Move developer content

**Files:**
- Create: `docs/developer.md`

Keep these sections from today’s README (retitle as needed):

1. Title + one-line what the app is
2. Requirements (including Swift / Command Line Tools)
3. Info.plist keys and the crash warning about `NSMotionUsageDescription`
4. Build & run (Swift Package + Xcode)
5. How detection works
6. Project layout
7. Privacy file path, analytics versions, sound fallback notes, ColorSelector provenance

Open with:

```markdown
# AirPosture for developers

This page is for building and changing AirPosture. Everyday use is in [README.md](../README.md).
```

- [ ] **Step 1: Create `docs/developer.md` with the relocated technical sections**
- [ ] **Step 2: Do not commit**

---

### Task 3: Rewrite `README.md`

**Files:**
- Modify: `README.md`

Replace the file with this outline. Keep each section short. Use the product name **AirPosture**. Use **Neutral Posture**, **Desk**, **Sofa**, **Glow**, and **Options** exactly as the UI does.

```markdown
# AirPosture

[2–3 sentences: menu-bar posture coach, uses compatible AirPods, nudges you when your head stays off the posture you set.]

## What you need

- Mac running macOS 14 Sonoma or later
- Compatible headphones (list)
- Permission for Motion & Fitness
- Optional: Notifications, Focus Status

## Install and open

[make run / make install, plus: always open the AirPosture app, not a raw binary. Mention the menu-bar icon and that there is no Dock icon.]

## First 5 minutes

1. Put on compatible AirPods and connect them to the Mac
2. Open AirPosture — look in the menu bar, not the Dock
3. Allow Motion & Fitness
4. Click the menu-bar icon
5. Sit how you want to hold yourself → Set Neutral Posture
6. What happens next: faint Glow, then sound + Sit up straight! banner after a few seconds
7. How it works replay — only if that button exists in the built app

## Using AirPosture

Task headings, not file names:

- The menu-bar icon (colors: orange through grace, red when a slouch is sustained)
- The avatar and one-line coach
- This week and History (plain language: green / orange / red / gray)
- Desk and Sofa
- Options (Monitoring, Breaks, Reminders, Appearance, Pause & feedback) — what a person would change, not how it is stored
- Break reminders (off until you turn them on)
- Snooze and Esc
- Quit

## If something’s wrong

At least these five:

1. Icon says Disconnected / Waiting for AirPods
2. Set Neutral Posture is dimmed
3. Motion access is off
4. No banner
5. Glow feels late or too strong

## Privacy

Local only. No account. No network. One sentence.

## Building from source

See [docs/developer.md](docs/developer.md).
```

Writing rules:

- “Click the AirPosture icon in the menu bar” not “open the `MenuBarExtra`”.
- “Sit up straight!” only if that is still the slouch banner title.
- Break banners: Time for a walk / Drink some water / Rest your eyes — only those titles, no Mix on the banner.
- Do not paste Swift, XML, or file trees in README.

- [ ] **Step 1: Write the new `README.md`**
- [ ] **Step 2: Read it once as a non-developer. Remove any leftover jargon**
- [ ] **Step 3: Do not commit**

---

### Task 4: Claim check

- [ ] **Step 1: For each README sentence that states a behavior, point to a file/string that proves it**
- [ ] **Step 2: Confirm `docs/developer.md` still has plist keys, `make test`, `make sound-probe`, detection steps, and project layout**
- [ ] **Step 3: Confirm no user-facing feature was invented (login, iPhone app, iCloud, accounts, cloud sync)**

---

## Out of scope

- Implementing or restyling the in-app walkthrough
- Screenshots (unless the operator later asks)
- App Store copy
- Translating the app
- Changing Swift UI strings to “match” the README
