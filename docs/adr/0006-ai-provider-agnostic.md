# 0006 — AI: shareable report first, provider-agnostic chat later

- **Status:** Accepted
- **Date:** 2026-11-16

## Context

The user already pays for ChatGPT. API usage is billed separately. We want AI help without locking into one
vendor, and without making AI responsible for the numbers.

## Decision

- Numbers (loads, baselines, readiness) are always computed by `Analytics`. AI only interprets them.
- **Prototype:** `Reports` renders a Markdown report (context, today, 30-day trends, recent sessions,
  check-ins, question). An "Ask ChatGPT" button opens the iOS share sheet with the report attached; the
  conversation continues in the ChatGPT (or Claude) app, covered by the user's subscription.
- **Phase 4:** in-app chat through an `LLMProvider` protocol in `AIKit`, with adapters for OpenAI (default),
  Anthropic and any OpenAI-compatible endpoint. The API key is stored in the Keychain; the model can call
  app-defined tools to fetch more history. A monthly spend estimate is shown in Settings.

## Consequences

- The prototype has zero AI cost and no API key handling.
- The same report content feeds both paths, so answers are consistent.
- Provider-specific features (e.g. tool-calling formats) must be mapped in each adapter.
