---
name: mvp-pre-push-review
description: >-
  Runs a focused pre-push / pre-commit code review for MVP-quality code: logic
  bugs, dead code, obvious security issues, and maintainability—without requiring
  unit tests or full production rigor. Use when the user asks for a code review
  before pushing, wants to verify changes before commit, or asks to check for
  bugs, dead code, or quality before shipping MVP features.
---

# MVP pre-push code review

## Scope (MVP)

**In scope:** Catch real problems cheaply—correctness, safety, clutter, and obvious foot-guns.

**Out of scope (unless asked):** Full test suites, formal architecture reviews, performance profiling, accessibility audits, localization.

---

## When invoked

1. Identify **what changed** (diff, files touched, or user-described scope).
2. Run through the **checklists** below in order.
3. Produce a **structured report** using the template at the end.
4. Prefer **actionable fixes** over generic advice; cite file/line when possible.

---

## 1. Correctness & bugs

- [ ] **Happy path** matches the intended behavior; edge cases (nil/empty, bad HTTP status, decode failures) are handled or consciously accepted.
- [ ] **Async / concurrency:** no obvious race, missing `await`, or main-thread UI updates from background (SwiftUI/UIKit).
- [ ] **Force unwraps / fatal paths:** `!`, `try!`—justify or replace with safe handling.
- [ ] **Error handling:** errors are not silently swallowed without a fallback or log in DEBUG; user-facing failures degrade gracefully.
- [ ] **Types & contracts:** API request/response shapes match server/client; renamed fields updated everywhere.

---

## 2. Dead code & clutter

- [ ] **Unused** types, functions, imports, assets, and commented-out blocks—remove or ticket.
- [ ] **Duplicate logic** that should be one helper (only if duplication is clear and risky).
- [ ] **Stale config:** wrong URLs, placeholder refs, or keys left from old backends.

---

## 3. Security & secrets (MVP bar)

- [ ] No **service role keys**, private API keys, or passwords in client code or committed files.
- [ ] **Public/anon keys** only where appropriate; note if exposure increases abuse risk (spam, quota).
- [ ] **URLs and env:** production vs dev endpoints are intentional.

---

## 4. Good practices (lightweight)

- [ ] **Naming** is clear; magic numbers/strings reduced or named.
- [ ] **Single responsibility:** large functions called out if they block understanding.
- [ ] **Comments** explain *why*, not what the code already says.
- [ ] **Consistency** with existing project patterns (naming, folders, error style).

---

## 5. Stack-specific hints (apply if relevant)

**Swift / iOS**

- Codable keys match JSON; optional vs required fields align with backend.
- `URLSession` / networking: timeouts, cancellation if applicable.

**Supabase Edge Functions (Deno)**

- Secrets read from env; no keys in source.
- CORS and methods match how the client calls the function.

**Web**

- User input escaped or parameterized where it hits HTML/SQL/APIs.

---

## 6. Optional quick passes

Only if time/value warrants:

- Grep for `TODO`, `FIXME`, `HACK` near changed code.
- Linter/compiler warnings on touched files.

---

## Report template

Use this structure in the reply:

```markdown
## MVP pre-push review: [short scope]

### Summary
[1–3 sentences]

### Blockers (fix before push)
- [ ] ...

### Should fix (high value)
- ...

### Nice to have
- ...

### Dead code / cleanup
- ...

### Security / secrets
- [Clear | Notes: ...]

### Tests
[MVP: skipped | Manual test suggestions: ...]
```

### Severity labels

- **Blocker** — Wrong behavior, leak, or break; fix before push.
- **Should fix** — Bug risk, confusion, or debt that is quick to address.
- **Nice to have** — Polish; can ship without.

---

## Principles

- **Be honest about uncertainty**—flag “verify by running X” instead of guessing.
- **MVP trade-offs are OK**—say what to defer *after* launch if scope is tight.
- **Small diffs** get lighter review; large refactors get extra attention to integration points.
