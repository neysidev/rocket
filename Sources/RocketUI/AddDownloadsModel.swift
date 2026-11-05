import Foundation
import Observation
import RocketCore
import RocketIPC

/// Pulls http(s) links out of pasted text, dropped `.txt` lists or anything else (FR-ADD-01). Keeps order, drops repeats.
public enum LinkExtractor {
    public static func urls(in text: String) -> [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        var seen = Set<URL>()
        return matches.compactMap(\.url).filter { url in
            ["http", "https"].contains(url.scheme?.lowercased()) && seen.insert(url).inserted
        }
    }

    /// Web links stay as they are; local `.txt` files are read for the links inside.
    public static func urls(fromDropped items: [URL]) -> [URL] {
        var text = ""
        for item in items {
            if item.isFileURL {
                if item.pathExtension.lowercased() == "txt", let contents = try? String(contentsOf: item, encoding: .utf8) {
                    text += contents + "\n"
                }
            } else {
                text += item.absoluteString + "\n"
            }
        }
        return urls(in: text)
    }
}

/// State for the add sheet: paste links → review what the server says → start.
@MainActor
@Observable
public final class AddDownloadsModel: Identifiable {
    public enum Phase { case input, review }

    /// FR-ADD-03: what to do when a download is already in the list or its file already exists.
    public enum Resolution: String, CaseIterable, Identifiable, Sendable {
        case keepBoth, overwrite, skip, showExisting
        public var id: Self { self }
        public var title: String {
            switch self {
            case .keepBoth: String(localized: "Keep both")
            case .overwrite: String(localized: "Replace existing file")
            case .skip: String(localized: "Skip")
            case .showExisting: String(localized: "Show existing")
            }
        }
    }

    public enum Conflict: Equatable, Sendable {
        case inList(UUID)
        case fileExists
    }

    public struct Candidate: Identifiable, Sendable {
        public let id = UUID()
        public let url: URL
        public var fileName: String
        public var info: RemoteFileInfo?
        public var error: String?
        public var resolution: Resolution = .keepBoth
        public var isProbing: Bool { info == nil && error == nil }
    }

    public var text: String
    public var folder: URL
    public var connections: Int
    public var queueID: String
    /// Headers, referrer, user agent, cookies and Basic auth for every link in this sheet (FR-ADD-04).
    public var context = RequestContext()
    public var headerText = ""
    public let queues: [DownloadQueue]
    public private(set) var phase: Phase = .input
    public var candidates: [Candidate] = []
    /// Downloads to select in the list after "Show existing".
    public private(set) var revealed: [UUID] = []

    private let agent: (any AgentCommanding)?
    private let existing: [Download]
    /// The folder and queue the sheet opened with; unchanged choices are left to rules and defaults.
    private let initialFolder: URL
    private let initialQueueID: String
    private let fileExists: (URL) -> Bool

    public init(
        text: String = "", folder: URL, connections: Int = 8, queueID: String = DownloadQueue.defaultID,
        queues: [DownloadQueue] = [], agent: (any AgentCommanding)?, existing: [Download],
        fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) {
        self.text = text
        self.folder = folder
        initialFolder = folder
        initialQueueID = queueID
        self.connections = connections
        self.queueID = queueID
        self.queues = queues
        self.agent = agent
        self.existing = existing.filter { $0.state != .cancelled }
        self.fileExists = fileExists
    }

    public var links: [URL] { LinkExtractor.urls(in: text) }

    public var startCount: Int {
        candidates.count { $0.info != nil && ![.skip, .showExisting].contains($0.resolution) }
    }

    public func conflict(for candidate: Candidate) -> Conflict? {
        if let same = existing.first(where: { $0.url == candidate.url }) { return .inList(same.id) }
        if fileExists(folder.appending(path: candidate.fileName)) { return .fileExists }
        if existing.contains(where: { $0.destinationPath == folder.path && $0.fileName == candidate.fileName }) { return .fileExists }
        return nil
    }

    public func resolutions(for conflict: Conflict) -> [Resolution] {
        switch conflict {
        case .inList: [.showExisting, .keepBoth, .skip]
        case .fileExists: [.keepBoth, .overwrite, .skip]
        }
    }

    /// Probes every link through the agent, in parallel.
    public func review() async {
        candidates = links.map { Candidate(url: $0, fileName: FileNameSanitizer.sanitize($0.lastPathComponent)) }
        phase = .review
        guard let agent else {
            for index in candidates.indices { candidates[index].error = String(localized: "Rocket's background agent is not running.") }
            return
        }
        let requestContext = requestContext
        await withTaskGroup(of: (UUID, Result<RemoteFileInfo, any Error>).self) { group in
            for candidate in candidates {
                group.addTask {
                    do {
                        switch try await agent.send(.probe(url: candidate.url, context: requestContext)) {
                        case .info(let info): return (candidate.id, .success(info))
                        case .error(let message): return (candidate.id, .failure(AddError(message: message)))
                        default: return (candidate.id, .failure(AddError(message: "Unexpected reply")))
                        }
                    } catch {
                        return (candidate.id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                guard let index = candidates.firstIndex(where: { $0.id == id }) else { continue }
                switch result {
                case .success(let info):
                    candidates[index].info = info
                    if let name = info.suggestedFileName { candidates[index].fileName = FileNameSanitizer.sanitize(name) }
                    if let conflict = conflict(for: candidates[index]) {
                        candidates[index].resolution = resolutions(for: conflict)[0]
                    }
                case .failure(let error):
                    candidates[index].error = (error as? AddError)?.message ?? error.localizedDescription
                }
            }
        }
    }

    /// Adds every candidate the user kept. Returns the IDs of new and "show existing" downloads.
    public func start() async -> [UUID] {
        guard let agent else { return [] }
        var ids: [UUID] = []
        for index in candidates.indices where candidates[index].info != nil {
            let candidate = candidates[index]
            let conflict = conflict(for: candidate)
            switch (candidate.resolution, conflict) {
            case (.skip, _):
                continue
            case (.showExisting, .inList(let id)?):
                ids.append(id)
                continue
            case (.overwrite, .fileExists?):
                try? FileManager.default.trashItem(at: folder.appending(path: candidate.fileName), resultingItemURL: nil)
            case (.keepBoth, .fileExists?):
                candidates[index].fileName = uniqueName(candidate.fileName)
            default:
                break
            }
            let command = Command.add(
                url: candidate.url, directory: folder == initialFolder ? nil : folder.path, fileName: candidates[index].fileName,
                queueID: queueID == initialQueueID && queueID == DownloadQueue.defaultID ? nil : queueID,
                context: requestContext
            )
            switch try? await agent.send(command) {
            case .download(let download)?: ids.append(download.id)
            case .error(let message)?: candidates[index].error = message
            default: candidates[index].error = String(localized: "Could not reach the background agent.")
            }
        }
        revealed = ids
        return ids
    }

    /// The context with typed header lines merged in; nil when nothing was entered.
    var requestContext: RequestContext? {
        var context = context
        context.headers = RequestContext.headers(fromLines: headerText.components(separatedBy: .newlines))
        for keyPath in [\RequestContext.referrer, \.userAgent, \.cookies, \.username, \.password] where context[keyPath: keyPath]?.isEmpty == true {
            context[keyPath: keyPath] = nil
        }
        return context.isEmpty ? nil : context
    }

    /// "a.iso" → "a 2.iso", like Finder, avoiding files on disk and names already in the list.
    func uniqueName(_ name: String) -> String {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        for number in 2...999 {
            let candidate = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            let taken = fileExists(folder.appending(path: candidate))
                || existing.contains { $0.destinationPath == folder.path && $0.fileName == candidate }
            if !taken { return candidate }
        }
        return name
    }
}

struct AddError: Error {
    let message: String
}
