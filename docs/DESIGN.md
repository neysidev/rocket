# Rocket — Design System and Guidelines

Nov 5, 2026 · @Mehdi

Rocket's interface is a calm, dark-first instrument panel: tonal cards on a glass surface, large tabular numbers, one warm accent that marks what is happening now, and nothing decorative. This document is the single source of truth for Rocket's visual language in both dark and light mode; components in code must trace back to a token defined here.

## Design principles

1. **Quiet until it matters.** Neutral grays carry the layout. Color appears only to say something: live activity, success, failure, or an action. One accent per view.
2. **Numbers first.** Speed, size and time are the content. They get the largest type, tabular digits and stable positions so they never jitter while updating.
3. **Depth by tone, not effects.** Hierarchy comes from fill steps (panel → card → selected card), not shadows, borders, gradients or glows.
4. **Native, then distinctive.** Start from macOS conventions (SF Pro, SF Symbols, system controls, Liquid Glass); add Rocket's character only through proportion, type and the flame accent.
5. **Glanceable in one second.** The menu bar panel answers "what is downloading, how fast, how long" without a click.
6. **Same system, both modes.** Light mode is a deliberate counterpart of dark mode, not an inversion: same structure, same accent meaning, re-tuned values.

### What we take from the reference

| Observed in the reference | Rocket rule |
| --- | --- |
| Translucent dark panel, large radius, faint light edge | Panel uses system glass with a 1 px inner highlight; radius 20 pt |
| Cards are flat tonal fills with no border or shadow | Cards are fill steps only; borders appear only in Increase Contrast mode |
| Selected card is simply one step lighter | Selection = one fill step up; no outline, no accent color |
| Big semibold numbers with small secondary units ("3 MB", "1.2 GB") | Metric + unit pairing with a fixed size ratio (28 / 13 pt) |
| Gray bars with the most recent bars in amber | Charts are neutral; only "now" and live data use the flame accent |
| Small green "Live" status word, blue "Connect…" link | Status uses a word plus color, never color alone; links use the system accent |
| Hierarchy lines connecting grouped rows | Group rows (by queue or host) use a 1 pt connector in the tertiary color |
| Circular icon buttons, search field with a ⌘K keycap | Icon buttons are 28 pt circles; keyboard shortcuts are shown as keycaps |

We adopt the reference's visual language, not its brand: no layout, icon or name is copied.

## At a glance

The menu bar panel is the reference surface for the whole system: every token below appears in it.

&#91;embedded content: Menu bar panel mock · dark and light\]

Top to bottom: header, three stat cards (the selected one a step lighter), the 24-hour throughput chart with the current hours in Flame, the live list grouped by queue, and the filter field. Values in the mock are illustrative.

## Color

Rocket uses a cool neutral scale for 90% of every screen and one warm accent, **Flame**, that means "in flight now". Code never uses a raw color; it uses the semantic tokens below.

&#91;embedded content: Color tokens · dark and light\]

### Semantic tokens

Hex values are the opaque reference values (used for fallbacks, exports and contrast checks). On glass, surface tokens are applied as the listed white/black overlay so the material shows through.

| Token | Dark | Light | Use |
| --- | --- | --- | --- |
| `surface.canvas` | `#121417` | `#F7F8FA` | Main window content background |
| `surface.panel` | `#1B1E22` (glass) | `#EEF0F2` (glass) | Popover, sidebar, sheets |
| `surface.card` | `#24282D` · white 6% | `#FFFFFF` · white 72% | Stat cards, chart cards, grouped list |
| `surface.cardSelected` | `#2D3238` · white 10% | `#FFFFFF` + `stroke.hairline` | Selected card, selected row |
| `surface.control` | `#2A2E34` · white 8% | `#E6E8EB` · black 6% | Search field, keycaps, icon-button rest fill |
| `stroke.hairline` | white 8% | black 8% | Separators, glass edge, Increase Contrast borders |
| `text.primary` | `#F3F4F6` | `#17191C` | Titles, values, file names |
| `text.secondary` | `#A1A7AF` | `#5F656D` | Labels, metadata, units |
| `text.tertiary` | `#6E747C` | `#8E949B` | Axis labels, connectors, placeholders (never essential text) |
| `accent.flame` | `#FFB23F` | `#F29D0B` | Live data, active progress, "now" bars, the menu bar glyph while downloading |
| `accent.flameText` | `#FFB23F` | `#9A5B00` | Flame used as text on light surfaces (contrast) |
| `status.success` | `#6FCF8A` | `#23843E` | Completed, "Live" agent status |
| `status.danger` | `#FF6B63` | `#D7342B` | Failed, destructive actions |
| `status.warning` | `#F5C451` | `#A86F00` | Needs attention (expired link, disk nearly full) |
| `accent.interactive` | System accent (default `#0A84FF`) | System accent (default `#007AFF`) | Links, focus rings, default buttons, toggles |
| `chart.neutral` | `#5C626A` | `#C3C8CE` | Bars and lines for past data |
| `chart.track` | `#33383E` | `#E1E4E8` | Progress and chart tracks |

### Rules

- **Flame is not a button color.** Interactive elements follow the user's system accent (Apple HIG); Flame only describes live state and data.
- **One accent per view.** If a view shows Flame data, it does not also use colored icons or tinted cards.
- **Status always pairs color with an icon or word** ("Failed", ⊗), never color alone.
- **Light mode is re-tuned, not inverted:** cards are lighter than the panel (not darker), Flame shifts warmer and deeper so it reads on white, and secondary text darkens to keep 4.5:1.
- Contrast targets: body and label text at least 4.5:1 on its surface; `text.tertiary`, chart marks and icons at least 3:1. The values above are designed to these targets and are re-checked automatically in UI tests.

## Materials and Liquid Glass

Glass is for the navigation and control layer only; content (lists, cards, charts) sits on solid tonal fills above it. This matches Apple's Liquid Glass guidance and keeps text crisp.

| Layer | macOS 26 and later | macOS 14–15 fallback | Examples |
| --- | --- | --- | --- |
| Chrome | System Liquid Glass (automatic for toolbars, sidebars, popovers, menus) | `NSVisualEffectView` materials: `.popover`, `.sidebar`, `.titlebar` | Menu bar panel background, window sidebar, toolbar |
| Floating controls | `.glassEffect(.regular.interactive())`, grouped in a `GlassEffectContainer` | `.regularMaterial` capsule with `stroke.hairline` | Filter bar, bottom action bar, inspector toggle |
| Prominent action | `.buttonStyle(.glassProminent)` tinted with the system accent | `.borderedProminent` | "Start download" in the Add sheet |
| Content | No glass: `surface.card` / `surface.canvas` fills | Same | Cards, download list, charts, detail view |

### Rules

- **Never glass on glass.** A glass element is never placed on another glass element; cards inside the glass panel are tonal fills, not glass.
- **Group glass that moves together** in one `GlassEffectContainer` so shapes merge and morph instead of overlapping.
- **Tint sparingly.** Only the single primary action per view may be tinted; tint uses the system accent, never Flame.
- **Edge light:** the panel shows a 1 px inner highlight (`stroke.hairline`, top-weighted) that the system provides on macOS 26; the fallback draws it explicitly.
- **Concentric shapes:** inner radius = outer radius − inset, so cards nest cleanly in the panel (20 − 8 = 12 pt).
- **Reduce Transparency:** all glass becomes the opaque `surface.panel` value; layout and contrast stay identical.
- **Increase Contrast:** glass keeps its material but gains a `stroke.hairline` border at double opacity; cards gain a 1 px border.
- Liquid Glass API names (`glassEffect`, `GlassEffectContainer`, `.glass` / `.glassProminent` button styles) are checked against the shipping SDK at implementation time; the fallback path is mandatory for macOS 14–15.

## Typography

Rocket uses the system fonts only (SF Pro and SF Mono) through eight type tokens; every number that updates uses tabular digits.

| Token | Size / line height | Weight | Color | Use |
| --- | --- | --- | --- | --- |
| `type.metricLarge` | 28 / 32 pt | Semibold, tracking −0.4 | `text.primary` | Hero numbers in stat cards ("12", "84.3") |
| `type.metric` | 20 / 24 pt | Semibold | `text.primary` | Secondary metrics, detail view totals |
| `type.title` | 15 / 20 pt | Semibold | `text.primary` | Panel title, window section titles |
| `type.headline` | 13 / 16 pt | Semibold | `text.primary` | Card titles ("Last 24 hours"), file names in rows |
| `type.body` | 13 / 16 pt | Regular | `text.primary` | General text, settings |
| `type.label` | 12 / 16 pt | Medium | `text.secondary` | Card labels ("Active"), units, metadata |
| `type.caption` | 11 / 14 pt | Regular | `text.tertiary` | Axis labels, timestamps, footnotes |
| `type.mono` | 12 / 16 pt | SF Mono Regular | `text.secondary` | URLs, paths, hashes, ports |

### Rules

- **Tabular numerals everywhere numbers change** (`.monospacedDigit()`): speeds, sizes, percentages, ETAs, counts. A changing digit never shifts its neighbors.
- **Metric and unit:** the unit is set in `type.label` right after the value, baseline-aligned, 4 pt apart ("84.3 MB/s"). Units never wrap away from their value.
- **Sentence case** for every label, button and title; no ALL CAPS, no letter-spaced eyebrows.
- **Truncation:** file names truncate in the middle (`.truncationMode(.middle)`) to keep the extension visible; URLs truncate in the middle; descriptions at the tail.
- **Two weights per view** at most besides metrics: Regular and Semibold (Medium is reserved for `type.label`).
- Sizes are macOS points and follow the user's system text-size setting where macOS provides it (sidebar, lists); layouts must survive +2 pt without clipping.

## Spacing, radii and layout

All spacing sits on a 4 pt grid, with 8 pt as the default rhythm between siblings.

| Spacing token | Value | Typical use |
| --- | --- | --- |
| `space.1` | 2 pt | Metric to sub-label, icon to badge |
| `space.2` | 4 pt | Value to unit, inline icon to text |
| `space.3` | 8 pt | Gap between cards, panel inset, row vertical padding |
| `space.4` | 12 pt | Card inner padding, list row horizontal padding |
| `space.5` | 16 pt | Section spacing inside the main window |
| `space.6` | 24 pt | Window content margins, empty-state spacing |
| `space.7` | 32 pt | Large separations, onboarding |

| Radius token | Value | Use |
| --- | --- | --- |
| `radius.panel` | 20 pt | Menu bar panel, sheets (system-provided on macOS 26) |
| `radius.card` | 12 pt | Cards, grouped lists (20 − 8 inset) |
| `radius.control` | 8 pt | Search field, text fields, segmented controls |
| `radius.small` | 6 pt | Keycaps, file-type tiles, badges |
| `radius.full` | capsule / circle | Icon buttons, progress bars, pills |

| Size token | Value |
| --- | --- |
| `size.iconButton` | 28 pt circle (hit area 28 pt minimum) |
| `size.fileTile` | 28 pt square, `radius.small` |
| `size.rowCompact` / `size.row` | 36 pt / 52 pt |
| `size.progressBar` | 3 pt (rows), 6 pt (detail view) |
| `size.keycap` | 20 pt high, 6 pt horizontal padding |

### Menu bar panel

- Width 360 pt; height fits content up to 640 pt, then the live list scrolls.
- Order, top to bottom: header (title, pause-all, settings) → three stat cards in one row (Active, Speed, Queued) → throughput card (last 24 hours) → live downloads list grouped by queue → filter field with ⌘K.
- Panel inset 8 pt; card gap 8 pt; stat cards share the width equally.

### Main window

- `NavigationSplitView`: sidebar (220 pt; queues, categories, status filters) → download list → optional inspector (300 pt).
- Minimum window 760 × 480 pt; content margins 24 pt; the list uses `size.row` with a 3 pt progress bar under the metadata line.
- Toolbar holds Add, Pause all / Resume all, speed-limit menu and search; nothing else.

## Iconography

Icons are SF Symbols, monochrome, in the weight of the text beside them; Rocket adds only three custom symbols drawn on the SF Symbols template.

### Rules

- **Rendering:** monochrome or hierarchical only; never multicolor or palette. Icons take `text.secondary` at rest and `text.primary` on hover; status icons take their status color.
- **Weight matches text:** Regular next to body text, Medium next to `type.label`, Semibold next to headlines.
- **Sizes:** 13 pt inline, 15 pt in icon buttons, 17 pt in the toolbar, 11 pt in badges. Use symbol scale (`.imageScale`) rather than arbitrary frames.
- **Outline by default, fill for state:** `pause` at rest, `pause.fill` when pressed or active. Filled shapes signal "on", never decoration.
- **No icons for their own sake:** a label gets an icon only if it speeds recognition (toolbar, sidebar, status). Stat cards and section titles have none.

### Core set

| Meaning | Symbol |
| --- | --- |
| Add download | `plus` |
| Pause / resume | `pause` / `play` |
| Stop / cancel | `stop` / `xmark` |
| Reveal in Finder | `magnifyingglass.circle` in rows; `folder` in menus |
| Retry | `arrow.clockwise` |
| Completed | `checkmark.circle` |
| Failed | `exclamationmark.triangle` |
| Scheduled | `clock` |
| Speed limit | `gauge.with.dots.needle.33percent` |
| Queue | `list.bullet` |
| Settings | `gearshape` |
| Filter / search | `line.3.horizontal.decrease` / `magnifyingglass` |

### Custom symbols

- `rocket.down` — the brand glyph: a minimal rocket pointing down, 2 strokes plus a flame cutout; built as an SF Symbol template with all 9 weights and 3 scales.
- `rocket.down.fill` — the menu bar glyph while downloads are active; the flame cutout takes `accent.flame` as a hierarchical secondary layer.
- `segments` — four stacked bars of unequal length for the connections view.

The menu bar item is a template image (adapts to light, dark and tinted menu bars) and shows aggregate speed as text only when the user enables it.

### App icon

- Built in Icon Composer as a layered macOS 26 icon (with a flattened fallback for macOS 14–15): a rounded square in deep graphite, the down-pointing rocket in off-white on the front layer, a small Flame-colored exhaust as the only warm element.
- No gradients beyond the system's glass lighting, no text, no extra objects. It must read at 16 pt in Finder lists.

## Components

Every screen is assembled from the components below; a new component needs a design review and an entry here before it ships.

| Component | Anatomy | Tokens | Variants and notes |
| --- | --- | --- | --- |
| **Panel** | Header, stack of cards, footer field | `surface.panel` (glass), `radius.panel`, inset `space.3` | Menu bar panel, sheets. One per window |
| **Panel header** | App glyph + title, trailing icon buttons | `type.title`; secondary word in `text.secondary` Regular | Trailing actions max 2 (pause all, settings) |
| **Stat card** | Label (top left), status word (top right), metric + unit (bottom left), trailing indicator (bottom right) | `surface.card`, `radius.card`, padding `space.4`, `type.label`, `type.metricLarge` | Indicator: status word, sparkline, mini bar, or capacity bar. Selectable: selected = `surface.cardSelected` |
| **Chart card** | Title + summary value on one line, chart, two axis captions (start, "Now") | `type.headline`, `type.caption`, `chart.*` | Bar (throughput history) or line (live speed). No gridlines |
| **Download row** | File tile, name, metadata line, progress bar, trailing actions | `size.row`, `type.headline`, `type.label`, `size.progressBar` | Compact (panel) and regular (window). Actions appear on hover in the window; always visible in the panel |
| **Group header** | Queue or host tile, name, path or rule in `type.mono`, count | `type.headline`, `text.secondary` | Children connected by a 1 pt `text.tertiary` line, as in the reference |
| **File tile** | 28 pt rounded square with a type symbol | `surface.control`, `radius.small` | Archive, video, audio, image, document, app, other. Icon monochrome |
| **Icon button** | Circle with SF Symbol | `size.iconButton`, `surface.control` on hover only | Plain (no fill at rest), filled (`surface.control` at rest, e.g. stop/open in rows), destructive (icon `status.danger`) |
| **Primary button** | Text, optional leading symbol | System `.glassProminent` / `.borderedProminent`, system accent | Max one per view |
| **Filter field** | Magnifier, placeholder, keycap | `surface.control`, `radius.control`, `type.body`, keycap `size.keycap` | Focus shows the system focus ring; Escape clears |
| **Keycap** | Shortcut glyphs | `surface.control`, 1 px `stroke.hairline`, `type.caption` Medium | Used in fields, menus and empty states |
| **Status pill** | Dot or symbol + word | `type.label`, status color on text and dot only (no filled background) | Live, Paused, Scheduled, Failed, Completed |
| **Progress bar** | Track + fill | `chart.track`, fill `accent.flame` (active) / `text.tertiary` (paused) / `status.success` (done, then fades) / `status.danger` (failed) | Determinate only when size is known; otherwise an indeterminate shimmer-free pulse |
| **Segments bar** | One track split into per-connection fills | Same as progress bar, 6 pt, 1 pt gaps | Detail view only; shows dynamic segmentation live |
| **Empty state** | `rocket.down` symbol, one sentence, one action, keycap hint | `type.headline`, `type.body`, `space.6` | No illustrations |

### Composition rules

- A card holds one idea: one metric, one chart, or one list. Never two metrics of equal weight in one card.
- Stat cards in a row share equal widths and identical internal alignment so their numbers line up.
- Lists inside the panel are grouped by queue; in the window they can be grouped by queue, host or status.
- Native controls (toggles, pickers, menus, segmented controls, sliders) are always the system ones; Rocket never restyles them.

## Interaction states and motion

States change fill and opacity, never size or layout; motion is short, purposeful and disappears under Reduce Motion.

| State | Visual change (dark) | Visual change (light) |
| --- | --- | --- |
| Rest | Token value | Token value |
| Hover | Fill +4% white; icon to `text.primary` | Fill +4% black; icon to `text.primary` |
| Pressed | Fill +8% white | Fill +8% black |
| Selected | `surface.cardSelected` | `surface.cardSelected` (white + hairline) |
| Focused (keyboard) | System focus ring in system accent, 3 pt offset following the shape's radius | Same |
| Disabled | 40% opacity on content; no hover | Same |
| Live | Flame on progress, metric indicator and menu bar glyph | Same, light Flame values |
| Paused | Progress fill `text.tertiary`; status word "Paused" | Same |
| Error | `status.danger` icon and status word; row stays neutral | Same |
| Completed | Progress turns `status.success` for 2 s, then the row settles to neutral with a check | Same |

### Motion tokens

| Token | Value | Use |
| --- | --- | --- |
| `motion.fast` | 120 ms ease-out | Hover and press fills |
| `motion.standard` | 220 ms ease-in-out | Row insert/remove, card selection, disclosure |
| `motion.glass` | Spring, response 0.35, damping 0.85 | Glass shapes morphing (macOS 26) |
| `motion.progress` | Linear interpolation over 200 ms between 5 Hz updates | Progress bars and speed numbers |

### Rules

- Numbers update in place with no rolling or counting animation; the tabular digits do the work.
- Progress interpolates between updates so bars move smoothly, but never runs ahead of real data.
- No bounce, confetti, pulsing glows or attention-seeking loops. Completion is a quiet color change plus a system notification.
- Reduce Motion: all transitions become cross-fades of `motion.fast`; glass morphing is disabled.
- Hover affordances never hide essential actions from keyboard or VoiceOver users; hidden row actions remain in the context menu and accessibility actions.

## Data visualization

Charts are built with Swift Charts in the same quiet language: neutral history, Flame for now, no chrome.

- **Throughput history (chart card):** 24 hourly bars, `chart.neutral`; the current hour and any bar with active downloads in `accent.flame`. Bars 2 pt apart with 2 pt top corners. Only two axis captions: the start time and "Now".
- **Live speed (detail view):** a 60-second line in `accent.flame`, 1.5 pt, with a 12% Flame area fill; no markers, no gridlines, a single caption for the peak.
- **Sparkline (stat card indicator):** 16 bars, 2 pt wide, the last bar Flame; height 14 pt.
- **Capacity bar (stat card indicator):** 3 pt capsule for disk space or queue fill; turns `status.warning` above 90%.
- **Progress:** linear bars only; no circular rings except the menu bar glyph's optional progress.
- **Scales:** speed axes use human units chosen per range (KB/s, MB/s, GB/s) with at most 3 significant digits; sizes use decimal units (MB, GB) to match Finder.
- **Empty data:** a flat `chart.track` baseline with the caption "No downloads in the last 24 hours"; never an empty frame.
- **Accessibility:** every chart provides `accessibilityChartDescriptor` (Audio Graphs) and a one-line summary label, e.g. "Peak 412 MB/s at 14:00".

## Accessibility and consistency

Accessibility is a release gate: a screen that fails the checks below does not ship.

| Area | Requirement |
| --- | --- |
| Contrast | Text 4.5:1 minimum; large metrics, icons, chart marks and focus rings 3:1; checked in both modes |
| Color independence | Every status has a word or symbol; charts never rely on color alone to distinguish series |
| VoiceOver | Each row reads as one element: "ubuntu-24.04.iso, downloading, 62 percent, 84 megabytes per second, 2 minutes left"; actions exposed as accessibility actions |
| Keyboard | Every action reachable by keyboard; ⌘K focuses the filter, Space pauses or resumes the selected download, ⌫ removes, ⌘O reveals in Finder; focus order follows reading order |
| Hit targets | 28 × 28 pt minimum for clickable icons; rows fully clickable |
| Reduce Transparency | Glass becomes opaque `surface.panel`; no loss of contrast |
| Increase Contrast | Hairline borders on cards and controls; `text.secondary` steps toward `text.primary` |
| Reduce Motion | Cross-fades only; no glass morphing, no interpolated progress |
| Text size | Layouts tolerate +2 pt and long localized strings (German, French) without clipping; right-to-left layouts mirror correctly |
| Live updates | Progress announcements are throttled (on start, every 25%, on finish or failure) to avoid VoiceOver chatter |

### Consistency checklist (every pull request with UI changes)

- [ ] Only tokens from this document; no raw colors, sizes or font literals.
- [ ] Checked in dark, light, Increase Contrast and Reduce Transparency.
- [ ] Numbers use tabular digits; file names truncate in the middle.
- [ ] At most one Flame-accented element type and one primary button per view.
- [ ] Keyboard path and VoiceOver labels verified.
- [ ] Screenshots of both modes attached to the PR.

## Implementation in SwiftUI

The design system ships as a `RocketDesign` module (UI layer only) so the app, settings and future surfaces share one implementation.

- **Colors** live in an asset catalog with Any/Dark and High Contrast variants, exposed only through semantic accessors; raw `Color(red:green:blue:)` is banned by a SwiftLint custom rule outside `RocketDesign`.
- **Typography, spacing, radii and motion** are static constants; components read them, views never hard-code numbers.
- **Components** are SwiftUI views and `ButtonStyle` / `LabelStyle` types with previews for every variant in both modes.
- **Glass** goes through one modifier that selects Liquid Glass on macOS 26+ and the material fallback on 14–15.
- **Snapshot tests** render each component in dark, light and Increase Contrast; contrast is checked programmatically from the token values.

```swift
public enum RocketColor {
    public static let surfaceCard   = Color("surface.card", bundle: .module)
    public static let textSecondary = Color("text.secondary", bundle: .module)
    public static let flame         = Color("accent.flame", bundle: .module)
}

public enum RocketSpace {
    public static let s2: CGFloat = 4
    public static let s3: CGFloat = 8
    public static let s4: CGFloat = 12
}

public enum RocketRadius {
    public static let panel: CGFloat = 20
    public static let card:  CGFloat = 12
}

extension Font {
    static let rocketMetricLarge = Font.system(size: 28, weight: .semibold).monospacedDigit()
    static let rocketLabel       = Font.system(size: 12, weight: .medium)
}

extension View {
    /// Liquid Glass on macOS 26+, system material before that.
    @ViewBuilder
    func rocketGlass(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}
```

## What we avoid

These patterns are rejected in review even when they look attractive in isolation.

| Avoid | Why | Instead |
| --- | --- | --- |
| Purple-blue gradients, neon glows, "aurora" backgrounds | Generic AI-product look; fights the wallpaper and glass | Neutral tonal surfaces; Flame only for live data |
| Drop shadows on cards, glassmorphism stacks | Muddy depth, double blur, poor contrast | One glass layer; tonal steps for hierarchy |
| Bento grids of many equal tiles | Everything looks equally important | Three stat cards, then one chart, then the list |
| Colored icon backgrounds, multicolor symbols | Visual noise, competes with status colors | Monochrome SF Symbols |
| Emoji, mascots, illustrations in empty states | Breaks the instrument tone | One symbol, one sentence, one action |
| Animated counters, confetti, pulsing "live" dots | Distracting in a tool that runs for hours | Static tabular numbers; quiet color change on completion |
| ALL-CAPS labels, letter-spaced eyebrows | Shouty, un-Mac-like | Sentence case, `type.label` |
| Custom-styled toggles, sliders, menus | Inconsistent with macOS, accessibility regressions | System controls |
| Flame on buttons or selections | Dilutes its meaning as "in flight" | System accent for interaction |
| Glass behind dense text or lists | Legibility drops on busy wallpapers | Glass for chrome; solid fills for content |
