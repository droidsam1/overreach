# ADR-0017: Versioned messages between the app and AI chat apps

- Status: accepted
- Date: 2026-11-19

## Context

The user wants to discuss their training with ChatGPT (mainly) or Claude, and then bring what they agree on
(routines, exercise settings, a training block) back into the app.

The obvious option, an MCP server, does not fit. ChatGPT and Claude on iOS only connect to **remote** MCP servers
reachable over HTTPS. An iPhone app cannot be one, and running one would need a backend holding the user's
training and health data. Overreach has no backend by design. Live two-way chat arrives in phase 4, through the
provider APIs (ADR-0006).

What does work on iOS without a backend:
- the share sheet;
- the clipboard (`PasteButton` reads it without a permission prompt);
- files, opened with "Open in" or from the Files app.

## Decision

The app and the chat app exchange **self-describing, versioned JSON messages** over those channels.

1. **App → AI: the context pack** (`overreach.context`).
   - It is raw data: sessions with notes, exercise settings, routines, profile and goal, check-ins, health metrics,
     and trends computed by the app (estimated 1RM per session, progression status).
   - It contains **no instructions**. The user asks the questions in the chat. "Ask AI" can add one optional first
     request after the data, which the user can edit there.
   - It is shared as text (share sheet or copy) or as a `.json` file.
2. **AI → App: import messages** (next step, issue #34). They use their own format names, for example
   `overreach.routines`, for what the AI proposes.
   - The app parses them from pasted text or a file.
   - It shows a preview, and gives back a correction prompt when something does not fit.
   - Each item carries an `id`, so importing the same message twice updates instead of duplicating.
3. **Versioning.**
   - Every message has `format` and `version`.
   - Adding an optional field keeps the version.
   - Renaming or removing a field, or changing its meaning or unit, raises it.
   - The app keeps reading every import version it has ever documented.
   - The context pack is built from its own types (`AIExchange`), not the domain's, so a domain refactor cannot
     change the format by accident.
4. **Privacy.** Data leaves the phone only when the user shares it, to the app they pick. The screen says that the
   pack includes their notes.

The field reference lives in `docs/ai-exchange.md` and is linked from the pack itself, so an assistant can read
it.

## Consequences

- It works today with ChatGPT and Claude, and with any other chat app that takes text or files.
- The user drives the conversation. The app never sends instructions it did not show.
- The flow is not automatic: there is a share step out and a paste or file step back. Shortcuts (App Intents)
  could automate it later.
- Two formats to maintain, with tests that pin their shape.
