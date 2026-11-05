import RocketCore
import RocketDesign
import SwiftUI

/// Paste links → see name, size, type, resumability and destination → start (FR-ADD-01/02/03). Shown in a modal.
public struct AddDownloadsSheet: View {
    @Bindable var model: AddDownloadsModel
    let onFinish: ([UUID]) -> Void
    @Environment(\.rocketDismiss) private var dismiss
    @State private var choosingFolder = false
    @State private var starting = false
    @State private var showsOptions = false
    @FocusState private var linksFocused: Bool

    public init(model: AddDownloadsModel, onFinish: @escaping ([UUID]) -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    public var body: some View {
        RocketModalLayout(
            model.phase == .input ? String(localized: "New download") : String(localized: "Review downloads"),
            subtitle: model.phase == .input
                ? String(localized: "Paste one or more links. Rocket checks each one before anything starts.")
                : String(localized: "Rename files or resolve conflicts, then start.")
        ) {
            Group {
                switch model.phase {
                case .input: input
                case .review: review
                }
            }
            .id(model.phase)
            .rocketTransition(RocketTransition.content)
            .rocketAnimation(RocketMotion.standard, value: model.phase)
            .padding(.horizontal, RocketSpace.s6)
            .padding(.bottom, RocketSpace.s5)
        } actions: {
            folderPicker
            if model.queues.count > 1 {
                RocketSelect("Queue", selection: $model.queueID, options: model.queues.map { RocketOption($0.id, $0.name) }, compact: true)
                    .fixedSize()
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.rocketGhost)
                .keyboardShortcut(.cancelAction)
            primaryButton
        }
        .frame(width: 620)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.folder = url }
        }
    }

    // MARK: Input

    private var input: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s3) {
            TextEditor(text: $model.text)
                .font(.rocketMono)
                .scrollContentBackground(.hidden)
                .focused($linksFocused)
                .frame(height: 148)
                .padding(.horizontal, -RocketSpace.s1)
                .rocketField(mono: true, multiline: true)
                .overlay(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text(verbatim: "https://")
                            .font(.rocketMono)
                            .foregroundStyle(RocketColor.textTertiary)
                            .padding(.horizontal, RocketSpace.s3 + 2)
                            .padding(.vertical, RocketSpace.s3)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Links")
                .onAppear { linksFocused = true }
            HStack(spacing: RocketSpace.s2 + 2) {
                StatusGlyph(model.links.isEmpty ? .queued : .done, size: 11)
                Text(linkCountText)
                    .font(.rocketLabel)
                    .foregroundStyle(model.links.isEmpty ? RocketColor.textTertiary : RocketColor.textSecondary)
                    .contentTransition(.numericText())
            }
            .animation(RocketMotion.fast, value: model.links.count)
            RocketDisclosure(String(localized: "Request options"), isExpanded: $showsOptions) { RequestOptions(model: model) }
                .padding(.top, RocketSpace.s2)
        }
    }

    private var linkCountText: String {
        switch model.links.count {
        case 0: String(localized: "No http or https links found yet")
        case 1: String(localized: "1 link")
        default: String(localized: "\(model.links.count) links")
        }
    }

    // MARK: Review

    @ViewBuilder
    private var review: some View {
        let rows = VStack(spacing: RocketSpace.s3) {
            ForEach($model.candidates) { $candidate in
                CandidateRow(candidate: $candidate, conflict: model.conflict(for: candidate), model: model)
            }
        }
        // A few links fit as they are; longer lists scroll.
        if model.candidates.count <= 3 {
            rows
        } else {
            ScrollView { rows }.frame(height: 400)
        }
    }

    // MARK: Footer

    private var folderPicker: some View {
        Button {
            choosingFolder = true
        } label: {
            HStack(spacing: RocketSpace.s2 + 2) {
                RocketIcon(.folder, size: 14).foregroundStyle(RocketColor.textSecondary)
                Text(model.folder.lastPathComponent).lineLimit(1).truncationMode(.middle)
            }
        }
        .buttonStyle(RocketButtonStyle(.secondary, size: .small))
        .rocketTooltip(model.folder.path)
        .accessibilityLabel("Destination folder, \(model.folder.lastPathComponent)")
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch model.phase {
        case .input:
            Button("Continue") { Task { await model.review() } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.rocketPrimary)
                .disabled(model.links.isEmpty)
        case .review:
            Button {
                starting = true
                Task {
                    let ids = await model.start()
                    starting = false
                    if !model.candidates.contains(where: { $0.error != nil && $0.resolution != .skip }) || !ids.isEmpty {
                        onFinish(ids)
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: RocketSpace.s3) {
                    if starting { RocketSpinner(size: 11, tint: RocketColor.textInverse) }
                    Text(model.startCount > 1 ? "Start \(model.startCount) Downloads" : "Start Download")
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.rocketPrimary)
            .disabled(starting || model.candidates.contains(where: \.isProbing)
                || (model.startCount == 0 && !model.candidates.contains { $0.resolution == .showExisting && $0.info != nil }))
        }
    }
}

private struct CandidateRow: View {
    @Binding var candidate: AddDownloadsModel.Candidate
    let conflict: AddDownloadsModel.Conflict?
    let model: AddDownloadsModel

    var body: some View {
        HStack(alignment: .top, spacing: RocketSpace.s4) {
            FileTile(symbol: FileCategory(fileName: candidate.fileName, mimeType: candidate.info?.contentType).symbol, size: 34)
            VStack(alignment: .leading, spacing: RocketSpace.s2) {
                TextField("File name", text: $candidate.fileName)
                    .textFieldStyle(.plain)
                    .font(.rocketHeadline)
                    .foregroundStyle(RocketColor.textPrimary)
                    .disabled(candidate.info == nil)
                Text(candidate.url.absoluteString)
                    .font(.rocketMono)
                    .foregroundStyle(RocketColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                details
                if let conflict, candidate.info != nil {
                    HStack(spacing: RocketSpace.s3) {
                        Text(conflictText(conflict))
                            .font(.rocketLabel)
                            .foregroundStyle(RocketColor.warning)
                        RocketSelect(conflictText(conflict), selection: $candidate.resolution,
                                     options: model.resolutions(for: conflict).map { RocketOption($0, $0.title) }, compact: true)
                            .fixedSize()
                    }
                    .padding(.top, RocketSpace.s1)
                }
            }
        }
        .padding(RocketSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rocketCard()
    }

    @ViewBuilder
    private var details: some View {
        if let error = candidate.error {
            HStack(spacing: RocketSpace.s2 + 2) {
                StatusGlyph(.failed, size: 11)
                Text(error)
            }
            .foregroundStyle(RocketColor.danger)
            .font(.rocketLabel)
        } else if let info = candidate.info {
            HStack(spacing: RocketSpace.s2) {
                Text(info.totalBytes.map(Format.bytes) ?? String(localized: "Size unknown"))
                Text("·").foregroundStyle(RocketColor.textTertiary)
                Text(info.contentType ?? FileCategory(fileName: candidate.fileName).title)
                Text("·").foregroundStyle(RocketColor.textTertiary)
                if info.acceptsRanges {
                    Text("Resumable")
                } else {
                    Text("Not resumable, single connection")
                        .foregroundStyle(RocketColor.warning)
                }
            }
            .font(.rocketLabel)
            .foregroundStyle(RocketColor.textSecondary)
            .monospacedDigit()
            .lineLimit(1)
        } else {
            HStack(spacing: RocketSpace.s2 + 2) {
                RocketSpinner(size: 11)
                Text("Checking link…")
            }
            .font(.rocketLabel)
            .foregroundStyle(RocketColor.textSecondary)
        }
    }

    private func conflictText(_ conflict: AddDownloadsModel.Conflict) -> String {
        switch conflict {
        case .inList: String(localized: "Already in your downloads")
        case .fileExists: String(localized: "A file with this name exists")
        }
    }
}

/// Headers, referrer, user agent, cookies and Basic auth for sites that need them (FR-ADD-04).
private struct RequestOptions: View {
    @Bindable var model: AddDownloadsModel

    var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s3) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: RocketSpace.s4, verticalSpacing: RocketSpace.s3) {
                field("Referrer", text: optional(\.referrer), prompt: "https://example.com/page")
                field("User agent", text: optional(\.userAgent), prompt: "Default")
                field("Cookies", text: optional(\.cookies), prompt: "name=value; other=value")
                GridRow {
                    label("Sign in")
                    HStack(spacing: RocketSpace.s3) {
                        TextField("User name", text: optional(\.username), prompt: Text("User name")).rocketField()
                        SecureField("Password", text: optional(\.password), prompt: Text("Password")).rocketField()
                    }
                }
                GridRow(alignment: .top) {
                    label("Headers").padding(.top, RocketSpace.s3)
                    TextField("Headers", text: $model.headerText, prompt: Text("Name: value, one per line"), axis: .vertical)
                        .lineLimit(2...4)
                        .rocketField(mono: true, multiline: true)
                }
            }
            Text("Cookies and passwords are kept in your Keychain and only sent to the link's own site.")
                .font(.rocketCaption)
                .foregroundStyle(RocketColor.textTertiary)
        }
        .padding(.leading, RocketSpace.s5 - 2)
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.rocketLabel)
            .foregroundStyle(RocketColor.textSecondary)
            .gridColumnAlignment(.leading)
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>, prompt: LocalizedStringKey) -> some View {
        GridRow(alignment: .center) {
            label(title)
            TextField(title, text: text, prompt: Text(prompt)).rocketField()
        }
    }

    private func optional(_ keyPath: WritableKeyPath<RequestContext, String?>) -> Binding<String> {
        Binding { model.context[keyPath: keyPath] ?? "" } set: { model.context[keyPath: keyPath] = $0 }
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
