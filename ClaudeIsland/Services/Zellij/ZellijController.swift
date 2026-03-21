//
//  ZellijController.swift
//  ClaudeIsland
//
//  High-level zellij operations controller
//

import Foundation
import os.log

/// Controller for zellij operations
actor ZellijController {
    static let shared = ZellijController()

    nonisolated static let logger = Logger(subsystem: "com.claudeisland", category: "ZellijController")

    private init() {}

    /// Find the zellij target for a Claude process
    func findTarget(forClaudePid pid: Int, workingDir: String) async -> ZellijTarget? {
        // Zellij doesn't support PID-based matching, use working directory
        await findTarget(forWorkingDirectory: workingDir)
    }

    /// Find the zellij target for a working directory
    func findTarget(forWorkingDirectory dir: String) async -> ZellijTarget? {
        await ZellijTargetFinder.shared.findTarget(forWorkingDirectory: dir)
    }

    /// Switch to a specific tab
    func switchToPane(target: ZellijTarget) async -> Bool {
        guard let zellijPath = await ZellijPathFinder.shared.getZellijPath() else {
            Self.logger.warning("Zellij executable not found")
            return false
        }

        do {
            Self.logger.info("Switching to zellij tab \(target.tabIndex) in session \(target.sessionName)")

            _ = try await ProcessExecutor.shared.run(zellijPath, arguments: [
                "action", "go-to-tab", "\(target.tabIndex)"
            ])

            return true
        } catch {
            Self.logger.error("Failed to switch to tab: \(error.localizedDescription)")
            return false
        }
    }

    /// Check if zellij is available
    func isZellijAvailable() async -> Bool {
        await ZellijPathFinder.shared.isZellijAvailable()
    }
}
