import RocketCore

/// Owns queues and concurrency limits; starts and stops coordinators. One per agent.
public actor DownloadScheduler {
    private let repository: any DownloadRepository
    private let transport: any HTTPTransport

    public init(repository: any DownloadRepository, transport: any HTTPTransport) {
        self.repository = repository
        self.transport = transport
    }

    public func snapshot() async throws -> [Download] {
        try await repository.all()
    }
}
