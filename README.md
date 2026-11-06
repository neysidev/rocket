<h1 align="center">Rocket</h1>

<p align="center">
  <b>The fast, native download manager for Mac.</b><br>
  Parallel connections, resume after anything, queues and schedules: written in Swift, open source and free.
</p>

<p align="center">
  <img alt="Platform: macOS 14+" src="https://img.shields.io/badge/platform-macOS%2014%2B-black">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue"></a>
  <img alt="Status: pre-release" src="https://img.shields.io/badge/status-pre--release-orange">
</p>

<p align="center">
  <b><a href="#why-rocket">Why Rocket</a> · <a href="#features">Features</a> · <a href="#command-line">CLI</a> · <a href="#build-from-source">Build</a> · <a href="#architecture">Architecture</a> · <a href="CONTRIBUTING.md">Contributing</a></b>
</p>

<!-- Add a screenshot here once the UI settles, e.g.:
<p align="center"><img src="docs/images/main-window.png" width="100%" alt="Rocket's main window: queues in the sidebar, a downloads table and an inspector"></p>
-->

> [!NOTE]
> Rocket is in early development and has no published release yet. You can build it from source today; expect rough edges and breaking changes until v1.0.

## Why Rocket

**⚡ Faster downloads.** Browsers fetch a file over one connection. Rocket splits it across up to 16 parallel connections, so large files arrive as fast as your link and the server allow.

**🛟 Never lose a byte.** Downloads resume after network drops, Wi-Fi switches, sleep, crashes and expired links. Checksums are verified, and a corrupted "complete" file counts as a release-blocking bug.

**🍎 Truly native.** Swift, SwiftUI and AppKit, following system conventions. There's no Electron and no web views. A background agent (`rocketd`) keeps downloads running after you close the window, and uses near-zero CPU when idle.

**🔒 Private.** No accounts, no telemetry and no tracking. Cookies and passwords are stored in the macOS Keychain.

**⌨️ Scriptable.** Anything the app can do, the `rocket` CLI, the `rocket://` URL scheme and Shortcuts can do too.

## Features

- **Acceleration:** segmented HTTP/HTTPS downloads with 1–16 connections per file, plus plain-HTTP support.
- **Resume everywhere:** reconnects after the Mac wakes from sleep, and you can **refresh an expired link** without losing progress.
- **Queues and scheduling:** named queues with schedules, ordering and per-queue concurrency.
- **Speed limits:** global or per-download limits (`2M`, `500K`, …).
- **Rules and sorting:** files are sorted by type, and your own rules decide where downloads go.
- **Integrity:** MD5, SHA-1 and SHA-256 checksum verification.
- **Authenticated downloads:** custom headers, cookies, Referer, User-Agent and HTTP Basic auth.
- **Network:** a per-app proxy.
- **Capture links from anywhere:**
  - links you copy to the clipboard (opt-in)
  - **Download with Rocket** in the macOS Services menu
  - `rocket://add?url=…` links
  - Shortcuts actions
- **A window you'll actually like:**
  - a calm, state-aware downloads table with an inspector showing connections, speed and the log
  - a progress window for each download
  - a menu bar panel and Dock icon progress
  - a command palette (fuzzy search) and a contextual selection toolbar
- **Insights:** Smart Downloads statistics and activity charts.
- **Feedback:** optional sound effects.
- **Updates:** automatic updates via Sparkle.

Items you add from outside the app (the clipboard, Services, URL scheme) always open the add sheet for review first. Nothing starts without your say-so.

## Command line

The `rocket` CLI ships inside the app bundle at `Rocket Downloader.app/Contents/Helpers/rocket` and talks to the same background agent as the app. Add `--json` to most commands to get machine-readable output.

```sh
rocket add <url> [--dir ~/Downloads] [--name file.iso] [--connections 8] [--limit 2M] \
                 [--queue Nightly] [--header "Name: value"] [--cookie …] [--user user:pass] \
                 [--checksum sha256:ab12…] [--wait]
rocket info <url>                 # what the server reports, without downloading
rocket list                       # all downloads
rocket pause|resume|cancel <id>   # an ID or a unique prefix of one
rocket wait [<id>…]               # block until downloads finish
rocket limit 2M [--id <id>]       # global or per-download speed limit ("off" to clear)
rocket refresh <id> <new-url>     # swap an expired link, keep progress
rocket queue list|add|remove
rocket config list|get|set
```

`rocket add --wait` and `rocket wait` exit with `1` if a download fails or is cancelled, and with `4` if the checksum doesn't match, so they fit well in scripts and CI.

Run `rocket help <command>` to see every option.

## Build from source

**Requirements:** macOS 14+, Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/neysidev/rocket.git
cd rocket
./Scripts/run-app.sh          # generate Rocket.xcodeproj, build, load rocketd, open the app
```

Other useful commands:

```sh
swift test                    # run the module tests
swift run rocket --help       # build and run the CLI from SwiftPM
swift run rocket-test-server  # local HTTP server for manual download testing
```

Some notes:

- `Rocket.xcodeproj` is generated from [`project.yml`](project.yml). Don't edit it by hand.
- Debug builds load `rocketd` straight into launchd.
- Release builds register `rocketd` with `SMAppService`. macOS may ask you to allow it in **System Settings → General → Login Items**.

## Architecture

Rocket is split into two processes and a set of small Swift packages. The UI app and the CLI are thin clients. A LaunchAgent, `rocketd`, owns the engine, the database and all file writes, and serves them over a versioned XPC contract.

| Path | What |
| --- | --- |
| `project.yml` | XcodeGen spec for the app bundle (app + `rocketd` + `rocket`) |
| `App/` | SwiftUI app: the composition root, Services, Shortcuts, Sparkle |
| `Agent/` | `rocketd` LaunchAgent: XPC listener, owns the engine, database and file writes |
| `Sources/RocketCore` | Models, state machine and ports. No third-party code, no UI |
| `Sources/RocketEngine` | Scheduler, coordinators, segmentation, retries, rules |
| `Sources/RocketNetworking` | URLSession `HTTPTransport` adapter, proxy |
| `Sources/RocketPersistence` | GRDB database, migrations and repositories |
| `Sources/RocketIPC` | Versioned XPC message contract and client |
| `Sources/RocketDesign` | Design tokens, motion and shared components |
| `Sources/RocketUI` | App screens and their view models |
| `Sources/RocketCLI` | The `rocket` command-line tool |
| `Tests/` | Per-module tests and a local test server |

Dependencies only point downward: **App / Agent / CLI → adapters → Engine → Core**.

To go deeper, see the [PRD](docs/PRD.md), the [TRD](docs/TRD.md) and the [design notes](docs/DESIGN.md).

## Contributing

Issues and pull requests are welcome. In short:

- Branch off `main` with a branch named `type/short-description`.
- Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat(engine): …`).
- Sign off every commit (`git commit -s`, [DCO](https://developercertificate.org/)).
- Keep PRs small and focused.
- Architecture changes need an ADR in `docs/adr/`.

CI builds with warnings treated as errors, runs `swift test` and builds the Xcode project. Run the same checks locally before you open a PR. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide.

## License

Rocket is licensed under the [MIT License](LICENSE). Third-party notices, for [GRDB.swift](https://github.com/groue/GRDB.swift) (MIT) and [swift-argument-parser](https://github.com/apple/swift-argument-parser) (Apache-2.0), are in [NOTICE](NOTICE).
