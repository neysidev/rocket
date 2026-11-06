import RocketCore
import RocketDesign
import SwiftUI

/// Organization, duplicates, and retry behavior — the "smart" layer on top of the engine.
struct SmartDownloadsSettings: View {
    @Bindable var settings: AppSettings
    let model: DownloadsModel

    var body: some View {
        Group {
            RocketFormSection(String(localized: "Smart categories"),
                              footer: String(localized: "Rocket groups downloads by file type in the list and can sort completed files into type folders automatically.")) {
                RocketFormRow(String(localized: "Sort into folders by type"), detail: String(localized: "Video, Archives, Documents, …")) {
                    Toggle("Sort into folders by type", isOn: $settings.autoSort).labelsHidden().toggleStyle(.rocketSwitch)
                }
            }
            RocketFormSection(String(localized: "Duplicate downloads"),
                              footer: String(localized: "When you add a link that is already downloading or would overwrite a file, Rocket starts with this choice. You can still change it per download.")) {
                RocketFormRow(String(localized: "Default action")) {
                    RocketSelect(String(localized: "Default action"), selection: $settings.defaultDuplicateResolution,
                                 options: DuplicateResolution.allCases.map { RocketOption($0, $0.title) })
                        .fixedSize()
                }
            }
            RocketFormSection(String(localized: "Smart retry"),
                              footer: String(localized: "Transient network errors retry with exponential backoff and jitter. The background agent reads these values for new connection attempts.")) {
                RocketFormRow(String(localized: "Maximum attempts")) {
                    RocketSelect(String(localized: "Maximum attempts"), selection: $settings.retryMaxAttempts,
                                 options: RocketDefaults.retryAttemptRange.map { RocketOption($0, "\($0)") })
                        .fixedSize()
                }
                RocketFormRow(String(localized: "Starting delay")) {
                    RocketSelect(String(localized: "Starting delay"), selection: $settings.retryBaseDelaySeconds,
                                 options: [1, 2, 5, 10].map { RocketOption($0, String(localized: "\($0) s")) })
                        .fixedSize()
                }
                RocketFormRow(String(localized: "Maximum delay")) {
                    RocketSelect(String(localized: "Maximum delay"), selection: $settings.retryMaxDelaySeconds,
                                 options: [15, 30, 60, 120, 300].map { RocketOption($0, String(localized: "\($0) s")) })
                        .fixedSize()
                }
            }
            RocketFormSection(String(localized: "Download rules"),
                              footer: String(localized: "Rules match sites, file types and sizes, then set folder, queue, connections and speed. Edit them in the Rules tab.")) {
                RocketFormRow(String(localized: "Active rules")) {
                    Text("\(model.rules.filter(\.enabled).count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { await model.refreshRules() }
    }
}
