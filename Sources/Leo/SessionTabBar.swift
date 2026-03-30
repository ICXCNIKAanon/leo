import SwiftUI
import AppKit

struct SessionTabBar: View {
    @Bindable var sessionStore: SessionStore
    @State private var hoveredId: UUID?
    @State private var renameId: UUID?
    @State private var renameText = ""
    @State private var showRenameAlert = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(sessionStore.sessions) { session in
                SessionTab(
                    session: session,
                    isActive: session.id == sessionStore.activeSessionId,
                    isHovered: session.id == hoveredId,
                    onSelect: { sessionStore.selectSession(id: session.id) },
                    onClose: { sessionStore.removeSession(id: session.id) },
                    onRename: {
                        renameId = session.id
                        renameText = session.projectName
                        showRenameAlert = true
                    }
                )
                .onHover { isHovering in
                    hoveredId = isHovering ? session.id : nil
                }
            }
        }
        .alert("Rename Session", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let id = renameId {
                    sessionStore.renameSession(id: id, name: renameText)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct SessionTab: View {
    let session: TerminalSession
    let isActive: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            statusIndicator
            Text(session.projectName)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tabBackground)
        .cornerRadius(4)
        .onTapGesture { onSelect() }
        .contextMenu {
            Button("Rename…") { onRename() }
            Button("Close") { onClose() }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch session.terminalStatus {
        case .working:
            SpinnerView(size: 8, color: .white)
        case .waitingForInput:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.yellow)
        case .taskCompleted:
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.green)
        case .idle, .interrupted:
            Circle()
                .fill(Color.gray)
                .frame(width: 6, height: 6)
                .opacity(0.4)
        }
    }

    private var tabBackground: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(Color.accentColor.opacity(0.15))
        } else if isHovered {
            return AnyShapeStyle(Color.white.opacity(0.05))
        } else {
            return AnyShapeStyle(Color.clear)
        }
    }
}
