# Rocket

The fast, native download manager for Mac — open source and free.

> Early development. Infrastructure only; features land from v0.1.

## Build and run

Requires macOS 14+ and Swift 6 (Xcode or Command Line Tools).

```sh
./Scripts/run-app.sh   # build and open the app
swift test             # run tests
swift run rocket --help
```

## Layout

| Path | What |
| --- | --- |
| `App/` | SwiftUI app (UI only) |
| `Agent/` | `rocketd` background agent (owns engine, database, file writes) |
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
