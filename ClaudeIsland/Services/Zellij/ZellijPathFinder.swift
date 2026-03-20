//
//  ZellijPathFinder.swift
//  ClaudeIsland
//
//  Finds zellij executable path
//

import Foundation
import os.log

/// Finds and caches the zellij executable path
actor ZellijPathFinder {
    static let shared = ZellijPathFinder()

    nonisolated static let logger = Logger(subsystem: "com.claudeisland", category: "ZellijPathFinder")

    private var cachedPath: String?

    private init() {}

    /// Get the path to zellij executable
    func getZellijPath() -> String? {
        if let cached = cachedPath {
            Self.logger.debug("Returning cached zellij path: \(cached)")
            return cached
        }

        let possiblePaths = [
            "/opt/homebrew/bin/zellij",  // Apple Silicon Homebrew
            "/usr/local/bin/zellij",     // Intel Homebrew
            "/usr/bin/zellij",           // System
            "/bin/zellij"
        ]

        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedPath = path
                Self.logger.info("Found zellij executable at: \(path)")
                return path
            }
        }

        Self.logger.warning("Zellij executable not found in any standard path")
        return nil
    }

    /// Check if zellij is available
    func isZellijAvailable() -> Bool {
        getZellijPath() != nil
    }
}
