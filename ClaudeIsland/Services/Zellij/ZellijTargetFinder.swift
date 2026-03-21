//
//  ZellijTargetFinder.swift
//  ClaudeIsland
//
//  Finds zellij targets for Claude processes
//

import Foundation
import os.log

/// Finds zellij session/tab targets for Claude processes
actor ZellijTargetFinder {
    static let shared = ZellijTargetFinder()

    nonisolated static let logger = Logger(subsystem: "com.claudeisland", category: "ZellijTargetFinder")

    private init() {}

    /// Find the zellij target for a given working directory
    func findTarget(forWorkingDirectory workingDir: String) async -> ZellijTarget? {
        guard let layout = await getLayout() else {
            Self.logger.warning("Failed to get zellij layout")
            return nil
        }

        // Normalize working directory
        let normalizedWorkingDir = normalizePath(workingDir)

        // Search through all tabs and panes
        for tab in layout.tabs {
            for pane in tab.panes {
                let normalizedPaneCwd = normalizePath(pane.cwd)

                if normalizedPaneCwd == normalizedWorkingDir {
                    Self.logger.info("Found matching pane in tab '\(tab.name)' for directory: \(workingDir)")
                    return ZellijTarget(
                        sessionName: layout.sessionName,
                        tabIndex: tab.index,
                        paneId: nil
                    )
                }
            }
        }

        Self.logger.info("No matching pane found for working directory: \(workingDir)")
        return nil
    }

    // MARK: - Private Methods

    private func getLayout() async -> ZellijLayout? {
        guard let zellijPath = await ZellijPathFinder.shared.getZellijPath() else {
            Self.logger.warning("Zellij executable not found")
            return nil
        }

        do {
            let output = try await ProcessExecutor.shared.run(zellijPath, arguments: ["action", "dump-layout"])

            guard let layout = await ZellijLayoutParser.shared.parse(output) else {
                Self.logger.error("Failed to parse zellij layout")
                return nil
            }

            return layout
        } catch {
            Self.logger.error("Failed to get zellij layout: \(error.localizedDescription)")
            return nil
        }
    }

    private func normalizePath(_ path: String) -> String {
        // Resolve relative paths and symlinks
        let url = URL(fileURLWithPath: path)
        let standardized = url.standardized
        return standardized.path
    }
}
