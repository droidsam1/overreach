Task: <!-- issue link (#94), design-doc task link, or "none — <reason>" for work outside the backlog -->

## What and why

<!-- What does this change and why is it needed? Link the issue: Closes #123 -->

## How to test

<!-- Steps, or the tests that cover it. -->

## Checklist

- [ ] Follows the dependency rules in `AGENTS.md` and the rules in `CODING_STANDARDS.md` (no feature → feature or feature → data-module imports)
- [ ] Tests added/updated for logic in `OverreachCore`
- [ ] SwiftUI previews for new or changed views
- [ ] Missing data handled gracefully (all metrics optional)
- [ ] User-facing strings localizable; Dynamic Type and VoiceOver checked
- [ ] `CHANGELOG.md` updated if user-visible
- [ ] If this PR completes a queued task, it closes the issue, updates the queue and links an issue for any remaining work
- [ ] Recommendation/evaluation rules researched and recorded in `docs/evidence.md` (ADR-0012)
- [ ] ADR added if this is an architectural decision
- [ ] No personal data, real exports or secrets included
