import AppKit

final class SoundManager {
    static let shared = SoundManager()
    private init() {}

    func playTaskComplete() {
        guard SettingsManager.shared.soundEnabled else { return }
        NSSound(named: "Glass")?.play()
    }
}
