# Rocket

The fast, native download manager for Mac — open source and free.

> Early development. Infrastructure only; features land from v0.1.

## Build and run

Requires macOS 14+, Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
./Scripts/run-app.sh   # generate Rocket.xcodeproj, build, open the app
swift test             # run module tests
swift run rocket-test-server   # local test server for manual downloads
```

The `rocket` CLI ships inside the app at `Contents/Helpers/rocket`:

```sh
rocket add <url> [--dir ~/Downloads] [--name f.iso] [--connections 8] [--wait]
rocket info <url>
rocket list [--json]
rocket pause|resume|cancel <id-prefix>
```

`Rocket.xcodeproj` is generated from `project.yml`; don't edit it by hand. Debug builds: `run-app.sh` loads
`rocketd` into launchd directly. Release builds register it with `SMAppService`, and macOS may ask you to allow
it in System Settings > General > Login Items.

## Layout

| Path | What |
| --- | --- |
| `project.yml` | XcodeGen spec for the app bundle (app + `rocketd` + `rocket`) |
| `App/` | SwiftUI app (UI only) |
| `Agent/` | `rocketd` LaunchAgent: XPC listener, owns engine, database, file writes |
| `Sources/RocketCore` | Models, state machine, ports. No third-party, no UI |
| `Sources/RocketEngine` | Scheduler, coordinators, segmentation |
| `Sources/RocketNetworking` | URLSession `HTTPTransport` adapter |
| `Sources/RocketPersistence` | GRDB database, migrations, repositories |
| `Sources/RocketIPC` | Versioned XPC message contract |
| `Sources/RocketDesign` | Design tokens and shared components |
| `Sources/RocketCLI` | `rocket` command-line tool |

Dependencies point downward only: App/Agent/CLI → adapters → Engine → Core.

## License

Apache-2.0. See [LICENSE](LICENSE).
