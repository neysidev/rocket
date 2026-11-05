import RocketCore
import RocketDesign
import SwiftUI

/// Paste links → see name, size, type, resumability and destination → start (FR-ADD-01/02/03).
public struct AddDownloadsSheet: View {
    @Bindable var model: AddDownloadsModel
    let onFinish: ([UUID]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choosingFolder = false
    @State private var starting = false

    public init(model: AddDownloadsModel, onFinish: @escaping ([UUID]) -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s5) {
            Text(model.phase == .input ? "Add downloads" : "Review downloads")
                .font(.rocketTitle)
                .foregroundStyle(RocketColor.textPrimary)

            switch model.phase {
            case .input: input
            case .review: review
            }

            HStack {
                folderPicker
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                primaryButton
            }
        }
        .padding(RocketSpace.s6)
        .frame(width: 600)
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
                .padding(RocketSpace.s3)
                .frame(height: 160)
                .background(RocketColor.control, in: RoundedRectangle(cornerRadius: RocketRadius.control))
                .overlay(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text("Paste one or more links, one per line")
                            .font(.rocketBody)
                            .foregroundStyle(RocketColor.textTertiary)
                            .padding(RocketSpace.s4)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Links")
            Text(linkCountText)
                .font(.rocketLabel)
                .foregroundStyle(RocketColor.textSecondary)
        }
    }

    private var linkCountText: String {
        switch model.links.count {
        case 0: String(localized: "No http or https links found yet.")
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
            Label(model.folder.lastPathComponent, systemImage: "folder")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help(model.folder.path)
        .accessibilityLabel("Destination folder, \(model.folder.lastPathComponent)")
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch model.phase {
        case .input:
            Button("Next") { Task { await model.review() } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(model.links.isEmpty)
        case .review:
            Button(model.startCount > 1 ? "Start \(model.startCount) Downloads" : "Start Download") {
                starting = true
                Task {
                    let ids = await model.start()
                    starting = false
                    if !model.candidates.contains(where: { $0.error != nil && $0.resolution != .skip }) || !ids.isEmpty {
                        onFinish(ids)
                        dismiss()
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
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
            FileTile(symbol: FileCategory(fileName: candidate.fileName).symbol)
            VStack(alignment: .leading, spacing: RocketSpace.s2) {
                TextField("File name", text: $candidate.fileName)
                    .textFieldStyle(.plain)
                    .font(.rocketHeadline)
                    .disabled(candidate.info == nil)
                Text(candidate.url.absoluteString)
                    .font(.rocketMono)
                    .foregroundStyle(RocketColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                details
                if let conflict, candidate.info != nil {
                    Picker(conflictText(conflict), selection: $candidate.resolution) {
                        ForEach(model.resolutions(for: conflict)) { Text($0.title).tag($0) }
                    }
                    .font(.rocketLabel)
                    .fixedSize()
                }
            }
        }
        .padding(RocketSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RocketColor.card, in: RoundedRectangle(cornerRadius: RocketRadius.card))
    }

    @ViewBuilder
    private var details: some View {
        if let error = candidate.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(RocketColor.danger)
                .font(.rocketLabel)
        } else if let info = candidate.info {
            HStack(spacing: RocketSpace.s2) {
                Text(info.totalBytes.map(Format.bytes) ?? String(localized: "Size unknown"))
                Text("·")
                Text(info.contentType ?? FileCategory(fileName: candidate.fileName).rawValue.capitalized)
                Text("·")
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
        } else {
            HStack(spacing: RocketSpace.s2) {
                ProgressView().controlSize(.small)
                Text("Checking link…")
            }
            .font(.rocketLabel)
            .foregroundStyle(RocketColor.textSecondary)
        }
    }

    private func conflictText(_ conflict: AddDownloadsModel.Conflict) -> String {
        switch conflict {
        case .inList: String(localized: "Already in your downloads:")
        case .fileExists: String(localized: "A file with this name exists:")
        }
    }
}
