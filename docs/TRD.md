# Rocket — Technical Requirements Document (TRD)

Nov 5, 2026 · @Mehdi

Rocket is a Swift 6 macOS app whose downloads run in a separate background agent (`rocketd`) behind a versioned XPC API, with a dependency-free core engine built on URLSession and GRDB. This TRD specifies how the PRD's requirements are built, measured and maintained.

## Document control and key decisions

| Field | Value |
| --- | --- |
| Document | Technical Requirements Document, v1.0 draft |
| Status | Draft for review |
| Owner | Mehdi (neysidev), maintainer |
| Companion | Rocket PRD (requirement IDs FR-\* and NFR-\* referenced here) |
| Keywords | MUST / SHOULD / MAY as in RFC 2119 |

Each decision below becomes an ADR in `docs/adr/` (MADR format) before v0.1.

| ADR | Decision | Main alternative rejected | Reason |
| --- | --- | --- | --- |
| 0001 | Swift 6, strict concurrency, macOS 14+ | macOS 13 support | `@Observable`, mature SwiftUI, compile-time data-race safety |
| 0002 | Direct distribution first (Developer ID, notarized, Sparkle, Homebrew); sandbox-compatible design | App Store first | App Store sandbox blocks CLI, native messaging and free folder access |
| 0003 | Downloads run in a LaunchAgent daemon (`rocketd`); app, CLI, extensions are XPC clients | Engine inside the app | Downloads survive UI quit, crash and update |
| 0004 | Networking on URLSession behind a `HTTPTransport` protocol | SwiftNIO, libcurl | System TLS, proxies, HTTP/2 and HTTP/3 for free; swappable |
| 0005 | Persistence with GRDB (SQLite) in the daemon | SwiftData, Core Data | Explicit migrations, Sendable records, cheap frequent writes |
| 0006 | Dynamic segmentation (split largest remaining range) | Static N-way split | Keeps every connection busy to the end |
| 0007 | Minimal dependencies: GRDB, Sparkle, swift-argument-parser only in shipped code | Allowing convenience packages | Supply-chain and maintenance risk |
| 0008 | MIT license with DCO sign-off | Apache-2.0, GPL-3.0 | Simplest permissive license; keeps App Store option open |
| 0009 | Ports-and-adapters module layout with one-way dependencies | Single app target | Testability, parallel contribution, clear ownership |
| 0010 | Bundle ID `io.github.neysidev.rocket` | — | No personal domain confirmed yet; must be final before v0.1 |

## System architecture

Rocket runs as two long-lived processes: the app (UI only) and the `rocketd` agent (all downloads). Every other entry point is a thin client of the agent.

&#91;embedded content: Process architecture · 4 clients, 1 agent, 3 adapters\]

The agent owns the engine, the database and every file write; clients send commands and render coalesced snapshots. Because the agent is registered with `SMAppService`, downloads continue after the app quits, crashes or updates (FR-APP-04).

| Process | Bundle location | Lifetime |
| --- | --- | --- |
| `Rocket Downloader.app` | `/Applications` | While the user has it open |
| `rocketd` | `Contents/MacOS/rocketd`, plist in `Contents/Library/LaunchAgents` | Launched on demand by launchd; exits after 60 s idle with no work and no clients |
| `rocket` CLI | `Contents/Helpers/rocket` | One command |
| `rocket-native-host` | `Contents/Helpers/rocket-native-host` | Launched by Chrome/Firefox per message session |
| Safari Web Extension | `Contents/PlugIns` | Managed by Safari |

## Module structure and dependency rules

The code is a ports-and-adapters design: `RocketCore` defines protocols (ports), adapters implement them, and only the app targets wire concrete types together.

&#91;embedded content: Module layers · ports and adapters\]

### Rules (enforced in CI)

- Dependencies point downward only; a module never imports a sibling in its layer, except `RocketEngine` and the adapters may share types through `RocketCore`.
- `RocketCore` and `RocketEngine` import no third-party packages and no AppKit/SwiftUI, so the engine is fully testable on its own.
- Third-party packages are confined to one module each: GRDB in `RocketPersistence`, Sparkle in the app, swift-argument-parser in the CLI.
- Every module has its own test target (`<Module>Tests`); public API is the minimum needed (`internal` by default, `package` access for cross-module internals).

### Repository layout

```
rocket/
├── Rocket.xcodeproj           app, agent, extension and host targets
├── Package.swift              all library modules (SPM)
├── App/                       SwiftUI app target
├── Agent/                     rocketd executable
├── Extensions/
│   ├── Shared/                WebExtension JavaScript (all browsers)
│   ├── SafariExtension/
│   └── NativeHost/            rocket-native-host
├── Sources/
│   ├── RocketCore/
│   ├── RocketEngine/
│   ├── RocketNetworking/
│   ├── RocketPersistence/
│   ├── RocketIPC/
│   └── RocketCLI/             executable product `rocket`
├── Tests/                     <Module>Tests, RocketTestServer (dev only)
├── Benchmarks/
├── docs/                      adr/, architecture/, product/
└── README.md, LICENSE, NOTICE, CONTRIBUTING.md, CODE_OF_CONDUCT.md,
    SECURITY.md, GOVERNANCE.md, CHANGELOG.md
```

## Download engine

Each download is a state machine owned by one `DownloadCoordinator`; states and transitions are a Swift enum in `RocketCore`, so illegal transitions do not compile.

&#91;embedded content: Download lifecycle · 8 states\]

Any state can also move to Cancelled (user action), which deletes the `.rocketpart` file unless the user keeps it.

### Probe

1. Send `GET` with `Range: bytes=0-0` (fall back to `HEAD` only if the server rejects it).
2. Record final URL after redirects, total size, `Accept-Ranges`/`206` support, `ETag`, `Last-Modified`, `Content-Disposition` file name and content type.
3. Decide mode: segmented (size known and ranges supported) or single-stream (otherwise; resume only if ranges are supported).

### Dynamic segmentation

1. Start with N connections (default 8, per-host max 16), each taking an equal range.
2. When a worker finishes, it finds the active segment with the most bytes remaining; if that remainder is over 2 MiB, it splits it at the midpoint and takes the upper half.
3. Minimum segment size is 1 MiB; small files use fewer connections.
4. On HTTP 429/503 or connection resets, the `ConnectionPolicy` lowers the host's connection count and retries with exponential backoff and jitter (1 s base, 60 s cap, 5 attempts).
5. Slow-segment detection: a worker below 10% of the median segment speed for 15 s is restarted on a new connection.

### Resume and integrity

- On resume, every request carries `If-Range` with the stored ETag (or Last-Modified); a `200` instead of `206` means the file changed, so the download restarts and the user is told why.
- Checkpoints store per-segment offsets only after bytes are durable (TRD Persistence).
- Verification step: confirm final size; if a checksum was supplied, hash the file with CryptoKit (streamed, off the main actor).
- Completion: `fsync`, atomic rename from `.rocketpart` to the final name, set quarantine and `kMDItemWhereFroms` attributes, then notify.

### Error classes

| Class | Examples | Behavior |
| --- | --- | --- |
| Transient | timeout, connection reset, 5xx, 429, network lost | Retry with backoff; resume on network return |
| Needs user | 401/403, link expired (410, signed-URL expiry), disk full, file changed | Fail with a specific reason and a fix-it action (sign in, refresh URL, free space, restart) |
| Fatal | 404, invalid URL, destination not writable, checksum mismatch | Fail immediately with reason; no retry |

## Concurrency model

All code compiles in the Swift 6 language mode with complete strict-concurrency checking; data races are compile errors, not runtime bugs.

| Component | Isolation | Responsibility |
| --- | --- | --- |
| `DownloadScheduler` | actor (one per daemon) | Applies queues, schedules and concurrency limits; starts and stops coordinators |
| `DownloadCoordinator` | actor (one per active download) | Owns a download's state machine and its segment plan; runs segment workers in a `TaskGroup` |
| `SegmentWorker` | child task | Streams one byte range from `HTTPTransport` to the file sink |
| `BandwidthLimiter` | actor | Token bucket shared by all workers (global, queue and per-download buckets) |
| `ProgressAggregator` | actor | Coalesces byte counts and publishes snapshots to clients at 5 Hz (1 Hz in Low Power Mode) |
| `CheckpointWriter` | actor | Batches segment offsets to GRDB every 2 s or 8 MiB, and immediately on pause or shutdown |
| UI view models | `@MainActor`, `@Observable` | Render daemon snapshots; never touch network or disk |

### Rules

- **Structured concurrency only.** No `Task.detached`, no unowned background tasks; every task has a parent that cancels it.
- **Cancellation is cooperative and prompt.** Pause or cancel cancels the coordinator's task group; workers check `Task.isCancelled` between chunks and flush their offset before exiting.
- **Backpressure.** A worker does not request more data while its write buffer (max 4 MiB per connection) is full; the limiter suspends workers instead of dropping data.
- **No blocking calls on actors.** File writes run on a dedicated serial I/O executor so actors never block on `pwrite` or `fsync`.
- **Sendable boundaries.** Only `Sendable` value types (DTOs, records) cross actor, process and module boundaries.
- **No locks in feature code.** `Mutex` from the Synchronization module is allowed only in low-level types with a documented reason.

## Persistence and data model

Only the daemon opens the database: one SQLite file in WAL mode at `~/Library/Application Support/io.github.neysidev.rocket/rocket.sqlite`, accessed through GRDB behind repository protocols.

| Table | Key columns | Notes |
| --- | --- | --- |
| `download` | id (UUID), url, finalURL, destinationPath, fileName, totalBytes, state, queueId, connections, speedLimit, etag, lastModified, checksumKind, checksum, createdAt, completedAt, errorCode | One row per download; `state` is the lifecycle enum |
| `segment` | id, downloadId, start, end, received, state | Rewritten by checkpoints; deleted when the download completes |
| `queue` | id, name, maxActive, scheduleJSON, postAction, sortOrder | The default queue always exists |
| `rule` | id, matchJSON, actionJSON, priority, enabled | Domain / extension / size matching |
| `requestContext` | downloadId, headersJSON, cookiesRef, referrer, userAgent | Cookies stored as a Keychain reference, never in plain SQLite |
| `setting` | key, valueJSON | Daemon-side settings; UI-only preferences live in `UserDefaults` |

### Requirements

- **Migrations** are append-only GRDB migrations (`v1_createDownload`, …), never edited after release, each with an upgrade test from every prior released schema.
- **Crash safety:** writes are transactional; a checkpoint records an offset only after its bytes are written and `fsync`ed, so the database never claims bytes the disk lacks.
- **Partial files** live next to the destination as `<name>.rocketpart` with an extended attribute holding the download ID; completion is an atomic `rename`.
- **Retention:** completed history is kept until the user clears it; an optional auto-clear after N days.
- **Repositories** (`DownloadRepository`, `QueueRepository`, `RuleRepository`) are protocols in `RocketCore`; GRDB adapters live in `RocketPersistence`; tests use in-memory adapters.

## IPC and integrations

Every client talks to `rocketd` through one typed, versioned XPC API defined in `RocketIPC`; no client links the engine or opens the database.

### XPC API

- **Transport:** the Swift `XPCSession` / `XPCListener` API (macOS 14+) with `Codable` messages; Mach service `TEAMID.io.github.neysidev.rocket.agent`, registered by the app via `SMAppService.agent(plistName:)`.
- **Commands:** `add`, `pause`, `resume`, `cancel`, `remove`, `reorder`, `setLimit`, `queue.*`, `rule.*`, `settings.*`, `snapshot`.
- **Events:** clients subscribe and receive coalesced `DownloadSnapshot` batches (5 Hz) plus discrete events (completed, failed, needsAttention).
- **Versioning:** every message carries `apiVersion`. Minor versions add optional fields only; a major version bump requires an ADR. The daemon supports the current and previous major version.
- **Trust:** the daemon accepts connections only from code signed by the same Team ID (code-signing requirement checked per connection); everything else is rejected and logged.

### Clients

| Client | Mechanism | Notes |
| --- | --- | --- |
| App | `RocketIPC` client SDK | Relaunches the agent if it is not running |
| CLI `rocket` | `RocketIPC` client SDK; swift-argument-parser | Shipped in `Contents/Helpers`; installed to PATH by Homebrew or a menu command. `--json` output with a versioned schema. Exit codes: 0 ok, 1 failed, 2 usage, 3 agent unavailable, 4 checksum mismatch |
| URL scheme | `rocket://add?url=…&dir=…` | Handled by the app; always confirms before starting (prevents drive-by downloads from web pages) |
| Safari | Safari Web Extension; its app extension forwards to the daemon over XPC | Shares the WebExtension JavaScript codebase |
| Chrome / Firefox | WebExtension + native messaging host `rocket-native-host` (stdio JSON) forwarding over XPC | Host manifests installed per browser by the app; allowed extension IDs pinned |
| Shortcuts | App Intents in the app | Add, pause all, resume all, status |
| Clipboard | App-side watcher, opt-in | Polls `NSPasteboard.changeCount` at 1 Hz only while enabled |

## Performance requirements

Performance is a feature with budgets enforced in CI; a pull request that breaks a budget by more than 5% fails.

| ID | Metric | Budget | Measured by |
| --- | --- | --- | --- |
| PERF-01 | Single-file throughput, local server, 1 Gbps shaped link | at least 940 Mbps sustained | Benchmark suite |
| PERF-02 | Throughput vs. aria2, same file and connection count | at least 95% | Benchmark suite |
| PERF-03 | Daemon CPU at 500 Mbps (Apple Silicon M1 baseline) | under 5% of one core | `os_signpost` + CI sampling |
| PERF-04 | Daemon memory while downloading | under 50 MB + 4 MiB per active connection | Instruments, `footprint` in CI |
| PERF-05 | Daemon idle | 0% CPU, under 20 MB, no timer wake-ups | Activity Monitor energy, CI |
| PERF-06 | App cold launch to interactive | under 500 ms | XCTest launch metric |
| PERF-07 | Scrolling 10,000 history rows | no dropped frames at 120 Hz | XCTest scroll metric |
| PERF-08 | Time to first byte after "Start" | under 100 ms plus network latency | Benchmark suite |
| PERF-09 | Checkpoint write cost | under 1 ms per checkpoint | Unit benchmark |

### Engineering techniques (required)

- Receive data through `URLSessionDataDelegate` chunks; never iterate `URLSession.bytes` byte by byte.
- Preallocate the file (`F_PREALLOCATE`, then `ftruncate`) and write each segment with `pwrite` at its offset; no single-writer bottleneck.
- Set `F_NOCACHE` on large files so downloads do not evict useful page cache.
- Reuse buffers; avoid per-chunk `Data` copies on the hot path.
- Coalesce progress to 5 Hz; the UI diffs snapshots rather than reloading lists.
- Network conditions for tests are simulated with macOS `dnctl`/`pfctl` dummynet: latency, bandwidth caps, packet loss.

## Scalability and extensibility

The architecture grows by adding adapters behind existing protocols, not by editing the engine.

- **New protocols** (FTP, SFTP, later possibly BitTorrent) implement a `DownloadSource` protocol: `probe() -> RemoteFileInfo`, `stream(range:) -> AsyncThrowingStream<Chunk>`, `capabilities` (ranges, resume, validators). The engine selects a source by URL scheme through a `SourceRegistry`. HTTP is the first implementation.
- **Engine policies are strategies:** `SegmentationStrategy`, `RetryPolicy`, `ConnectionPolicy` (per-host limits, backoff) are protocols with default implementations, so tuning or experiments never fork the coordinator.
- **Post-download actions** (unpack, checksum, move, open) run as a pipeline of `PostProcessor` steps, added without touching download code.
- **Load targets:** the daemon handles 10,000 history items, 500 queued and 32 concurrently active downloads (up to 512 connections) without exceeding PERF-04.
- **Hosts:** connection limits and backoff are tracked per host, so one slow mirror never starves others.
- **API stability:** the XPC API, CLI JSON schema and URL scheme are public contracts with semantic versioning and deprecation notices one minor release ahead.
- **Feature flags:** unfinished features ship dark behind compile-time flags in `RocketCore.FeatureFlags`, so `main` is always releasable.

## Security and privacy

Rocket handles untrusted URLs, untrusted server responses and sometimes user credentials, so every boundary is treated as hostile.

### Threat model

| Threat | Control |
| --- | --- |
| Malicious web page triggers downloads via `rocket://` | URL scheme always requires user confirmation; no silent starts |
| Another local process drives the daemon | XPC peer code-signing check (same Team ID); unsigned or foreign clients rejected |
| Rogue browser extension uses the native host | Native host manifests pin Rocket's extension IDs only |
| Path traversal via server file names (`../`, absolute paths) | File names sanitized; destination must resolve inside the chosen folder |
| Downloaded malware runs without checks | `com.apple.quarantine` extended attribute set on every completed file, with source URL |
| Tampered or swapped file on resume | ETag / Last-Modified validation; optional checksums |
| TLS downgrade or bad certificates | System trust only; no option to disable certificate validation |
| Credential leakage | Cookies and passwords in Keychain; never logged; redacted in diagnostics exports |
| Compromised update | Sparkle EdDSA-signed appcast and archives, served over HTTPS; notarized builds |
| Supply-chain attack via dependencies | Three pinned dependencies, `Package.resolved` committed, Dependabot alerts, license check in CI |

### Platform hardening

- Developer ID signing, hardened runtime, notarization and stapling for the app, agent, CLI and native host.
- Minimal entitlements; no JIT, no disabled library validation. Each entitlement justified in an ADR.
- Folder access stored as security-scoped bookmarks, so a sandboxed build later needs no redesign.

### Privacy

- No analytics, no tracking, no accounts. Network traffic is limited to user downloads and the Sparkle update check (which sends no system profile).
- Crash reports are opt-in. Logs stay on the Mac and redact URLs' query strings by default.
- A `PrivacyInfo.xcprivacy` manifest documents all required-reason API usage.

## Testing strategy

Most confidence comes from fast, deterministic engine tests against fakes; slower tests prove the real system end to end.

| Layer | Scope | Tools | Runs |
| --- | --- | --- | --- |
| Unit | Core models, state machine, segment planner, limiter, rules, parsers | Swift Testing (`@Test`), in-memory fakes, `FakeClock` | Every PR, under 60 s |
| Engine integration | Coordinator + real file I/O + `MockHTTPTransport` scripting faults | Swift Testing | Every PR |
| Network integration | Real URLSession against `RocketTestServer` (ranges, ETag changes, 503/429, drops at byte N, slow and lossy links) | Swift Testing, dummynet shaping | Every PR (core matrix), nightly (full) |
| Persistence | Migrations from every released schema; crash-consistency of checkpoints | GRDB in-memory and on-disk | Every PR |
| IPC contract | Encode/decode of every message for current and previous API version | Swift Testing, golden JSON files | Every PR |
| Resilience | Force-kill the agent mid-download, kill during checkpoint, fill the disk, sleep/wake | Scripted harness | Nightly |
| UI | Core journeys J1–J6, accessibility audit | XCUITest, `performAccessibilityAudit()` | Nightly, release |
| Performance | PERF-01..09 | XCTest metrics, benchmark harness vs. aria2 | Nightly, release, on `perf`-labeled PRs |
| Fuzzing | Header parsing, file-name sanitizing, URL-scheme parsing | libFuzzer via `-sanitize=fuzzer` | Nightly |

### Requirements

- Line coverage: at least 90% for `RocketCore` and `RocketEngine`, at least 80% overall; coverage may not drop on a PR.
- Every bug fix lands with a regression test that fails before the fix.
- Tests are deterministic: no real time, no randomness without a seed, no public internet.
- Thread Sanitizer and Address Sanitizer run on the unit and integration suites nightly.
- `RocketTestServer` is a development-only target and may use SwiftNIO; it never ships.

## Code quality and engineering standards

Standards are enforced by tools in CI, so reviews focus on design rather than style.

### Design principles

- **SOLID, applied pragmatically:** small single-purpose types; depend on protocols defined by the consumer (ports), not on concrete adapters; no protocol without at least two conformers (a fake counts).
- **Value types first:** structs and enums for models; classes only for identity or reference semantics; actors for shared mutable state.
- **Make illegal states unrepresentable:** download state is an enum with associated values, not flags.
- **Errors are typed:** each module exposes its own error enum; user-facing messages are mapped in one place and localized.
- **No singletons** except system ones; dependencies are injected through initializers and a composition root per process.

### Naming and style

- Swift API Design Guidelines; conventions recorded in the founding decision log (module prefixes `Rocket*`, adapters named `<Technology><Protocol>`, no `Manager`/`Helper` suffixes, one primary type per file).
- `swift-format` (formatting) and SwiftLint (rules) with configs in the repo; both run as pre-commit hooks and in CI.
- Documentation comments (`///`) on every public symbol; DocC catalogs for `RocketCore`, `RocketEngine` and `RocketIPC`.

### Limits checked in CI

| Check | Limit |
| --- | --- |
| Function body length | 60 lines (warning 40) |
| Type body length | 400 lines |
| File length | 500 lines |
| Cyclomatic complexity | 10 |
| Compiler warnings | 0 (warnings as errors) |
| `force_unwrapping`, `force_try` | Forbidden outside tests |
| TODO without issue link | Forbidden |

### Review

- Every change goes through a pull request with at least one approving review from a maintainer; maintainers' own PRs also need review once a second maintainer exists.
- PRs stay small (target under 400 changed lines) and do one thing.
- Changes to public APIs, the XPC protocol, the schema or entitlements need an ADR or ADR update.

## Open-source repository standards

The repository meets GitHub's community standards and the OpenSSF Best Practices "passing" level before v1.0.

| File | Content |
| --- | --- |
| `README.md` | What Rocket is, screenshots, install (DMG, Homebrew), build from source, links to docs |
| `LICENSE` | MIT License; `NOTICE` lists third-party attributions |
| `CONTRIBUTING.md` | Setup in under 10 minutes, workflow, commit and PR rules, DCO, how to run tests and benchmarks |
| `CODE_OF_CONDUCT.md` | Contributor Covenant 2.1, enforcement contacts |
| `SECURITY.md` | Supported versions, private reporting via GitHub Security Advisories, 90-day coordinated disclosure, response in 72 h |
| `GOVERNANCE.md` | Maintainer roles, decision process (lazy consensus, ADRs), how contributors become maintainers |
| `CHANGELOG.md` | Keep a Changelog format, generated from Conventional Commits and edited for humans |
| `docs/adr/` | Architecture Decision Records (MADR), numbered |
| `docs/architecture/` | Architecture overview, module guide, diagrams |
| `.github/` | Issue forms (bug, feature, question), PR template with checklist, `CODEOWNERS`, workflows, Dependabot config |

### Contribution workflow

- Trunk-based: short-lived branches named `type/short-description` off `main`; squash-merge; `main` is always releasable.
- Commits follow Conventional Commits (`feat(engine): …`) and carry `Signed-off-by` (DCO); enforced by CI.
- Branch protection on `main`: required checks green, one approval, linear history, no force-push.
- Labels: `type/*`, `area/*` (engine, ui, cli, browser, ci, docs), `good first issue`, `help wanted`, `needs-adr`.
- Issue triage at least weekly; stale bot only for `needs-info` issues after 30 days.

## Build, CI/CD and release management

Every merge to `main` produces a signed, notarized build; releases are cut from tags by an automated workflow that requires one manual approval.

### Build

- Xcode version pinned in `.xcode-version`; Swift packages resolved from the committed `Package.resolved`.
- Universal binary (arm64 + x86\_64); deployment target macOS 14.0.
- Build configuration in `.xcconfig` files, not in the project file; no secrets in the repo.

### CI pipeline (GitHub Actions, macOS runners)

1. Lint: swift-format, SwiftLint, commit-message and DCO checks.
2. Build all targets with warnings as errors.
3. Unit, engine, persistence and IPC tests with coverage gate.
4. Network integration core matrix against `RocketTestServer`.
5. Performance smoke (PERF-01, PERF-03, PERF-05) on labeled PRs; full suite nightly.
6. On `main`: sign, notarize and upload a nightly build artifact.

### Release process

1. Maintainer runs the release workflow with a version number; it creates the tag and changelog section.
2. The workflow builds, signs (Developer ID), notarizes, staples and packages a DMG and a Sparkle ZIP.
3. It signs the archive with the Sparkle EdDSA key, updates the appcast for the right channel, and attaches GitHub build provenance attestations.
4. A protected GitHub environment requires maintainer approval before publishing.
5. Publishing creates the GitHub Release, updates the appcast, and opens a bump PR for the `rocket-downloader` Homebrew cask.

### Versioning and support

| Item | Policy |
| --- | --- |
| Version scheme | SemVer `MAJOR.MINOR.PATCH`; pre-releases `0.x`; release candidates `1.0.0-rc.N` |
| Build number | Monotonic CI run number (`CFBundleVersion`) |
| Channels | `beta` (pre-releases, RCs) and `stable` Sparkle appcasts |
| Cadence | Minor release roughly every 6–8 weeks after 1.0; patches as needed |
| Supported versions | Latest minor gets fixes; security fixes for the previous minor for 90 days |
| OS support | Drop a macOS version only in a minor release, announced one release ahead |
| Secrets | Signing certificate, notarization API key and Sparkle key stored as encrypted GitHub environment secrets, available only to the release workflow |

## Observability and diagnostics

Rocket is debuggable on a user's Mac without telemetry: structured local logs, signposts and a one-click diagnostics export.

- **Logging:** `os.Logger` with subsystem `io.github.neysidev.rocket` and one category per module (`Engine`, `Networking`, `Persistence`, `IPC`, `UI`). Levels: `debug` for per-chunk detail (off by default), `info` for lifecycle, `error` for failures. URLs and file paths use `privacy: .private`.
- **Signposts:** `os_signpost` intervals for probe, segment transfer, checkpoint and IPC round-trips, visible in Instruments.
- **Per-download log:** the last 200 lifecycle events per download (state changes, retries, HTTP status) stored with the download and shown in the detail view.
- **Diagnostics export:** "Help > Export Diagnostics" builds a ZIP of recent logs, redacted settings, schema version and system info; the user reviews it before attaching to an issue.
- **Crash reports:** Apple's standard crash logs; an opt-in setting to include them in diagnostics exports.
- **Health:** the app shows an agent status indicator (running, not approved in Login Items, version mismatch) with a fix-it action.

## Technical risks and open questions

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| URLSession limits fine control (per-connection reuse, HTTP/2 multiplexing hides parallelism) | Medium | Lower speed-up on HTTP/2 servers | Separate `URLSession` per segment group with HTTP/1.1 preference where faster; benchmark both; `HTTPTransport` allows another adapter |
| Users fail to approve the LaunchAgent in Login Items | Medium | Downloads stop with the UI | Detect `SMAppService.Status.requiresApproval`; guided fix-it; fallback in-app engine mode |
| XPC API drift between app and agent after partial updates | Low | Broken clients | Agent and app ship in one bundle; version handshake; agent restarts on version mismatch |
| SQLite contention from frequent checkpoints | Low | Stutters | WAL mode, batched writes, dedicated writer actor, PERF-09 budget |
| macOS API changes each year | Medium | Breakage on new OS | Beta testing every June; CI job on the latest beta |

### Open questions

- [ ] Confirm the final bundle ID (personal domain or `io.github.neysidev.rocket`) before v0.1.
- [ ] Choose a crash-report path for opt-in users (Apple reports only vs. a self-hosted open-source collector).
- [ ] Decide whether an in-app fallback engine (when the agent is not approved) is worth its complexity.
