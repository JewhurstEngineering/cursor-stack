# CursorStack — Design System

Global source of truth for the marketing site. Page rules in `pages/home.md` override this file when they disagree.

## How this was chosen

The design-system command was run twice:

- `developer tool macOS window manager`
- `developer tool product landing`

Both returned **FAQ / Documentation Landing** (search bar, article categories, support CTA) with a green “run” accent. That pattern is for a docs site, not a Mac app download page, so it was not saved.

What was used instead, from verified search rows:

- **Product:** Developer Tool / IDE. Style is Dark Mode (OLED) plus Minimalism and Swiss. Landing pattern on that row is Minimal and Direct, plus documentation. Color note is dark syntax with a blue focus. Type is monospace plus a functional sans. Avoid a light-mode default and slow pages.
- **Landing:** App Store Style Landing for a download page (real screenshots, a download button that repeats, no auto-rotating carousel). The hero stays minimal and direct: one headline, a short description, a few facts, one primary action.
- **Accent:** `#01BBD8`, sampled from the color wordmark. The palette’s generic green (`#22C55E`) fights the mark. The product row also asks for a blue focus. Dark text on this cyan is 7.74:1. White text on it is 2.31:1, so it is not used.

## Style

Dark, quiet, precise. The page should feel like the tab strip: a small instrument sitting on real windows. No purple gradients, no neon wash, no light theme.

## Colors

| Role | Hex | Token |
|------|-----|--------|
| Primary | `#1E293B` | `--color-primary` |
| On primary | `#FFFFFF` | `--color-on-primary` |
| Secondary | `#334155` | `--color-secondary` |
| Background | `#0F172A` | `--color-background` |
| Foreground | `#F8FAFC` | `--color-foreground` |
| Card | `#1B2336` | `--color-card` |
| Muted | `#272F42` | `--color-muted` |
| Muted foreground | `#94A3B8` | `--color-muted-foreground` |
| Border | `#475569` | `--color-border` |
| Accent / CTA | `#01BBD8` | `--color-accent` |
| On accent | `#0F172A` | `--color-on-accent` |
| Attention | `#F59E0B` | `--color-attention` |
| Ring | `#FFFFFF` | `--color-ring` |

Muted text on the background is 6.96:1. Foreground on the background is 17:1.

## Typography

- Headings: JetBrains Mono
- Body: IBM Plex Sans
- Body size 16px, line-height 1.5
- `text-wrap: balance` on headings is a progressive enhancement. The line still has to work if it wraps anywhere.

```css
@import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@500;600;700&display=swap');
```

## Effects and motion

Subtle only. A 1px cyan edge on the window mock is enough glow. Do not put a glow on body text.

Scroll reveal, if used: 12px and 350ms, ease-out. Content stays visible without JavaScript. Skip the motion when `prefers-reduced-motion: reduce`.

## Avoid

- Light mode as the default
- FAQ / search-bar hero
- Green “run” accent
- Emoji as icons
- Auto-rotating carousels
- Hover-only actions
- Layout shift from images without dimensions

## Pre-delivery

- SVG icons (Heroicons outline). Decorative icons get `aria-hidden="true"`.
- `cursor: pointer` on links and buttons
- Hover transitions 150–300ms
- Text contrast at least 4.5:1
- Visible focus, not covered by the sticky header (`scroll-padding-top`)
- `prefers-reduced-motion` respected
- Labels and shortcut keys wrap without clipping
- Check 375, 768, 1024, and 1440
