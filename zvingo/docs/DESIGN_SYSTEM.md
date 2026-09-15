# Zvingo Design System — Single Source of Truth

> **Status:** Normative. Every surface (Consumer app, Driver app, Merchant dashboard) MUST conform.
> If code disagrees with this document, the code is wrong.

Zvingo is a three-sided on-demand delivery platform. The three surfaces must feel like
one product built by one team. This document is the contract that makes that true.

---

## 0. Design principles (in priority order)

1. **Stupid-obvious navigation.** A first-time user must never wonder where they are, how
   they got there, or how to go back. Every screen answers: *Where am I? What can I do? How do I leave?*
2. **One primary action per screen.** Exactly one filled dark button. Everything else is
   secondary (outline), tertiary (text), or an icon affordance.
3. **Content first, chrome last.** Food photography, order status and money are the heroes.
   Borders, shadows and dividers are near-invisible.
4. **Motion explains, never decorates.** Every animation must communicate causality,
   continuity or state. If it doesn't, delete it.
5. **Calm by default, loud on purpose.** The palette is neutral. Color is a signal —
   green means good, amber means waiting, red means stop. Saturation is earned.
6. **Never a dead end.** No empty screen without an illustration, a sentence of
   explanation, and a button that moves the user forward.

---

## 1. Color

### 1.1 Brand

| Token | Hex | Use |
|---|---|---|
| `brand/green` | `#0A8F5B` | Identity: logo, brand moments, success states, driver "online", money-positive |
| `brand/green-dark` | `#076C45` | Hover/pressed on brand green |
| `brand/green-surface` | `#E9F8F1` | Tinted background behind brand content |
| `brand/lime` | `#D7F654` | **Accent only.** Highlights, badges, "new", progress fill. Never a full-width button. |
| `brand/lime-surface` | `#F4FBCF` | Tinted background behind lime accents |

### 1.2 Action (primary interactive color)

Transactional actions use **near-black**, not green. This is deliberate: it matches the
confident, low-chrome interaction language of modern delivery/mobility apps and keeps green
meaningful as a *semantic* signal rather than a button color.

| Token | Hex | Use |
|---|---|---|
| `action/default` | `#101210` | Filled primary buttons, selected states, active nav |
| `action/hover` | `#2A2C29` | Hover |
| `action/pressed` | `#050605` | Pressed |
| `action/disabled-bg` | `#E2E2DE` | Disabled fill |
| `action/disabled-fg` | `#999B96` | Disabled label |

### 1.3 Neutrals (shared 10-step ramp — identical across all three surfaces)

| Token | Hex |
|---|---|
| `neutral/0` | `#FFFFFF` |
| `neutral/50` | `#F7F7F5` |
| `neutral/100` | `#EFEFEC` |
| `neutral/200` | `#E2E2DE` |
| `neutral/300` | `#CDCDC7` |
| `neutral/400` | `#999B96` |
| `neutral/500` | `#737570` |
| `neutral/600` | `#555752` |
| `neutral/700` | `#383A37` |
| `neutral/800` | `#222421` |
| `neutral/900` | `#101210` |

**Roles:** `background` = `neutral/50` · `surface` = `neutral/0` · `surface-muted` = `neutral/100`
· `border` = `neutral/200` · `divider` = `neutral/200` · `text-primary` = `neutral/900`
· `text-secondary` = `neutral/600` · `text-tertiary` = `neutral/400` · `text-on-dark` = `neutral/0`

### 1.4 Semantic

| Token | Hex | Surface tint | Meaning |
|---|---|---|---|
| `success` | `#0A8F5B` | `#E9F8F1` | Delivered, paid, online, confirmed |
| `warning` | `#B96800` | `#FFF4DE` | Waiting, delayed, action needed soon |
| `error` | `#BA1A1A` | `#FFEDEA` | Failed, cancelled, destructive |
| `info` | `#246BCE` | `#EAF1FC` | Neutral informational |
| `rating` | `#F4A100` | — | Star fills only |
| `deal` | `#C9362B` | `#FFEFED` | Discounts, promo tags, price drops |

### 1.5 Hard rules

- **Never** use raw hex in a widget/component. Always reference the token layer
  (`AppColors.x` in Flutter, `var(--color-x)` / Tailwind class in the dashboard).
- Text on any background must meet **WCAG AA: 4.5:1** for body, **3:1** for text ≥18.66px bold / 24px regular.
  `text-tertiary` (`#999B96`) is **only** legal on `neutral/0` and `neutral/50`, and only for
  non-essential metadata.
- Never communicate state by color alone — always pair with an icon, a label, or both
  (colorblind users are ~8% of men).
- Maximum **three** accent colors visible in one viewport.

---

## 2. Typography

**Family:** Inter across all surfaces (dashboard: `next/font/google` Inter; Flutter: bundled Inter,
fallback Roboto). Numerals in money/time contexts use **tabular figures**
(`fontFeatures: [FontFeature.tabularFigures()]` / `font-variant-numeric: tabular-nums`)
so digits don't jitter as values update.

| Role | Size / Line height | Weight | Letter-spacing | Use |
|---|---|---|---|---|
| `display` | 32 / 38 | 800 | −0.6 | Hero numbers (earnings total, order total) |
| `h1` | 26 / 32 | 800 | −0.5 | Screen titles |
| `h2` | 21 / 27 | 700 | −0.4 | Section headers, restaurant name |
| `h3` | 17 / 23 | 700 | −0.2 | Card titles, menu item name |
| `body` | 15 / 22 | 400 | 0 | Default body copy |
| `body-strong` | 15 / 22 | 600 | 0 | Emphasis within body |
| `caption` | 13 / 18 | 500 | 0 | Metadata, ETA, distance, helper text |
| `overline` | 11 / 14 | 700 | +0.8, UPPERCASE | Section eyebrows, status chips |
| `button` | 15 / 20 | 700 | −0.1 | All button labels |

**Rules:** Never more than 3 sizes in one card. Never center-align paragraphs longer than
2 lines. Truncate with ellipsis at a fixed `maxLines` — never let text reflow the layout.

---

## 3. Spacing, radius, elevation

### 3.1 Spacing — 4pt grid. Only these values:
`2, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64`

- Screen horizontal padding: **16** (mobile), **24** (tablet ≥600), **32** (desktop ≥1024)
- Gap between cards in a list: **12**
- Gap between sections: **32**
- Inner card padding: **16**
- Minimum gap between a label and its control: **8**

### 3.2 Radius

| Token | Value | Use |
|---|---|---|
| `radius/sm` | 8 | Chips, tags, small badges |
| `radius/md` | 14 | Buttons, inputs, small cards |
| `radius/lg` | 20 | Cards, images, list tiles |
| `radius/xl` | 28 | Bottom sheets, modals, hero images |
| `radius/full` | 999 | Avatars, pills, FABs, toggles |

### 3.3 Elevation — shadow only, never Material `elevation`

| Token | CSS / Flutter |
|---|---|
| `shadow/sm` | `0 1px 2px rgba(16,18,16,0.04)` |
| `shadow/md` | `0 8px 24px rgba(16,18,16,0.08)` |
| `shadow/lg` | `0 20px 48px rgba(16,18,16,0.12)` |
| `shadow/dock` | `0 -4px 24px rgba(16,18,16,0.10)` (bottom nav / sticky footers only) |

Cards at rest use `shadow/sm` + a `neutral/200` hairline border. Raised/dragged/hovered
cards use `shadow/md`. Sheets and modals use `shadow/lg`. **Never stack shadows.**

---

## 4. Motion

### 4.1 Duration

| Token | ms | Use |
|---|---|---|
| `motion/instant` | 100 | Tap feedback, checkbox, toggle thumb |
| `motion/fast` | 180 | Hover, color change, chip select, icon swap |
| `motion/base` | 260 | Card enter, list stagger item, sheet snap |
| `motion/slow` | 400 | Page transition, sheet open/close, hero expand |
| `motion/deliberate` | 700 | Status-step progression, success celebration |

### 4.2 Easing

| Token | Curve | Use |
|---|---|---|
| `ease/standard` | `cubic-bezier(0.2, 0, 0, 1)` — Flutter `Curves.easeOutCubic` | Default for everything |
| `ease/enter` | `cubic-bezier(0.05, 0.7, 0.1, 1)` — `Curves.easeOutQuint` | Elements entering the screen |
| `ease/exit` | `cubic-bezier(0.3, 0, 1, 1)` — `Curves.easeInCubic` | Elements leaving the screen |
| `ease/spring` | Flutter `Curves.easeOutBack` / CSS `cubic-bezier(0.34,1.56,0.64,1)` | Playful confirmations only (added-to-cart, order placed) |

### 4.3 Required motion patterns

- **List entrance:** stagger children by **40ms**, each fading in + rising **12px** over
  `motion/base` with `ease/enter`. Cap the stagger at the 8th item (later items animate together).
- **Page transition:** forward = new page slides in from right 24px + fades, `motion/slow`.
  Back = reverse. Modal/sheet = slide from bottom with `ease/enter`.
- **Tap feedback:** every tappable surface scales to **0.985** over `motion/instant`. No exceptions.
- **Skeletons, not spinners.** Any load expected >300ms shows a shimmer skeleton matching the
  real content's layout. A bare `CircularProgressIndicator` on a full screen is a bug.
  Spinners are allowed only *inside* a button during submit.
- **Number changes** (cart total, earnings, ETA) animate by counting/cross-fading over
  `motion/base` — never hard-swap.
- **Status progression** (order tracking, delivery steps) animates the connector line filling
  and the node scaling in over `motion/deliberate`.
- **Success moments** (order placed, delivery completed, payout) get one deliberate
  celebration: a check that draws in with `ease/spring`. Once, not looping.

### 4.4 Accessibility

Respect reduced-motion (`MediaQuery.disableAnimations` / `prefers-reduced-motion`): replace
movement with a plain cross-fade at `motion/fast`. Never block interaction behind an animation.
Nothing flashes more than 3×/second.

---

## 5. Component contract

### 5.1 Buttons

| Variant | Fill | Label | Border | Height | Radius |
|---|---|---|---|---|---|
| Primary | `action/default` | `neutral/0` | none | 52 | `radius/md` |
| Secondary | transparent | `neutral/900` | 1px `neutral/200` | 52 | `radius/md` |
| Tertiary | transparent | `neutral/900` | none | 44 | `radius/md` |
| Destructive | `error` | `neutral/0` | none | 52 | `radius/md` |
| Icon | `neutral/100` | `neutral/900` | none | 44×44 | `radius/full` |

- Minimum touch target **48×48** everywhere, even if the visual is smaller.
- Loading state: label is replaced by an inline spinner, width is **locked** (no layout shift).
- Disabled buttons are never hidden — they are disabled with a visible reason nearby.
- Full-width primary buttons live in a sticky footer with `shadow/dock` and safe-area padding.

### 5.2 Cards

Surface `neutral/0`, `radius/lg`, `shadow/sm`, 1px `neutral/200` border, 16 padding.
Image-led cards: image is edge-to-edge at the top with the card's radius on the top corners only,
**16:9** for restaurants, **1:1** for menu items. Always `cached_network_image` /
`next/image` with a shimmer placeholder and a branded fallback on error — never a broken-image icon.

### 5.3 Inputs

Height 52, fill `neutral/100`, no border at rest, `radius/md`, 16 horizontal padding.
Focus: 1.5px `action/default` border + fill goes `neutral/0`. Error: 1.5px `error` border with
the message below in `caption`/`error` — **never** only a red border.
Labels sit above the field, never as a disappearing placeholder.

### 5.4 Navigation (the "stupid-easy" rules)

- **Bottom tab bar** is the spine of both mobile apps. Max **5** tabs, always visible on
  top-level screens, always labelled (icon-only bars are banned). Selected = `action/default`
  icon + 700 label. Unselected = `neutral/400`.
- Every non-top-level screen has a **back affordance in the top-left** and a **title** naming
  where you are. Never rely on swipe-back alone.
- Bottom sheets get a visible **drag handle** and close on scrim tap.
- Destructive or irreversible actions require a confirm sheet naming the consequence in plain
  language ("Cancel order? You'll be refunded $12.50 within 3 days.") — never just "Are you sure?".
- **Progressive disclosure:** the default path shows the minimum; advanced options live behind
  "More options". A first-time user should reach checkout in ≤4 taps from home.
- Persistent context bars: an active cart shows a sticky bottom bar on every browse screen;
  an in-progress order shows a sticky top banner with live ETA that taps into tracking.

### 5.5 Feedback & empty states

- Every empty list: illustration/icon + one-line title + one-line explanation + a primary action.
- Every error: what happened, in plain language, plus **Retry**. Never surface a raw exception
  or HTTP status to a user.
- Every mutation gets optimistic UI where safe, and a snackbar confirmation with **Undo** where reversible.
- Offline: a persistent, non-blocking banner — cached content stays readable.

---

## 6. Per-surface token bindings

| Surface | File | Mechanism |
|---|---|---|
| Consumer app | `consumer_app/lib/core/app_colors.dart`, `app_text_styles.dart`, `theme.dart`, `app_motion.dart`, `app_spacing.dart` | `AppColors.*`, `AppTextStyles.*`, `AppMotion.*`, `AppSpacing.*` |
| Driver app | `driver_app/lib/core/app_colors.dart`, `app_text_styles.dart`, `theme.dart`, `app_motion.dart`, `app_spacing.dart` | identical token names to consumer |
| Merchant dashboard | `merchant-dashboard/app/globals.css` `@theme` block | CSS custom properties → Tailwind v4 utilities |

**Token names are identical across surfaces.** A developer moving between the three apps
must not have to relearn names. Both Flutter apps' `app_colors.dart` expose the same
identifiers; only platform-idiomatic syntax differs.

---

## 7. Definition of "elite" (the review bar)

A screen ships only when all of these are true:

- [ ] Zero raw hex / magic numbers — tokens only
- [ ] Exactly one primary action
- [ ] Loading state is a layout-matched skeleton
- [ ] Error state has plain-language copy and Retry
- [ ] Empty state has illustration + explanation + action
- [ ] Entrance animation present and staggered
- [ ] All touch targets ≥48×48
- [ ] Text contrast passes AA
- [ ] Works at 320px width and at 200% text scale without overflow
- [ ] Back affordance present and labelled
- [ ] No hardcoded strings that should be dynamic; no `TODO` left in the widget tree
- [ ] No `onTap: () {}` / dead buttons / "coming soon" placeholders
