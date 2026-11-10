# UI Visual Polish Checklist

Companion to `reference/operate.md`. Run this after the operation checklist passes.

**Mandatory for `area:ui`, `area:dashboard`, `area:admin` lanes:** invoke `frontend-design` skill before writing the lane brief.
**Optional enrichment:** `web-design-guidelines` skill for broader design system context.

## Typography

- [ ] Font sizes follow the design system scale (no ad-hoc `px` values)
- [ ] Line-height set for readability (1.4–1.6 for body text)
- [ ] Heading hierarchy is consistent (h1 > h2 > h3 — no skipped levels)
- [ ] No all-caps body text; all-caps reserved for labels/badges only

## Spacing

- [ ] Spacing values come from the design token scale (4/8/12/16/24/32/48...)
- [ ] Consistent internal padding within card/panel components
- [ ] No hard-coded margin values that bypass the scale

## Colour

- [ ] All colours reference design tokens, not hex literals in component code
- [ ] Contrast ratio ≥ 4.5:1 for normal text, ≥ 3:1 for large text (WCAG AA)
- [ ] Interactive elements have a colour-independent hover/focus indicator (not colour alone)
- [ ] Error states use the system error colour token; not a one-off red

## Motion

- [ ] Transitions ≤ 200 ms for state changes (hover, focus, toggle)
- [ ] No animation on initial page load unless it communicates meaningful progress
- [ ] `prefers-reduced-motion` media query respected — animations disabled or slowed

## Accessibility minimums

- [ ] All images have `alt` text (empty `alt=""` for decorative images)
- [ ] Form inputs have associated `<label>` elements
- [ ] Interactive elements are keyboard-reachable and in logical tab order
- [ ] ARIA roles added only where native semantics are insufficient

---

> **Gate reminder:** Polish checklist does not replace the operation checklist in `reference/operate.md` — both must pass before a UI lane brief is considered complete.
