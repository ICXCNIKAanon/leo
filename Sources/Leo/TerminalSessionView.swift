import SwiftUI
import SwiftTerm

struct TerminalSessionView: NSViewRepresentable {
    let sessionId: UUID
    @Bindable var sessionStore: SessionStore

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        attachTerminal(to: container, context: context)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let session = sessionStore.sessions.first { $0.id == sessionId }
        let generation = session?.generation ?? 0

        if context.coordinator.currentSessionId != sessionId ||
           context.coordinator.currentGeneration != generation {
            nsView.subviews.forEach { $0.removeFromSuperview() }
            attachTerminal(to: nsView, context: context)
        }
    }

    private func attachTerminal(to container: NSView, context: Context) {
        guard let session = sessionStore.sessions.first(where: { $0.id == sessionId }) else { return }

        if !session.hasStarted {
            if let idx = sessionStore.sessions.firstIndex(where: { $0.id == sessionId }) {
                sessionStore.sessions[idx].hasStarted = true
            }
        }

        let terminal = TerminalManager.shared.terminal(for: session)
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminal)

        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: container.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        context.coordinator.currentSessionId = sessionId
        context.coordinator.currentGeneration = session.generation

        DispatchQueue.main.async {
            terminal.window?.makeFirstResponder(terminal)
        }
    }

    class Coordinator {
        var currentSessionId: UUID?
        var currentGeneration: Int = 0
    }
}
