# 0024 — Explanations can link to curated further reading

- **Status:** Proposed
- **Date:** 2026-11-20

## Context

Every recommendation already says *why* and *how sure* (ADR-0012): a reason and an evidence level. Users who want
to understand the idea behind it ("why double progression?", "why rest today?", "what is a deload?") have nowhere
to go. The product owner wants a recommended reading next to the explanation, and values Fitness Revolucionario
(Marcos Vázquez) as a Spanish-language reference, especially where research is thin.

Popular articles age and sometimes disagree with current evidence. The November 2026 review
(`docs/evidence-review-2026-11.md`, §6) found two Fitness Revolucionario articles that contradict the register
(phase-based training by menstrual cycle; shorter rests for more hypertrophy) next to many that agree.

## Decision

1. **Readings hang off evidence keys.** A static catalogue maps an evidence key (e.g. `proximity-to-failure`) to
   0–3 readings. Each reading has: title, author or outlet, URL, language, kind (`study`, `review`, `article`),
   publication date and the date someone last read it against the register entry.
2. **Curated, never automatic.** A reading is added only after a person has read it and confirmed it agrees with
   the register entry. An article that disagrees is not linked, even from a trusted author. The register entry
   lists its readings so a changed conclusion (ADR-0012 §6) re-checks them too.
3. **One primary source, one plain-language source.** Where possible each key has an open-access study or review
   and one plain-language article in the user's language (Fitness Revolucionario for es/gl; an English explainer
   for en). Readings in another language are shown with their language.
4. **Shown on demand.** The reason text stays short. Its "why?" sheet adds a "Learn more" section with the
   readings, opened in the in-app browser. No tracking parameters, no prefetching, nothing sent about the user.
5. **Where it lives.** The catalogue is data in `PresentationKit` keyed by evidence key; models expose it with the
   reason; views only render it (ADR-0014). A test checks every catalogue key exists in `docs/evidence.md`.

## Consequences

- Users can go deeper without the app writing long texts, and the evidence level and the reading reinforce each
  other.
- Links rot: the catalogue needs a periodic check (a script that reports non-200 URLs).
- Curation costs time, and some keys (deloads, illness) will only have primary sources in Spanish for now.
- Linking to an author is not an endorsement of everything they publish; the register stays the source of truth.
