import SwiftUI
import AppKit

struct PanelContentView: View {
    @Bindable var sessionStore: SessionStore
    @State private var isWindowFocused = true
    @State private var showRestoreAlert = false
    @State private var checkpointStatus: String?

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.black)
                .frame(height: 10)

            HStack(spacing: 4) {
                Button(action: { sessionStore.isPinned.toggle() }) {
                    Image(systemName: sessionStore.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)

                WindowDragArea()
                    .frame(maxWidth: .infinity)

                SessionTabBar(sessionStore: sessionStore)

                Button(action: {
                    sessionStore.createSession(
                        projectName: "New Session",
                        workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
                    )
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
            .frame(height: 34)
            .background(Color(nsColor: NSColor(white: 0.14, alpha: isWindowFocused ? 1.0 : 0.5)))

            if let status = checkpointStatus {
                HStack {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore") {
                        showRestoreAlert = true
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(nsColor: NSColor(white: 0.18, alpha: 1.0)))
            }

            if let activeId = sessionStore.activeSessionId,
               sessionStore.sessions.contains(where: { $0.id == activeId }) {
                TerminalSessionView(
                    sessionId: activeId,
                    sessionStore: sessionStore
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Spacer()
                    Text("No active session")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                    Text("Click + to create a new session")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 11))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: NSColor(white: 0.1, alpha: 1.0)))
            }
        }
        .background(Color(nsColor: NSColor(white: 0.1, alpha: 1.0)))
        .alert("Restore Checkpoint?", isPresented: $showRestoreAlert) {
            Button("Restore", role: .destructive) {
                restoreCheckpoint()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will overwrite your working directory with the last checkpoint.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            isWindowFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            isWindowFocused = false
        }
    }

    private func restoreCheckpoint() {
        guard let session = sessionStore.activeSession else { return }
        Task {
            checkpointStatus = "Restoring…"
            let result = await CheckpointManager.shared.restoreLatest(
                projectName: session.projectName,
                workingDirectory: session.workingDirectory
            )
            checkpointStatus = result ? "Restored" : "Restore failed"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                checkpointStatus = nil
            }
        }
    }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DragView()
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class DragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
