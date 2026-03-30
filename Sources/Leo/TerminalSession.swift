import Foundation

enum TerminalStatus: String, Codable {
    case idle
    case working
    case waitingForInput
    case taskCompleted
    case interrupted
}

struct TerminalSession: Identifiable, Codable {
    let id: UUID
    var projectName: String
    var projectPath: String?
    var workingDirectory: String
    var hasStarted: Bool
    var terminalStatus: TerminalStatus
    var generation: Int
    var hasBeenSelected: Bool
    var createdAt: Date
    var workingStartedAt: Date?

    init(
        projectName: String,
        projectPath: String? = nil,
        workingDirectory: String
    ) {
        self.id = UUID()
        self.projectName = projectName
        self.projectPath = projectPath
        self.workingDirectory = workingDirectory
        self.hasStarted = false
        self.terminalStatus = .idle
        self.generation = 0
        self.hasBeenSelected = false
        self.createdAt = Date()
        self.workingStartedAt = nil
    }
}

struct PersistedSession: Codable {
    let id: UUID
    let projectName: String
    let projectPath: String?
    let workingDirectory: String
}
