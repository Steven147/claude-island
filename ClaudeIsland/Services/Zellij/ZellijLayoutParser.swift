//
//  ZellijLayoutParser.swift
//  ClaudeIsland
//
//  Parses zellij dump-layout output
//

import Foundation
import os.log

/// Represents a parsed zellij pane
struct ZellijPane: Sendable {
    let cwd: String
    let command: String?
    let isFloating: Bool
}

/// Represents a parsed zellij tab
struct ZellijTab: Sendable {
    let name: String
    let index: Int
    let panes: [ZellijPane]
}

/// Represents a parsed zellij layout
struct ZellijLayout: Sendable {
    let sessionName: String
    let tabs: [ZellijTab]
}

/// Parses zellij dump-layout output
actor ZellijLayoutParser {
    static let shared = ZellijLayoutParser()

    nonisolated static let logger = Logger(subsystem: "com.claudeisland", category: "ZellijLayoutParser")

    private init() {}

    /// Parse zellij dump-layout output into structured data
    func parse(_ output: String) -> ZellijLayout? {
        let lines = output.components(separatedBy: "\n")
        var iterator = lines.makeIterator()

        guard parseExpectedToken("layout", from: &iterator),
              parseExpectedToken("{", from: &iterator) else {
            Self.logger.error("Failed to parse layout header")
            return nil
        }

        var sessionName = ""
        var tabs: [ZellijTab] = []
        var currentTabIndex = 1

        while let line = iterator.next() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("cwd") {
                // Extract session-level cwd (not used currently)
                continue
            } else if trimmed.hasPrefix("tab") {
                if let tab = parseTab(from: trimmed, iterator: &iterator, tabIndex: currentTabIndex) {
                    tabs.append(tab)
                    currentTabIndex += 1
                }
            } else if trimmed == "}" {
                // End of layout
                break
            }
        }

        // Extract session name from environment or use default
        sessionName = Foundation.ProcessInfo.processInfo.environment["ZELLIJ_SESSION_NAME"] ?? "default"

        return ZellijLayout(sessionName: sessionName, tabs: tabs)
    }

    // MARK: - Private Parsing Methods

    private func parseExpectedToken(_ expected: String, from iterator: inout Array<String>.Iterator) -> Bool {
        guard let line = iterator.next() else { return false }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix(expected)
    }

    private func parseTab(from line: String, iterator: inout Array<String>.Iterator, tabIndex: Int) -> ZellijTab? {
        // Parse: tab name="env" hide_floating_panes=true {
        var tabName = "tab-\(tabIndex)"

        // Extract tab name
        if let nameRange = line.range(of: "name=\"") {
            let startIndex = nameRange.upperBound
            if let endIndex = line[startIndex...].firstIndex(of: "\"") {
                tabName = String(line[startIndex..<endIndex])
            }
        }

        var panes: [ZellijPane] = []

        // Parse tab content
        while let nextLine = iterator.next() {
            let trimmed = nextLine.trimmingCharacters(in: .whitespaces)

            if trimmed == "}" {
                // End of tab
                break
            } else if trimmed.hasPrefix("pane") {
                if let pane = parsePane(from: trimmed, iterator: &iterator) {
                    panes.append(pane)
                }
            }
        }

        return ZellijTab(name: tabName, index: tabIndex, panes: panes)
    }

    private func parsePane(from line: String, iterator: inout Array<String>.Iterator) -> ZellijPane? {
        // Parse: pane command="claude" cwd="env" size="50%" {
        // or: pane size=1 borderless=true {

        var cwd = ""
        var command: String? = nil
        var isFloating = false

        // Extract cwd
        if let cwdRange = line.range(of: "cwd=\"") {
            let startIndex = cwdRange.upperBound
            if let endIndex = line[startIndex...].firstIndex(of: "\"") {
                cwd = String(line[startIndex..<endIndex])
            }
        }

        // Extract command
        if let cmdRange = line.range(of: "command=\"") {
            let startIndex = cmdRange.upperBound
            if let endIndex = line[startIndex...].firstIndex(of: "\"") {
                command = String(line[startIndex..<endIndex])
            }
        }

        // Check if floating (pane in floating_panes block)
        isFloating = line.contains("floating") || line.contains("floating_panes")

        // Skip nested content (recurisve panes)
        if line.contains("{") {
            var braceCount = 1
            while braceCount > 0, let nextLine = iterator.next() {
                let trimmed = nextLine.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("{") { braceCount += 1 }
                if trimmed.contains("}") { braceCount -= 1 }
            }
        }

        guard !cwd.isEmpty else {
            return nil
        }

        return ZellijPane(cwd: cwd, command: command, isFloating: isFloating)
    }
}
