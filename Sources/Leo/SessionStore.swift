import Foundation
import AppKit

@Observable
final class SessionStore {
    static let shared = SessionStore()

    var sessions: [TerminalSession] = []
    var activeSessionId: UUID?
    var isPinned: Bool = true {
        didSet {
            UserDefaults.standard.set(isPinned, forKey: "isPinned")
            isPinned ? startPolling() : stopPolling()
        }
    }

    private var pollingTimer: Timer?
    private var taskCompletionTimer: Timer?
    private var sleepActivity: NSObjectProtocol?

    var notchStatusColor: NSColor {
        guard let active = activeSession else { return .systemGreen }
        switch active.terminalStatus {
        case .waitingForInput: return .systemRed
        case .working: return .systemYellow
        case .idle, .taskCompleted: return .systemGreen
        case .interrupted: return .systemGray
        }
    }

    var activeSession: TerminalSession? {
        sessions.first { $0.id == activeSessionId }
    }

    private init() {
        self.isPinned = UserDefaults.standard.object(forKey: "isPinned") as? Bool ?? true
        loadPersistedSessions()
        if isPinned { startPolling() }
    }

    // MARK: - Session CRUD

    func createSession(projectName: String, projectPath: String? = nil, workingDirectory: String) {
        let session = TerminalSession(
            projectName: projectName,
            projectPath: projectPath,
            workingDirectory: workingDirectory
        )
        sessions.append(session)
        activeSessionId = session.id
        persistSessions()
    }

    func removeSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeSessionId == id {
            activeSessionId = sessions.first?.id
        }
        persistSessions()
    }

    func renameSession(id: UUID, name: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].projectName = name
        persistSessions()
    }

    func selectSession(id: UUID) {
        activeSessionId = id
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].hasBeenSelected = true
        }
    }

    // MARK: - Status Updates

    func updateStatus(sessionId: UUID, status: TerminalStatus) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let previousStatus = sessions[idx].terminalStatus
        sessions[idx].terminalStatus = status

        if status == .working && previousStatus != .working {
            sessions[idx].workingStartedAt = Date()
            startSleepPrevention()
        }

        if previousStatus == .working && status == .idle {
            let duration = sessions[idx].workingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            if duration > 10 {
                taskCompletionTimer?.invalidate()
                let capturedId = sessionId
                taskCompletionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    if let i = self.sessions.firstIndex(where: { $0.id == capturedId }),
                       self.sessions[i].terminalStatus == .idle {
                        self.sessions[i].terminalStatus = .taskCompleted
                        SoundManager.shared.playTaskComplete()
                        NotificationCenter.default.post(name: .leoNotchStatusChanged, object: nil)

                        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                            if let self,
                               let j = self.sessions.firstIndex(where: { $0.id == capturedId }),
                               self.sessions[j].terminalStatus == .taskCompleted {
                                self.sessions[j].terminalStatus = .idle
                                NotificationCenter.default.post(name: .leoNotchStatusChanged, object: nil)
                            }
                        }
                    }
                }
            }
            stopSleepPreventionIfIdle()
        }

        NotificationCenter.default.post(name: .leoNotchStatusChanged, object: nil)
    }

    // MARK: - Persistence

    private func persistSessions() {
        let persisted = sessions.map {
            PersistedSession(id: $0.id, projectName: $0.projectName, projectPath: $0.projectPath, workingDirectory: $0.workingDirectory)
        }
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: "sessions")
        }
        if let id = activeSessionId {
            UserDefaults.standard.set(id.uuidString, forKey: "activeSessionId")
        }
    }

    private func loadPersistedSessions() {
        guard let data = UserDefaults.standard.data(forKey: "sessions"),
              let persisted = try? JSONDecoder().decode([PersistedSession].self, from: data) else { return }
        sessions = persisted.map {
            TerminalSession(projectName: $0.projectName, projectPath: $0.projectPath, workingDirectory: $0.workingDirectory)
        }
        if let idStr = UserDefaults.standard.string(forKey: "activeSessionId") {
            activeSessionId = UUID(uuidString: idStr)
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollEditors()
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func pollEditors() {
        Task { @MainActor in
            let projects = await EditorDetector.shared.detectProjects()
            for project in projects {
                let exists = sessions.contains { $0.projectName == project.name }
                if !exists {
                    createSession(
                        projectName: project.name,
                        projectPath: project.path,
                        workingDirectory: project.directoryPath
                    )
                }
            }
        }
    }

    // MARK: - Sleep Prevention

    private func startSleepPrevention() {
        guard sleepActivity == nil else { return }
        sleepActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
            reason: "Leo: Claude Code is working"
        )
    }

    private func stopSleepPreventionIfIdle() {
        let anyWorking = sessions.contains { $0.terminalStatus == .working }
        if !anyWorking, let activity = sleepActivity {
            ProcessInfo.processInfo.endActivity(activity)
            sleepActivity = nil
        }
    }
}
