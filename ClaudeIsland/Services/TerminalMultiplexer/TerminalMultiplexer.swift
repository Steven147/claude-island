//
//  TerminalMultiplexer.swift
//  ClaudeIsland
//
//  Routes terminal multiplexer operations to appropriate backend (tmux/zellij)
//

import Foundation
import os.log

/// Routes terminal multiplexer operations to the appropriate backend
actor TerminalMultiplexer {
    static let shared = TerminalMultiplexer()

    nonisolated static let logger = Logger(subsystem: "com.claudeisland", category: "TerminalMultiplexer")

    private var detectedType: MultiplexerType?
    private var hasChecked = false

    private init() {}

    /// Detect which terminal multiplexer is currently active
    func detectMultiplexer() -> MultiplexerType {
        if hasChecked, let cached = detectedType {
            return cached
        }

        // Priority 1: Check environment variables
        let env = Foundation.ProcessInfo.processInfo.environment

        if env["ZELLIJ_SESSION_NAME"] != nil {
            Self.logger.info("Detected zellij from environment variable")
            detectedType = .zellij
            hasChecked = true
            return .zellij
        }

        if env["TMUX"] != nil {
            Self.logger.info("Detected tmux from environment variable")
            detectedType = .tmux
            hasChecked = true
            return .tmux
        }

        // Priority 2: Check running processes
        if isZellijRunning() {
            Self.logger.info("Detected zellij from running process")
            detectedType = .zellij
            hasChecked = true
            return .zellij
        }

        if isTmuxRunning() {
            Self.logger.info("Detected tmux from running process")
            detectedType = .tmux
            hasChecked = true
            return .tmux
        }

        Self.logger.info("No terminal multiplexer detected")
        detectedType = .none
        hasChecked = true
        return .none
    }

    /// Find target for a Claude process
    func findTarget(claudePid: Int, workingDir: String) async -> (MultiplexerType, Any)? {
        let multiplexerType = detectMultiplexer()

        switch multiplexerType {
        case .tmux:
            if let target = await TmuxController.shared.findTmuxTarget(forClaudePid: claudePid) {
                return (.tmux, target)
            }
            return nil

        case .zellij:
            if let target = await ZellijController.shared.findTarget(forClaudePid: claudePid, workingDir: workingDir) {
                return (.zellij, target)
            }
            return nil

        case .none:
            return nil
        }
    }

    /// Switch to a target pane
    func switchToPane(multiplexerType: MultiplexerType, target: Any) async -> Bool {
        switch multiplexerType {
        case .tmux:
            guard let tmuxTarget = target as? TmuxTarget else {
                Self.logger.error("Invalid target type for tmux")
                return false
            }
            return await TmuxController.shared.switchToPane(target: tmuxTarget)

        case .zellij:
            guard let zellijTarget = target as? ZellijTarget else {
                Self.logger.error("Invalid target type for zellij")
                return false
            }
            return await ZellijController.shared.switchToPane(target: zellijTarget)

        case .none:
            Self.logger.warning("Cannot switch pane: no multiplexer detected")
            return false
        }
    }

    // MARK: - Private Methods

    private func isZellijRunning() -> Bool {
        guard let output = ProcessExecutor.shared.runSyncOrNil("/bin/ps", arguments: ["aux"]) else {
            return false
        }
        return output.contains("zellij") && !output.contains("grep zellij")
    }

    private func isTmuxRunning() -> Bool {
        guard let output = ProcessExecutor.shared.runSyncOrNil("/bin/ps", arguments: ["aux"]) else {
            return false
        }
        return output.contains("tmux") && !output.contains("grep tmux")
    }
}
