# Habit Loop — Design System

Dual-theme design system for the Habit Loop Flutter app. Every value below is
implemented in code; this document is the reference, not a parallel spec.

| Layer | File |
| --- | --- |
| Color tokens, accent swatches | `lib/core/theme/app_colors.dart` |
| Type scale, spacing, radii, motion | `lib/core/theme/app_typography.dart` |
| `ThemeData` assembly for both modes | `lib/core/theme/app_theme.dart` |
| Shared components | `lib/widgets/` |

Widgets never branch on `Brightness` themselves. They read semantic tokens from
`AppPalette.of(context)`, which is registered as a `ThemeExtension`, so a single
widget renders correctly in both themes with no conditional styling.

> **Flat and calm.** Two rules, both for eye comfort, and both binding on any
> new component:
>
> **No glow.** Nothing emits light: no colored shadows bleeding an accent
> outward, no blurred duplicate strokes behind rings, no pulsing halos, no
> radial accent washes.
>
> **No chromatic gradients.** No fill ramps between two hues — not on banners,
> buttons, hero headers, avatar rings, progress rings or progress bars. One
> solid accent per surface. The only ramps left in the app are achromatic: the
> near-monochrome page wash and the white-over-midnight sheen that gives a
> translucent card its material.
>
> Depth comes from neutral (near-black, low-opacity) elevation shadows;
> emphasis comes from fill, rim color, rim weight, size and type weight.

---

## 1. Color

### 1.1 Dark theme — "Midnight glass"

Rich midnight-navy canvas, translucent glass surfaces, vivid accents that carry
by saturation alone — never by bloom.

| Token | Hex | Role |
| --- | --- | --- |
| `canvas` | `#0F172A` | Page background |
| `canvasTop` | `#131E36` | Top of the ambient wash |
| `canvasBottom` | `#080D19` | Bottom of the wash (near-OLED) |
| `surface` | `#16213A` | Opaque card fill |
| `surfaceHigh` | `#1E2B47` | Raised fill, inputs, popups |
| `surfaceGlass` | `#FFFFFF` @ 5% | Glass card fill (gradient bottom) |
| `surfaceGlassHi` | `#FFFFFF` @ 10% | Glass card fill (gradient top) |
| `navGlass` | `#16213A` @ 80% | Floating nav bar, over a live blur |
| `stroke` | `#FFFFFF` @ 10% | Hairline rim |
| `strokeStrong` | `#FFFFFF` @ 20% | Emphasized rim |
| `textPrimary` | `#F1F5F9` | Headings, body |
| `textSecondary` | `#94A3B8` | Supporting copy |
| `textTertiary` | `#64748B` | Overlines, meta, disabled |
| `accent` | `#22D3EE` | Primary — cyan |
| `accentAlt` | `#A78BFA` | Secondary — violet |
| `success` | `#34D399` | Emerald |
| `warning` | `#FBBF24` | Amber — streaks, extensions |
| `danger` | `#FB7185` | Rose — missed days, destructive |
| `shadow` | `#000000` @ 40% | Ambient card shadow |

### 1.2 Light theme — "Porcelain"

Crisp near-white canvas, solid elevated cards, saturated-but-deep accents that
hold contrast on white. Frosted glass is deliberately **not** used here — a
translucent white card over a near-white page reads as mud.

| Token | Hex | Role |
| --- | --- | --- |
| `canvas` | `#F8FAFC` | Page background |
| `canvasTop` | `#FFFFFF` | Top of the ambient wash |
| `canvasBottom` | `#EEF2F7` | Bottom of the wash |
| `surface` | `#FFFFFF` | Card fill |
| `surfaceHigh` | `#F1F5F9` | Inputs, raised fill |
| `navGlass` | `#FFFFFF` @ 95% | Floating nav bar |
| `stroke` | `#E2E8F0` | Hairline rim |
| `strokeStrong` | `#CBD5E1` | Emphasized rim |
| `textPrimary` | `#0F172A` | Headings, body |
| `textSecondary` | `#475569` | Supporting copy |
| `textTertiary` | `#94A3B8` | Overlines, meta, disabled |
| `accent` | `#0891B2` | Primary — deep cyan |
| `accentAlt` | `#7C3AED` | Secondary — deep violet |
| `success` | `#059669` | Emerald |
| `warning` | `#D97706` | Amber |
| `danger` | `#E11D48` | Rose |
| `shadow` | `#0F172A` @ 8% | Soft elevation shadow |

### 1.3 Habit accent swatches

Each swatch is defined **once per theme**. A habit stores the dark value as its
canonical id; `AppAccents.resolve()` swaps in the light tone when the theme
flips, so the same habit is bright on midnight and solid on porcelain.

| Name | Light | Dark |
| --- | --- | --- |
| Cyan | `#0891B2` | `#22D3EE` |
| Emerald | `#059669` | `#34D399` |
| Violet | `#7C3AED` | `#A78BFA` |
| Amber | `#D97706` | `#FBBF24` |
| Rose | `#E11D48` | `#FB7185` |
| Sky | `#2563EB` | `#60A5FA` |
| Lime | `#65A30D` | `#A3E635` |
| Orange | `#EA580C` | `#FB923C` |

Habits created before this palette existed still work: an unrecognised stored
color is nudged 18% lighter on midnight and 12% deeper on porcelain.

---

## 2. Typography

**Outfit** (geometric, confident) for display and headings; **Inter** (tall
x-height, superb at 12–15px on device) for UI and body. Both are bundled as
variable fonts under `assets/fonts/`, so the app never reaches the network for
type. Counters and percentages use `FontFeature.tabularFigures()` so digits
don't jitter while they animate.

| Role | Family | Size / Line | Weight | Tracking | Used for |
| --- | --- | --- | --- | --- | --- |
| `displayLarge` | Outfit | 40 / 1.10 | 700 | −1.2 | Reserved hero numerals |
| `displayMedium` | Outfit | 32 / 1.15 | 700 | −0.8 | Sheet titles |
| `displaySmall` | Outfit | 28 / 1.20 | 700 | −0.6 | "0 / 2", habit name, note title |
| `headlineLarge` | Outfit | 24 / 1.25 | 700 | −0.5 | Screen titles (Today, Notes…) |
| `headlineMedium` | Outfit | 20 / 1.30 | 700 | −0.4 | Card headlines, preset numbers |
| `headlineSmall` | Outfit | 18 / 1.35 | 600 | −0.3 | Sub-screen titles |
| `titleLarge` | Inter | 17 / 1.35 | 700 | −0.3 | Habit card title, stat values |
| `titleMedium` | Inter | 15 / 1.40 | 600 | −0.1 | List row titles |
| `titleSmall` | Inter | 13 / 1.40 | 600 | 0 | Dense labels |
| `bodyLarge` | Inter | 16 / 1.55 | 400 | 0 | Note body, text fields |
| `bodyMedium` | Inter | 14 / 1.50 | 400 | 0 | Descriptions |
| `bodySmall` | Inter | 12.5 / 1.45 | 400 | 0 | Meta, captions |
| `labelLarge` | Inter | 14 / 1.20 | 600 | +0.1 | Buttons |
| `labelMedium` | Inter | 12 / 1.20 | 600 | +0.2 | Chips, nav labels |
| `labelSmall` | Inter | 10.5 / 1.20 | 700 | +0.9 | UPPERCASE section overlines |

### Geometry and motion

| Token | Value | Notes |
| --- | --- | --- |
| Spacing scale | 4 / 8 / 12 / 16 / 20 / 24 / 32 | 4pt base |
| `gutter` | 20 | Horizontal page margin |
| `navClearance` | 118 | Bottom padding so content clears the floating bar |
| Radii | sm 12 · md 18 · lg 24 · xl 32 · pill 999 | Cards use `lg`, controls `md` |
| `fast` | 160ms | Press-down, opacity swaps |
| `base` | 260ms | State changes, nav pill travel |
| `slow` | 420ms | Ring and progress-bar fills |
| `celebrate` | 1600ms | Confetti lifetime |
| `emphasized` | `easeOutCubic` | Default curve |
| `springy` | `easeOutBack` | Release, checkbox pop, color dots |

---

## 3. Components

| Component | File | Behaviour |
| --- | --- | --- |
| `GlassCard` | `widgets/glass_card.dart` | Primary surface. Dark: white gradient 10%→5% over midnight, 1px rim, neutral ambient shadow. Light: solid white, hairline rim, soft neutral shadow. Optional `accent` tints the rim; `highlighted` raises it to full accent at 1.4px. |
| `GlassBlur` | `widgets/glass_card.dart` | Real `BackdropFilter` (σ 22). Reserved for pinned chrome — a blur per list row is too expensive to scroll. |
| `TagChip` | `widgets/glass_card.dart` | Pill for streaks, day ranges, counts. Tinted wash + rim, or solid when `strong`. |
| `SectionHeader` | `widgets/glass_card.dart` | Uppercase overline + count badge + trailing action. |
| `Pressable` | `widgets/pressable.dart` | Universal press feedback: scale down over 160ms, spring back over 260ms, selection haptic. |
| `ProgressRing` | `widgets/progress_ring.dart` | Solid-accent arc, round caps, animated from the previous value, over a neutral track. |
| `ProgressBar` | `widgets/progress_ring.dart` | 6–8px solid-accent bar over a neutral track. |
| `Confetti` | `widgets/confetti.dart` | 90 particles, one ticker, painted into the root overlay and removed on completion. |
| `AppBackground` | `widgets/app_background.dart` | Quiet three-stop vertical canvas wash, achromatic — no accent light bleed. |

---

## 4. Navigation

Top tabs are gone. `AppShell` (`features/shell/app_shell.dart`) hosts an
`IndexedStack` — all four tabs keep their scroll position and state — under a
floating navigation bar:

- Pill container, 68pt tall, 32pt radius, 16pt side margins, floating 14pt above
  the safe-area inset so it sits in the natural thumb arc.
- Real backdrop blur behind a translucent fill; 1px rim.
- A **sliding accent pill** travels behind the active destination over 260ms
  `easeOutCubic` — the indicator moves, it doesn't cut.
- Active destination: filled icon, accent color, label at weight 700, icon
  lifted 6% of its height. Inactive: outlined icon, tertiary text.
- Width is `min(4 × 84, screenWidth − 32)`, and item widths are measured from
  the bar's inner constraints, so it never overflows on a narrow phone.

Destinations: **Today · To-Do · Notes · Settings**.

A contextual FAB rides 16pt above the bar and changes with the tab — "New habit"
on Today, "New note" on Notes, hidden on To-Do (which has inline capture) and
Settings. It scales to zero rather than popping out of existence.

---

## 5. Screens

### Screen 1 — Today dashboard (`features/today/today_screen.dart`)

```
┌──────────────────────────────────────────┐
│ ☀ Good afternoon              ╭────────╮ │  greeting + time icon
│ Habit Loop                    │ avatar │ │  headlineLarge
│ Friday, September 25          ╰────────╯ │  bodySmall / tertiary
│                                          │
│ ╭──────────────────────────────────────╮ │  GlassCard
│ │ DAILY PROGRESS                       │ │  labelSmall overline
│ │ 1 / 2                    ╭────────╮  │ │  displaySmall + ring
│ │ habits completed today   │  50%   │  │ │  ProgressRing 106pt
│ │ ╭─────────────╮ ╭──────╮ │  done  │  │ │
│ │ │ 🔥 1 day    │ │ 1 left│ ╰────────╯  │ │  TagChips (Wrap)
│ ╰──────────────────────────────────────╯ │
│                                          │
│ TODAY'S HABITS  (2)                      │  SectionHeader
│ ╭──────────────────────────────────────╮ │
│ │ ▌ Read 20 pages              ╭────╮  │ │  accent rail + title
│ │   🔥 4d · Day 6 of 21 · +2   │ ✓  │  │ │  chips + check-in
│ │   ▬▬ ▬▬ ▬▬ ▬▬ ▭▭ ▭▭ ▭▭       ╰────╯  │ │  7-day mini strip
│ │   ▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱▱▱▱▱▱▱▱  29%        │ │  solid accent bar
│ ╰──────────────────────────────────────╯ │
│              … more habits …             │
│ COMPLETED CHALLENGES (n)                 │  finished habits, trophy button
└──────────────────────────────────────────┘
```

- **Greeting** switches on the hour: `< 12` morning (twilight icon), `< 17`
  afternoon (sun), else evening (moon).
- **Avatar** is a solid accent ring; it shows a flame once any
  habit has a live streak, otherwise a person glyph. Tapping opens a quick-stats
  sheet: habit count, best streak, lifetime check-ins.
- **Mini day strip** shows the trailing seven days: filled bar = completed,
  rose wash = missed, outlined = today, flat = upcoming.
- **Category tag** is the 4pt accent rail down the left of each card, matching
  the habit's swatch.
- **Celebration state** — at 100% the progress card is *replaced* (not merely
  recolored) by a solid emerald banner reading "Loop
  closed 🎉", and a confetti burst fires once, only on the transition into 100%.

### Screen 2 — Habit detail and challenge grid (`features/habit_detail/`)

```
┌──────────────────────────────────────────┐
│ ←  Read 20 pages                      ⋯  │
│ ╭──────────────────────────────────────╮ │  hero, solid habit color
│ │ 21-DAY CHALLENGE                     │ │
│ │ Read 20 pages            ╭────────╮  │ │  displaySmall
│ │ 🔥 4 day streak          │  29%   │  │ │  ring in the on-hero color
│ │ 📅 Sep 22, 2026          ╰────────╯  │ │  (wraps on narrow widths)
│ ╰──────────────────────────────────────╯ │
│ ╭────────╮ ╭────────╮ ╭────────╮         │  stat chips
│ │  6/23  │ │   4d   │ │  29%   │         │
│ │Completed│ │ Streak │ │Progress│        │
│ ╰────────╯ ╰────────╯ ╰────────╯         │
│ ╭──────────────────────────────────────╮ │  extension banner (amber)
│ │ ⏱ Challenge extended by +2 days      │ │  only when days were missed
│ ╰──────────────────────────────────────╯ │
│ CHALLENGE GRID        Only today editable│
│ ● Completed ● Missed ○ Today ● Locked    │  legend
│ ┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐                 │  6-column grid
│ │✓ ││✓ ││✕ ││✓ ││ 5││ 6│                 │
│ └──┘└──┘└──┘└──┘└──┘└──┘                 │
└──────────────────────────────────────────┘
```

Cell states:

| State | Fill | Border | Glyph |
| --- | --- | --- | --- |
| Completed | solid habit accent | accent | white/canvas check |
| Missed (past) | rose @ 10% | rose @ 30% | muted rose cross |
| **Today** | accent @ 18% | accent, 2px | day number, weight 800 |
| Future | white @ 4% / `surfaceHigh` | hairline | day number, tertiary |

Only today's cell mutates state. Every other cell is still tappable but answers
with a snackbar — "Day 7 has passed, only today can be checked in" or "Day 12
unlocks on Oct 3" — rather than silently ignoring the tap.

The **missed-day extension banner** states the penalty in plain language: each
missed day appends one day to the end, and the banner names the new target so
the goalpost never moves silently.

### Screen 3 — Add habit (`features/add_habit/add_habit_screen.dart`)

A modal sheet (92% max height) rather than a pushed page, so the dashboard stays
visible behind it.

1. **Live preview card** at the top, updating as you type — title, length, start
   date, and the chosen accent, rendered in the same visual language as a real
   habit card.
2. **Habit title** — filled field, pencil affordance, autofocused.
3. **Challenge length** — three preset chips (21 "Form it", 30 "One month",
   66 "Automatic") plus a custom chip that reveals a digits-only field
   accepting 1–365.
4. **Start date** — full-width row opening the platform date picker, ranged
   −365 to +30 days.
5. **Accent color** — eight 42pt dots; the selected dot grows a ring and a
   check glyph.
6. **Pinned CTA** — "Create habit" sits in a bordered footer that rides above
   the keyboard, tinted with the selected accent.

Validation is inline and non-blocking: an error line appears above the CTA
rather than a dialog.

### Screen 4 — To-Do (`features/todo/todo_tab.dart`)

- **Quick entry bar** at the top. The submit button is a solid accent square that
  only lights up when there's text, and the field keeps focus after submit so
  several tasks can be captured in a row.
- **Active tasks** — rounded rows, 24pt custom checkbox with a spring pop. The
  entire row is the toggle target.
- Completing a task strikes the label through, drops the row to 55% opacity and
  moves it to the completed section.
- Swipe a row right-to-left to delete, or use the ✕ affordance.
- **Completed** is a collapsible section: a chevron rotates 180° while the list
  cross-fades and the surrounding content re-flows, plus a "Clear" action in
  the section header.

### Screen 5 — Notes (`features/notes/`)

- **Search bar** filters title and body live; a sort control offers "Recently
  updated" or "Title A–Z".
- **Two-column masonry** (three columns above 620pt). Columns are balanced by an
  estimated card height derived from the preview length, so the two sides stay
  level instead of the ragged bottom a uniform grid produces.
- **Note card**: a stable per-note accent dot (hashed from the note id), title
  up to two lines, a three-line body preview, the updated date, and a `⋯`
  contextual menu with Open / Delete.
- **Note editor** is deliberately bare — no toolbar. Title in `displaySmall`,
  a short accent rule, then the body at 16/1.65. The only persistent chrome is
  a bottom status strip: save state (spinner → "Saved <timestamp>"), and a live
  word count in tabular figures. Autosave runs 400ms after the last keystroke
  and again on pop; a note left completely empty deletes itself.

### Screen 6 — Settings (`features/settings/settings_screen.dart`)

Grouped glass panels, each under an uppercase overline:

| Group | Contents |
| --- | --- |
| Appearance | Segmented control — Light / Dark / System |
| Feedback | Sound & haptics switch |
| Habits | Manage habits → rename, retarget, recolor, delete |
| Data backup & restore | Export JSON file · Import JSON file · View raw JSON |

Export reports the written path with a copy action. Import lists backups already
found in `Habit Loop / Backup` and falls back to the system file browser. Raw
JSON opens in a selectable monospace dialog with a copy action. Data actions sit
last and use cooler icon tints than the rest of the screen.

---

## 6. Micro-interactions

| Interaction | Spec |
| --- | --- |
| **Check-in tap** | The circle pops through a three-stage sequence — 1.0 → 0.86 (20%) → 1.12 with `easeOutBack` (40%) → 1.0 (40%) over 460ms — while a 3px ring expands from 60% to 130% of the button and fades out. Fill and border cross-fade over 260ms. A light haptic fires on touch, the system click on commit. |
| **All-done celebration** | Only on the *transition* into 100%. 90 rounded confetti chips launch from a band across the upper third with randomised horizontal velocity, staggered up to 220ms, arc under gravity and fade over the last 25% of their 1600ms life. Painted in one `CustomPaint` into the root overlay and removed when the controller completes, so nothing lingers in the tree. A medium haptic accompanies it, and the progress card swaps to the solid emerald celebration banner. |
| **Grid cell press** | Today's cell scales to 0.90 with a haptic; every other cell scales to 0.96 with no haptic and answers with an explanatory snackbar. Today's cell also breathes continuously while unchecked — its 2px border opacity pulsing between 40% and 100% on a 1500ms reversing `easeInOut` ticker — so the one interactive target is unmistakable without anything emitting light. |
| **Progress ring / bar** | Both tween from their previous value over 420ms `easeOutCubic`, so checking a habit makes the arc travel rather than jump. |
| **Nav destination change** | The accent pill slides over 260ms `easeOutCubic`; the icon swaps outlined → filled and lifts 6%; the label animates weight and color over the same duration. |
| **Task checkbox** | Box fill and border animate over 260ms; the check glyph scales 0 → 1 on `easeOutBack`; the label's strikethrough and color animate via `AnimatedDefaultTextStyle`. |
| **Universal press** | Every non-Material tappable is wrapped in `Pressable`: scale down over 160ms `easeOut`, release over 260ms `easeOutBack`, selection haptic. |
| **Color dot selection** | Ring and check glyph animate in on `easeOutBack` at 0.88 press scale. |
| **FAB context switch** | Scales to 0 over 260ms `easeOutBack` and fades over 160ms when the active tab has no create action. |

---

## 7. Accessibility

- Body copy is Inter at ≥12.5px with 1.45+ line height; all text tokens meet
  4.5:1 against their intended surface in both themes.
- Grid cells carry semantic labels ("Day 7, completed", "Day 12, locked"),
  and nav destinations expose `selected` state to screen readers.
- Color is never the only signal: completed days also carry a check, missed days
  a cross, today a heavier numeral and a pulse.
- Every tap target in the nav bar, grid and check-in controls is ≥40pt.
