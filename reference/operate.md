# UI Operation Checklist

A lane brief for any UI lane must specify all items below before the lane starts. Missing items = incomplete brief.

## Loading state

- [ ] Skeleton or spinner shown while data is in-flight (prefer skeleton for content-shaped areas, spinner for actions)
- [ ] No layout shift when data arrives — reserve space upfront
- [ ] Infinite spinner blocked: set a timeout and fall through to the error state

## Empty state

- [ ] Zero-data view has a heading, one-line explanation, and a primary action (e.g. "No results — try a different filter")
- [ ] Empty ≠ loading: the two states must be visually distinct
- [ ] Empty table/list does not collapse to zero height

## Error state

- [ ] Error message names the failure in plain language (not "An error occurred")
- [ ] Retry action is present and labelled ("Try again" or equivalent)
- [ ] Error does not expose stack traces or internal identifiers to the user

## Interactive states — all controls

For every button, input, select, toggle, link, and card in the brief:

- [ ] **Default** — resting appearance defined
- [ ] **Hover** — distinct visual feedback (not just cursor change)
- [ ] **Focus** — visible focus ring for keyboard navigation
- [ ] **Selected / active** — clearly distinct from default
- [ ] **Disabled** — reduced opacity or greyed out; cursor: not-allowed
- [ ] **Busy** — spinner or progress indicator replaces the label; click disabled while busy

## Mobile layout

- [ ] Breakpoint specified (e.g. < 768 px)
- [ ] Touch target minimum 44 × 44 px for all interactive elements
- [ ] No horizontal scroll on 375 px viewport
- [ ] Stacked or single-column where multi-column is specified for desktop

## Desktop layout

- [ ] Breakpoint specified (e.g. ≥ 768 px), OR explicit note: "mobile-only, hidden on desktop"
- [ ] Maximum content width defined to prevent over-wide lines on large screens
- [ ] Multi-column or side-by-side layout specified where applicable

---

> **Gate reminder:** The foreman must invoke `ui-taste` and confirm all items above are addressed in the lane brief before `lane start`. See `docs/agents/foreman.md` Stage 2 hard gate.
