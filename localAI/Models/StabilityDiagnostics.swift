import Foundation
import OSLog

struct StabilityDebugStats: Equatable {
    var thinkingToggleCount: Int = 0
    var blockedActionCount: Int = 0
    var modeSwitchWhileGeneratingCount: Int = 0
    var streamingRefreshCount: Int = 0
    var lastActionDescription: String = "idle"
}

struct StabilityDiagnostics {
    private let logger: Logger
    private let signposter: OSSignposter

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "localAI") {
        self.logger = Logger(subsystem: subsystem, category: "stability")
        self.signposter = OSSignposter(logger: logger)
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }
}
