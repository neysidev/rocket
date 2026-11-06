import RocketCore
import RocketDesign
import SwiftUI

/// New Download: one link field, Cancel and Download. Rocket checks the link, applies rules and duplicate defaults,
/// and starts it; only a failure keeps the sheet open, with the reason under the field.
public struct AddDownloadsSheet: View {
    @Bindable var model: AddDownloadsModel
    let onFinish: ([UUID]) -> Void
    @Environment(\.rocketDismiss) private var dismiss
    @State private var working = false
    @State private var error: String?
    @FocusState private var focused: Bool

    public init(model: AddDownloadsModel, onFinish: @escaping ([UUID]) -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Download").font(.headline)
            TextField("URL", text: $model.text, prompt: Text(verbatim: "https://"))
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onAppear { focused = true }
                .onChange(of: model.text) { error = nil }
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Download", action: download)
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || model.links.isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 440)
    }

    private func download() {
        working = true
        error = nil
        Task {
            await model.review()
            let ids = await model.start()
            working = false
            if ids.isEmpty, let failure = model.candidates.compactMap(\.error).first {
                error = failure
            } else {
                onFinish(ids)
                dismiss()
            }
        }
    }
}

/// Paste a fresh link for a download whose link expired (FR-ENG-09).
public struct RefreshLinkSheet: View {
    let download: Download
    let onRefresh: (URL) async -> String?
    @State private var text: String
    @State private var error: String?
    @State private var working = false
    @Environment(\.rocketDismiss) private var dismiss

    public init(download: Download, onRefresh: @escaping (URL) async -> String?) {
        self.download = download
        self.onRefresh = onRefresh
        let clipboard = LinkExtractor.urls(in: NSPasteboard.general.string(forType: .string) ?? "").first
        _text = State(initialValue: clipboard?.absoluteString ?? "")
    }

    public var body: some View {
        RocketModalLayout(
            String(localized: "Refresh link"),
            subtitle: String(localized: "Paste a new link to \(download.fileName). Rocket keeps the \(Format.bytes(download.receivedBytes)) already downloaded if it is the same file.")
        ) {
            VStack(alignment: .leading, spacing: RocketSpace.s3) {
                TextField("Link", text: $text, prompt: Text(verbatim: "https://"))
                    .rocketField(mono: true)
                if let error {
                    HStack(spacing: RocketSpace.s2 + 2) {
                        StatusGlyph(.failed, size: 11)
                        Text(error)
                    }
                    .font(.rocketLabel)
                    .foregroundStyle(RocketColor.danger)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, RocketSpace.s6)
            .padding(.bottom, RocketSpace.s5)
            .animation(RocketMotion.fast, value: error)
        } actions: {
            Button("Cancel") { dismiss() }
                .buttonStyle(.rocketGhost)
                .keyboardShortcut(.cancelAction)
            Button {
                guard let url = LinkExtractor.urls(in: text).first else { return error = String(localized: "That is not an http or https link.") }
                working = true
                Task {
                    error = await onRefresh(url)
                    working = false
                    if error == nil { dismiss() }
                }
            } label: {
                HStack(spacing: RocketSpace.s3) {
                    if working { RocketSpinner(size: 11, tint: RocketColor.textInverse) }
                    Text("Refresh and Resume")
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.rocketPrimary)
            .disabled(working || text.isEmpty)
        }
        .frame(width: 480)
    }
}
