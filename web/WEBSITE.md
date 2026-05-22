# RULYX — Marketing Concept & Website Plan

## 1. Brand Identity

### Taglines
- **Primary:** "Bluesky moderation made easy."
- **Secondary:** "Easy to use, sharp as a knife."

### Brand Voice
Confident, direct, no-fluff. RULYX speaks like a trusted tool — not a lifestyle brand. The tone is pragmatic and empowering: this is software that solves a real problem for real people. No hype. No buzzwords. Just what it does and why it matters.

### Core Promise
Absolute control over your Bluesky experience — without exposing yourself, without paying a cent, and without trusting anyone's servers.

---

## 2. Target Audience

| Persona | Need | Pain Point |
|---------|------|------------|
| **Community Moderators** | Manage large lists, batch-block bad actors, inspect suspicious profiles | Manual moderation is slow; Bluesky's native tools are inadequate for scale |
| **Power Users** | Curate their feed, manage multiple identities, export data | Switching between accounts is clumsy; no built-in export |
| **Privacy-Conscious Users** | Moderate without exposing their main account, no tracking | Distrust of third-party services that phone home or serve ads |
| **Investigators / Researchers** | Audit handle histories, export posts/media, run bulk lookups | No native Bluesky tools for forensic profile analysis |

---

## 3. Messaging Hierarchy

```
Level 1 — Headline
  "Bluesky moderation made easy."

Level 2 — Subhead
  "Easy to use, sharp as a knife."

Level 3 — Value Props (in priority order)
  1. One-click moderation (block, mute, report, add-to-list)
  2. Batch operations at scale
  3. Profile inspection via clean second account
  4. Handle history & data export
  5. Face ID lock — zero trust architecture

Level 4 — Trust Signals
  - Open Source (MIT)
  - Free Forever
  - No Servers
  - No Tracking
  - No Ads
```

---

## 4. Competitive Landscape

| | RULYX | Bluesky Native | Third-Party Clients | Web Mod Tools |
|---|---|---|---|---|
| Multi-account | ✓ Unlimited | ✗ | Partial | ✗ |
| Batch block | ✓ Parallel queue | ✗ | ✗ | ✗ |
| Clean search account | ✓ | N/A | ✗ | ✗ |
| Handle history | ✓ PLC audit | ✗ | ✗ | ✗ |
| Post/media export | ✓ CSV/JSON | ✗ | ✗ | Partial |
| Face ID lock | ✓ | ✗ | ✗ | ✗ |
| No servers | ✓ | N/A | ✗ | ✗ |
| Open source | ✓ MIT | ✗ | Partial | Partial |
| Free | ✓ Forever | ✓ | Freemium | Freemium |

**Positioning:** RULYX is not a social client — it's a command center. It doesn't compete with Bluesky's app or third-party timeline viewers. It's a dedicated moderation workstation.

---

## 5. Website Plan (`web/index.html`)

### 5.1 Structure (One-Pager)

```
┌──────────────────────────────────────┐
│  NAV  RULYX  Features  Beta  Priv…  │  ← Fixed, blur backdrop
├──────────────────────────────────────┤
│                                      │
│  ╔═══════════ HERO ═══════════════╗  │
│  ║ "Bluesky moderation            ║  │  ← 100vh
│  ║  made easy."                   ║  │     Gradient headline
│  ║ "Easy to use, sharp as a knife."║  │     Phone mockup (rotates 4 screens)
│  ║ [App Store] [See Features]     ║  │     Badge row
│  ╚════════════════════════════════╝  │
│                                      │
│  ───── STATS BAR ────────────────    │  ← Animated counters
│   16 Languages · 0 Servers · 0 ...   │
│                                      │
│  ╔═══════════ FEATURES ═══════════╗  │
│  ║ 9 cards, 3×3 grid             ║  │  ← Glass cards, gradient borders
│  ║ 1. One-Click Moderation        ║  │     Hover lift + glow
│  ║ 2. Batch Block Operations      ║  │
│  ║ 3. List Management             ║  │
│  ║ 4. Profile Intel (Clean Acct)  ║  │
│  ║ 5. Handle History              ║  │
│  ║ 6. Export Posts & Media        ║  │
│  ║ 7. Multi-Account Switcher      ║  │
│  ║ 8. Easy Reporting              ║  │
│  ║ 9. Face ID Lock                ║  │
│  ╚════════════════════════════════╝  │
│                                      │
│  ╔═══════════ BETA ═══════════════╗  │
│  ║ 4 cards, gold BETA tag        ║  │  ← Opt-in experimental features
│  ║ Timeline · Posting · DM · Notif║  │
│  ╚════════════════════════════════╝  │
│                                      │
│  ╔═══════════ TRUST ══════════════╗  │
│  ║ 6 cards: Open Source, Free,    ║  │  ← Privacy-first messaging
│  ║ No Ads, No Tracking,           ║  │
│  ║ Dark/Light Mode, 16 Languages  ║  │
│  ╚════════════════════════════════╝  │
│                                      │
│  ╔═══════ DOWNLOAD CTA ══════════╗   │
│  ║ "Bluesky moderation           ║  │  ← Radial glow, App Store button
│  ║  made easy."                  ║  │     Device badges
│  ║ [Download on the App Store]   ║  │
│  ╚═══════════════════════════════╝   │
│                                      │
│  ───────── FOOTER ──────────────     │  ← Links, legal, GitHub
└──────────────────────────────────────┘
```

### 5.2 Navigation
```
RULYX (logo → #hero)
├── Features     → #features
├── Beta         → #beta
├── Privacy      → #privacy
└── Download     → #download
    └── EN | DE  → Language switch
```

### 5.3 Phone Mockup Screen Rotation (4 screens, 4s interval, tap to advance)

| Screen | Content | Purpose |
|--------|---------|---------|
| 1. Lists | Moderation lists with member counts | Show core feature: list management |
| 2. Profile Actions | User profile with Block/Mute/Add-to-List toggles | Show one-click moderation |
| 3. Handle History | PLC directory changelog with dates | Show forensic capability |
| 4. Account Switcher | 3 accounts + "clean account" search indicator | Show multi-account + privacy feature |

### 5.4 Visual Design System

```
Background:    #03030a (near-black)
Surface:       #08081a (slightly lifted)
Cards:         rgba(14,14,32,.65) glass
Borders:       rgba(99,102,241,.1)
Primary:       #6366f1 (indigo)
Accent:        #22d3ee (cyan)
Accent 2:      #f472b6 (pink)
Beta Gold:     #fbbf24
Success:       #34d399
Danger:        #f87171

Heading Font:  Bricolage Grotesque (weight 800-900)
Body Font:     Sora (weight 400-600)
Mono Font:     JetBrains Mono (for code/numbers)

Effects:
  - 4 animated mesh gradient blobs (blur 140px)
  - SVG noise texture overlay (opacity .02)
  - Floating particles (CSS animation)
  - Cursor-following radial glow
  - Card gradient borders on hover (mask-composite)
  - Scroll-triggered reveal animations
  - Animated stat counters (count-up on intersection)
```

### 5.5 Responsive Breakpoints
```
≥ 960px   Full 2-column hero, 3-column feature grids
≥ 640px   2-column grids, stacked hero
< 640px   Single column, mobile nav toggle
```

---

## 6. Conversion Funnel

```
Visit landing page
    │
    ▼
Hero: "Bluesky moderation made easy"
    │  Value proposition clear in <2s
    ▼
Stats: 0 servers, 0 trackers, 0 ads
    │  Trust established
    ▼
Features: 9 cards covering every use case
    │  User finds their specific need
    ▼
Beta: Timeline, posting, chat, notifications
    │  Future-proofing signal
    ▼
Trust: Open source, free, no tracking, 16 languages
    │  Objection handling
    ▼
Download CTA → App Store
    │
    ▼
Install → First launch → Add account → Moderate
```

---

## 7. Technical Specs

| Attribute | Value |
|-----------|-------|
| File | `web/index.html` |
| Lines | ~590 (single self-contained file, no external CSS/JS) |
| Dependencies | Google Fonts (Bricolage Grotesque, Sora, JetBrains Mono) |
| Framework | Zero. Vanilla HTML/CSS/JS |
| Hosting | Static file, any web server |
| Language Switch | Links to `index-de.html` |
| SEO | meta description, semantic HTML5, heading hierarchy |
| Accessibility | Semantic landmarks (nav, section, footer), alt text, keyboard-navable links |
| Performance | No render-blocking JS, CSS-first animations, system font fallback |

---

## 8. Future Considerations

- Add `index-de.html` with German translations matching the new structure
- Add `screenshot.png` assets for a dedicated screenshots/gallery section
- Add a `Press Kit` link in the footer
- Consider a `/privacy` standalone page
- Add Open Graph / Twitter Card meta tags for social sharing previews
- Add a "What's New" changelog section pulling from GitHub releases
