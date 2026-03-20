//
//  ZellijPathFinder.swift
//  ClaudeIsland
//
//  Finds zellij executable path
//

import Foundation

/// Finds and caches the zellij executable path
actor ZellijPathFinder {
    static let shared = ZellijPathFinder()

    private var cachedPath: String?

    private init() {}

    /// Get the path to zellij executable
    func getZellijPath() -> String? {
        if let cached = cachedPath {
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
                return path
            }
        }

        return nil
    }

    /// Check if zellij is available
    func isZellijAvailable() -> Bool {
        getZellijPath() != nil
    }
}
