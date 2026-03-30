import SwiftUI

struct CrystalBallView: View {
    let status: TerminalStatus
    let size: CGFloat

    @State private var glowPulse = false

    var body: some View {
        Text("🔮")
            .font(.system(size: size))
            .shadow(color: glowColor, radius: glowRadius)
            .shadow(color: glowColor, radius: glowRadius * 0.5)
            .onChange(of: status) { _, newStatus in
                updateGlow(for: newStatus)
            }
            .onAppear {
                updateGlow(for: status)
            }
    }

    private var glowColor: Color {
        switch status {
        case .idle:
            return .clear
        case .working:
            return Color(hex: "#D4A843").opacity(glowPulse ? 0.8 : 0.3)
        case .waitingForInput:
            return Color(hex: "#C0392B").opacity(glowPulse ? 1.0 : 0.4)
        case .taskCompleted:
            return Color(hex: "#FFD700").opacity(glowPulse ? 1.0 : 0.6)
        case .interrupted:
            return .clear
        }
    }

    private var glowRadius: CGFloat {
        switch status {
        case .idle, .interrupted: return 0
        case .working: return glowPulse ? 6 : 2
        case .waitingForInput: return glowPulse ? 8 : 3
        case .taskCompleted: return glowPulse ? 10 : 4
        }
    }

    private func updateGlow(for status: TerminalStatus) {
        switch status {
        case .working:
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        case .waitingForInput:
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        case .taskCompleted:
            glowPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.easeOut(duration: 0.5)) {
                    glowPulse = false
                }
            }
        case .idle, .interrupted:
            withAnimation(.easeOut(duration: 0.3)) {
                glowPulse = false
            }
        }
    }
}
