# Rocket — Product Requirements Document (PRD)

Nov 5, 2026 · @Mehdi

Rocket is a free, open-source, fully native macOS download manager that makes large downloads faster, resumable and hands-off. This PRD defines what v1.0 must do and why; the companion TRD defines how.

## Document control

| Field | Value |
| --- | --- |
| Product | Rocket (bundle ID `io.github.neysidev.rocket`) |
| Repository | github.com/neysidev/rocket |
| Document | Product Requirements Document, v1.0 draft |
| Status | Draft for review |
| Owner | Mehdi (neysidev), maintainer |
| Scope | v0.1 through v1.0, plus post-1.0 direction |
| Companion documents | Technical Requirements Document (TRD); architecture docs and ADRs in `docs/` |
| Requirement keywords | MUST / SHOULD / MAY as in RFC 2119; priority as MoSCoW |

| Date | Version | Change |
| --- | --- | --- |
| 2026-11-05 | 0.1 | First draft from the founding design sessions |

## Product overview and vision

**Pitch:** Rocket is the fast, native download manager for Mac — "IDM for macOS", open source and free.

**Vision:** any file a Mac user wants arrives as fast as their connection allows, survives every interruption, and never needs babysitting.

Rocket accelerates HTTP/HTTPS downloads by splitting files across parallel connections, resumes after network drops, sleep or crashes, and runs downloads in a background agent so they continue when the window is closed. Power features (queues, scheduling, speed limits, rules, CLI, browser capture) are built in, not bolted on.

### Product principles

1. **Native first.** Swift and SwiftUI/AppKit, system conventions, no Electron, no web views for core UI.
2. **Fast by default.** Acceleration works with zero configuration; tuning is optional.
3. **Never lose a byte.** A download is resumable or it is restarted honestly; a corrupted "complete" file is a release-blocking bug.
4. **Quiet and light.** Near-zero CPU and memory when idle; no dock bounces, no nags, no telemetry by default.
5. **Scriptable.** Everything the UI can do, the CLI and URL scheme can do.
6. **Private.** No accounts, no tracking, no data leaves the Mac except the downloads themselves.
7. **Open.** Developed in public, permissively licensed, built so contributors can work on one module without learning all of them.

## Problem and opportunity

macOS has no free, open-source, native download accelerator; users choose between slow browser downloads and non-native or closed tools.

### User pain points

- Browser downloads use one connection, so large files are slow on fast links and on servers that throttle per connection.
- A network drop, Wi-Fi switch, sleep or browser quit often kills the download; restarting a 20 GB file wastes hours.
- No queueing, scheduling or bandwidth control: big downloads saturate the link during calls and work.
- Downloads land unsorted in `~/Downloads`.
- No good way to script downloads from Terminal with a GUI to watch them.

### Competitive landscape

| Product | Platform / tech | License | Gap Rocket fills |
| --- | --- | --- | --- |
| Internet Download Manager (IDM) | Windows only | Paid, closed | The benchmark power users want; no Mac version |
| Free Download Manager (FDM) | Cross-platform, Qt | Free, closed | Not native; heavy for a Mac utility |
| Motrix | Electron + aria2 | Open source | Electron footprint; not Mac-native |
| Brisk | Flutter/Dart, desktop | Open source (GPL-3.0) | Cross-platform UI, not Mac-native |
| Folx | macOS native | Freemium, closed | Key features paywalled; closed source |
| Downie | macOS native | Paid, closed | Video-site focus, not a general accelerator |
| aria2 / wget / curl | CLI | Open source | Powerful but no Mac UI, no browser capture |

Competitor details reflect the team's knowledge as of November 2026 and were not independently re-verified for this draft.

### Positioning

For Mac users who download large files often, Rocket is the download manager that makes them faster and unbreakable. Unlike cross-platform or closed tools, it is fully native, lightweight, scriptable and open source.

## Goals, non-goals and success metrics

v1.0 succeeds when Rocket is measurably faster than Safari on large files, never corrupts a download, and attracts outside contributors.

### Goals

1. **G1 Speed:** saturate a 1 Gbps link on a single large file from a server that allows parallel ranges.
2. **G2 Reliability:** every interrupted download resumes, or restarts with a clear reason; zero silent corruption.
3. **G3 Control:** queues, scheduling, speed limits and rules cover the core IDM workflow.
4. **G4 Integration:** capture downloads from Safari, Chrome and Firefox; full CLI and URL scheme.
5. **G5 Native quality:** feels like an Apple-built utility; light on CPU, memory and battery.
6. **G6 Healthy project:** documented, tested, easy to contribute to, with a predictable release cadence.

### Non-goals for v1.0

- BitTorrent, magnet links, or other peer-to-peer protocols.
- Downloading video or audio streams from websites (yt-dlp-style extraction).
- Windows, Linux or iOS versions.
- Accounts, cloud sync or any server operated by the project.
- Mac App Store distribution (designed to stay possible; see TRD).
- FTP/SFTP (planned after 1.0 through the protocol layer).

### Success metrics

Rocket collects no telemetry, so metrics come from benchmarks, CI and public signals.

| Metric | Target at v1.0 | Source |
| --- | --- | --- |
| Speed-up vs. Safari, 5 GB file, parallel-capable server | at least 3x on a link where one connection caps below 30% of bandwidth | Benchmark suite |
| Throughput vs. aria2 (same file, same connections) | at least 95% | Benchmark suite |
| Resume success after kill, sleep, network drop | 100% of resumable servers in the test matrix | Integration tests |
| Corrupted completed files | 0 | Checksum tests, issue tracker |
| Daemon idle footprint | 0% CPU, under 20 MB memory | Instruments, CI |
| Crash-free sessions (opt-in reports only) | at least 99.5% | Opt-in crash reports |
| GitHub stars, 6 months after 1.0 | 2,000 | GitHub |
| External contributors with merged PRs by 1.0 | 10 | GitHub |
| Median first response to new issues | under 72 hours | GitHub |

## Target users and personas

The primary user downloads large files often and cares about speed and control; v1.0 is designed for them first.

| Persona | Who | Typical downloads | Needs most | Priority |
| --- | --- | --- | --- | --- |
| Power downloader ("Sara") | Former Windows/IDM user, tech-savvy | ISOs, games, datasets, 1–100 GB | Acceleration, resume, queues, browser capture | Primary |
| Developer ("Arash") | Engineer, lives in Terminal | Toolchains, Xcode, ML models, SDKs | CLI, scripting, checksums, reliability | Primary |
| Creative pro ("Lena") | Video/3D/audio work | Asset packs, footage, sample libraries | Scheduling, speed limits during calls, auto-sorting | Secondary |
| Constrained connection ("Omid") | Slow, unstable or metered internet | Anything large | Resume after drops, overnight scheduling, bandwidth caps | Secondary |
| Contributor | Swift/macOS developer | — | Clear architecture, docs, good first issues | Project stakeholder |

All personas expect a Mac-native look, Dark Mode, keyboard shortcuts, and no account or tracking.

## Key user journeys

Six journeys define v1.0; each maps to functional requirements in the next section.

1. **J1 Capture from the browser.** Sara clicks a download link in Chrome. The extension hands it to Rocket, which shows the file name, size and destination and starts with 8 connections. The browser's own download is cancelled. (FR-BRW, FR-ENG)
2. **J2 Paste and go.** Arash copies a URL. Rocket's clipboard watcher offers it in a small prompt; one click or Return starts it. (FR-INT-03, FR-ADD)
3. **J3 Survive interruptions.** Omid's Wi-Fi drops at 70% and the Mac sleeps overnight. On wake, Rocket validates the server copy is unchanged and resumes from 70%. If the file changed, it explains why and restarts. (FR-ENG-05..08)
4. **J4 Schedule overnight.** Lena adds five asset packs to a "Night" queue that runs 01:00–07:00 with 2 parallel downloads, then sleeps the Mac when done. (FR-QUE)
5. **J5 Script it.** Arash runs `rocket add <url> --dir ~/Models --sha256 <hash> --wait` in a build script. The download appears in the app UI and the command exits 0 only if the checksum matches. (FR-INT-01, FR-ENG-10)
6. **J6 Stay out of the way.** During a video call Lena sets a 2 MB/s global cap from the menu bar; downloads continue in the background after she quits the main window. (FR-SPD, FR-APP-04)

## Functional requirements

Requirements are numbered by area, prioritized with MoSCoW (Must / Should / Could), and assigned to the milestone that first ships them. Everything marked Must is required for v1.0.

### Adding downloads (FR-ADD)

| ID | Requirement | Priority | Milestone |
| --- | --- | --- | --- |
| FR-ADD-01 | Add one or many URLs via a dialog, paste, or drag and drop of links and `.txt` lists | Must | v0.1 |
| FR-ADD-02 | Before starting, show file name, size, type, resumability and destination; allow rename and folder change | Must | v0.1 |
| FR-ADD-03 | Detect duplicates (same URL or same target path) and offer: open existing, rename, overwrite, skip | Must | v0.1 |
| FR-ADD-04 | Support custom request headers, cookies, referrer and HTTP Basic auth per download | Should | v0.2 |
| FR-ADD-05 | Batch add with patterns (`file[001-100].zip`) | Could | post-1.0 |

### Download engine (FR-ENG)

| ID | Requirement | Priority | Milestone |
| --- | --- | --- | --- |
| FR-ENG-01 | Download HTTP and HTTPS (HTTP/1.1, HTTP/2, HTTP/3 where the system supports it) | Must | v0.1 |
| FR-ENG-02 | Split files across parallel connections (default 8, user range 1–16) when the server supports range requests | Must | v0.1 |
| FR-ENG-03 | Rebalance dynamically: a finished connection takes over half of the largest remaining part | Must | v0.1 |
| FR-ENG-04 | Fall back to a single connection when ranges are unsupported, and say so in the UI | Must | v0.1 |
| FR-ENG-05 | Pause and resume any download; state survives app quit, daemon restart, reboot and crash | Must | v0.1 |
| FR-ENG-06 | Validate on resume that the remote file is unchanged (ETag / Last-Modified); restart with a stated reason if not | Must | v0.1 |
| FR-ENG-07 | Retry transient failures automatically with exponential backoff (default 5 attempts) | Must | v0.1 |
| FR-ENG-08 | Resume automatically after network loss and wake from sleep | Must | v0.1 |
| FR-ENG-09 | Handle redirects, expired links (offer "refresh URL" keeping progress), and disk-full errors gracefully | Must | v0.2 |
| FR-ENG-10 | Verify checksums (MD5, SHA-1, SHA-256) when provided | Should | v0.3 |
| FR-ENG-11 | Honor system proxy settings and allow a per-app proxy (HTTP, HTTPS, SOCKS5) | Should | v0.2 |
| FR-ENG-12 | Reduce connections automatically when a server rejects or rate-limits them | Must | v0.1 |

### Queues and scheduling (FR-QUE)

| ID | Requirement | Priority | Milestone |
| --- | --- | --- | --- |
| FR-QUE-01 | A default queue plus user-created named queues | Must | v0.2 |
| FR-QUE-02 | Per-queue limit on simultaneous downloads | Must | v0.2 |
| FR-QUE-03 | Reorder downloads within and between queues by drag and drop | Must | v0.2 |
| FR-QUE-04 | Schedule queues by start/stop time and weekdays | Must | v0.2 |
| FR-QUE-05 | Post-queue actions: notify, sleep, shut down, quit Rocket, run a Shortcut | Should | v0.2 |
| FR-QUE-06 | Prevent system sleep while downloads are active (user setting, off by default on battery) | Should | v0.2 |

### Speed limits and rules (FR-SPD, FR-ORG)

| ID | Requirement | Priority | Milestone |
| --- | --- | --- | --- |
| FR-SPD-01 | Global download speed limit, changeable live from the menu bar | Must | v0.2 |
| FR-SPD-02 | Per-download and per-queue speed limits | Should | v0.2 |
| FR-SPD-03 | Time-based speed profiles (e.g. limited 09:00–18:00) | Could | post-1.0 |
| FR-ORG-01 | Auto-sort completed files into folders by category (Video, Archives, Documents, Apps, Music, Images, Other) | Must | v0.2 |
| FR-ORG-02 | User rules by domain, file extension and size: destination folder, queue, connection count, speed limit | Should | v0.2 |
| FR-ORG-03 | Optional actions on completion: open, reveal in Finder, unpack archive, move to Trash after N days | Could | post-1.0 |

### Integrations (FR-INT, FR-BRW)

| ID | Requirement | Priority | Milestone |
| --- | --- | --- | --- |
| FR-INT-01 | `rocket` CLI: add, list, pause, resume, cancel, wait, queue, config; human and JSON output; meaningful exit codes | Must | v0.3 |
| FR-INT-02 | `rocket://` URL scheme to add downloads from other apps | Must | v0.3 |
| FR-INT-03 | Clipboard watcher that offers copied downloadable URLs (opt-in, filter by extension list) | Should | v0.3 |
| FR-INT-04 | Shortcuts / App Intents: add download, pause all, resume all, get status | Should | v0.3 |
| FR-INT-05 | Services menu item "Download with Rocket" | Could | v0.3 |
| FR-BRW-01 | Safari Web Extension capturing downloads and offering "Download with Rocket" in the context menu | Must | v0.4 |
| FR-BRW-02 | Chrome (and Chromium browsers) and Firefox extensions with the same features | Must | v0.4 |
| FR-BRW-03 | Pass cookies, referrer and user agent from the browser so authenticated downloads work | Must | v0.4 |
| FR-BRW-04 | Capture filters: minimum file size, extension list, per-site on/off, and a modifier key to bypass | Should | v0.4 |

### App experience (FR-APP)

| ID | Requirement | Priority | Milestone |
| --- | --- | --- | --- |
| FR-APP-01 | Main window: sidebar (queues, categories, status filters) and a download list with name, size, progress, speed, ETA, status | Must | v0.1 |
| FR-APP-02 | Detail view per download: URL, segments visualization, connection count, headers, errors, log | Should | v0.2 |
| FR-APP-03 | Menu bar extra with aggregate speed, active downloads, pause/resume all, speed limit | Must | v0.2 |
| FR-APP-04 | Downloads continue after the main window or app is closed (background agent) | Must | v0.1 |
| FR-APP-05 | Native notifications on completion and failure, with actions (Open, Reveal, Retry) | Must | v0.1 |
| FR-APP-06 | Dock icon progress and badge (can be hidden) | Should | v0.2 |
| FR-APP-07 | Search, sort and filter history; clear completed; remove with or without deleting files | Must | v0.2 |
| FR-APP-08 | Settings: defaults for folder, connections, queues, limits, capture, notifications, launch at login | Must | v0.1 |
| FR-APP-09 | Export and import settings, queues and rules as JSON | Could | post-1.0 |
| FR-APP-10 | Automatic updates via Sparkle with signed release notes; users can opt out | Must | v0.1 |

## Non-functional requirements

These are the product-level qualities users will notice; the TRD turns each into measurable engineering targets and tests.

| ID | Area | Requirement |
| --- | --- | --- |
| NFR-01 | Performance | Saturate a 1 Gbps link on one large file from a parallel-capable server; at least 95% of aria2 throughput |
| NFR-02 | Footprint | Background agent idle: 0% CPU, under 20 MB memory; active: under 5% CPU at 500 Mbps on Apple Silicon |
| NFR-03 | Responsiveness | App launch to usable window under 500 ms; smooth scrolling with 10,000 history items; UI never blocks on network or disk |
| NFR-04 | Reliability | No data loss on crash, force quit, power loss or reboot; zero silently corrupted completed files |
| NFR-05 | Energy | No wake-ups when idle; respects Low Power Mode by lowering progress update frequency |
| NFR-06 | Privacy | No telemetry or analytics by default; crash reports opt-in only; no network calls except downloads and update checks |
| NFR-07 | Security | Signed, notarized, hardened runtime; downloaded files carry the macOS quarantine flag so Gatekeeper checks them |
| NFR-08 | Accessibility | Full VoiceOver support, keyboard navigation for every action, Dynamic Type where available, sufficient contrast, Reduce Motion respected |
| NFR-09 | Localization | All strings in String Catalogs from day one; English at v1.0, community translations after; right-to-left layouts supported |
| NFR-10 | Compatibility | macOS 14 Sonoma or later; Apple Silicon and Intel (universal binary) |
| NFR-11 | Native look | Follows Apple Human Interface Guidelines; Light/Dark Mode; standard menus, shortcuts and window behavior |
| NFR-12 | Upgrades | Settings and history migrate across all versions automatically; no manual steps |

## Open-source and community

Rocket is MIT licensed, developed in public on GitHub, and governed by its maintainer until a core team forms.

| Topic | Decision | Why |
| --- | --- | --- |
| License | MIT License | Short, permissive and widely understood; keeps a future App Store build possible (GPL would not) |
| Contributions | Developer Certificate of Origin (DCO) sign-off on every commit; no CLA | Low friction, legally clear provenance |
| Governance | Maintainer-led (neysidev) at start; documented path to a core team after 1.0 in `GOVERNANCE.md` | Fast decisions early, shared ownership later |
| Code of conduct | Contributor Covenant 2.1 | Industry standard, enforceable |
| Name and logo | "Rocket" name and logo reserved by the maintainer; forks must rebrand | Prevents confusing or malicious look-alike builds |
| Distribution | Signed, notarized DMG on GitHub Releases; Homebrew cask `rocket-downloader`; Sparkle updates | Trusted channels Mac users already use |
| Funding | GitHub Sponsors; the app stays free with no paid tier | Sustainability without paywalls |
| Communication | GitHub Issues (bugs), Discussions (ideas, Q&A), public roadmap project board | Everything in one public place |
| Security reports | Private reporting via GitHub Security Advisories; policy in `SECURITY.md` | Coordinated disclosure |

### Community goals for v1.0

- A newcomer can build and run the app from a fresh clone in under 10 minutes using `CONTRIBUTING.md`.
- At least 20 issues labeled `good first issue` at any time.
- Every architectural decision recorded as an ADR in `docs/adr/`.
- New issues get a first response within 72 hours; PRs get a first review within 7 days.

## Release plan and roadmap

Rocket ships in four public pre-releases before v1.0, so users get value early and contributors can join from v0.1. A milestone ships only when its gate passes; there are no fixed dates.

&#91;embedded content: Release roadmap · 5 milestones, 4 gates\]

Each milestone is a GitHub milestone with its FR IDs attached. Pre-releases go to a `beta` Sparkle channel; v1.0 and later go to `stable`.

### After 1.0 (direction, not commitments)

- FTP/SFTP through the protocol layer; BitTorrent evaluated only if it fits the architecture cleanly.
- Time-based speed profiles, batch URL patterns, post-download actions (FR-SPD-03, FR-ADD-05, FR-ORG-03).
- Settings export/import; an import tool for Folx and FDM.
- Optional Mac App Store edition if sandbox constraints allow feature parity.
- Community translations.

## Risks, assumptions and open questions

The largest risks are maintainer capacity and the cost of keeping three browser extensions working.

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Single maintainer (bus factor of 1) | Project stalls | Strong docs and ADRs, modular code, recruit co-maintainers from top contributors |
| Browser extension APIs change (Manifest V3, Safari) | Capture breaks | One shared extension codebase (WebExtensions), thin per-browser shims, CI smoke tests per browser |
| Servers that block parallel connections | Acceleration appears not to work | Automatic backoff (FR-ENG-12), per-site connection rules, clear UI message |
| Name collision with existing `Rocket.app` | User confusion, install overwrite | Bundle file `Rocket Downloader.app`, cask `rocket-downloader`, unique bundle ID |
| Apple platform changes (SMAppService, notarization rules) | Background agent or install breaks | Track betas each June; test on the next macOS beta in CI |
| Use for infringing downloads | Reputation, legal noise | General-purpose tool, no site-specific extractors; clear acceptable-use note |

### Assumptions

- Most target downloads are from HTTP/HTTPS servers that support range requests (CDNs, mirrors, cloud storage).
- Users accept a one-time approval of the background agent in System Settings > Login Items.
- An Apple Developer Program membership is available for signing and notarization.

### Open questions

- [ ] Does the maintainer own a personal domain? If so, switch the bundle ID from `io.github.neysidev.rocket` before the first public release; it cannot change later.
- [ ] Opt-in crash reporting: Apple's built-in reports only, or a self-hosted, open-source collector?
- [ ] Should v1.0 include a minimal "import from Folx / FDM" for history and queues?

## Glossary

| Term | Meaning |
| --- | --- |
| Segment | One byte range of a file downloaded over its own connection |
| Dynamic segmentation | Splitting the largest remaining segment when a connection becomes free, so all connections stay busy |
| Range request | HTTP request for part of a file (`Range: bytes=a-b`); required for acceleration and resume |
| ETag / Last-Modified | Server validators used to confirm a file has not changed before resuming |
| Background agent (`rocketd`) | The process that runs downloads independently of the app window |
| Queue | An ordered list of downloads with its own concurrency limit and schedule |
| Rule | A user condition (domain, extension, size) that sets folder, queue, connections or speed |
| Notarization | Apple's automated malware scan required for apps distributed outside the App Store |
| MoSCoW | Prioritization: Must, Should, Could, Won't (this release) |
