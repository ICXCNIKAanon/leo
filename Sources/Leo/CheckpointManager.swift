import Foundation

struct Checkpoint: Identifiable {
    let id: String
    let date: Date
    let commitHash: String

    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

enum CheckpointError: Error {
    case notAGitRepo
    case gitCommandFailed(String)
}

actor CheckpointManager {
    static let shared = CheckpointManager()
    private init() {}

    private let refPrefix = "refs/leo-snapshots"

    func createCheckpoint(projectName: String, workingDirectory: String) async -> Bool {
        do {
            try runGit(["rev-parse", "--git-dir"], in: workingDirectory)

            let timestamp = formatTimestamp(Date())
            let tempIndex = NSTemporaryDirectory() + "leo-index-\(UUID().uuidString)"

            var env = ProcessInfo.processInfo.environment
            env["GIT_INDEX_FILE"] = tempIndex
            try runGit(["add", "-A"], in: workingDirectory, environment: env)

            let treeHash = try runGit(["write-tree"], in: workingDirectory, environment: env)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let commitHash = try runGit(
                ["commit-tree", treeHash, "-m", "Leo checkpoint \(timestamp)"],
                in: workingDirectory
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            let refName = "\(refPrefix)/\(projectName)/\(timestamp)"
            try runGit(["update-ref", refName, commitHash], in: workingDirectory)

            try? FileManager.default.removeItem(atPath: tempIndex)

            return true
        } catch {
            return false
        }
    }

    func listCheckpoints(projectName: String, workingDirectory: String) async -> [Checkpoint] {
        let pattern = "\(refPrefix)/\(projectName)/"
        guard let output = try? runGit(
            ["for-each-ref", "--format=%(refname) %(objectname:short)", pattern],
            in: workingDirectory
        ) else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        return output
            .split(separator: "\n")
            .compactMap { line -> Checkpoint? in
                let parts = line.split(separator: " ", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                let refName = String(parts[0])
                let hash = String(parts[1])

                let components = refName.split(separator: "/")
                guard let timestampStr = components.last,
                      let date = formatter.date(from: String(timestampStr)) else { return nil }

                return Checkpoint(id: refName, date: date, commitHash: hash)
            }
            .sorted { $0.date > $1.date }
    }

    func restoreLatest(projectName: String, workingDirectory: String) async -> Bool {
        let checkpoints = await listCheckpoints(projectName: projectName, workingDirectory: workingDirectory)
        guard let latest = checkpoints.first else { return false }

        do {
            try runGit(["checkout", latest.commitHash, "--", "."], in: workingDirectory)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    private func runGit(
        _ args: [String],
        in directory: String,
        environment: [String: String]? = nil
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        if let env = environment {
            process.environment = env
        }

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw CheckpointError.gitCommandFailed(errorOutput)
        }

        return output
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }
}
