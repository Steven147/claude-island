//
//  YabaiController.swift
//  ClaudeIsland
//
//  High-level yabai window management controller
//

import Foundation

/// Controller for yabai window management
actor YabaiController {
    static let shared = YabaiController()

    private init() {}

    // MARK: - Public API

    /// Focus the terminal window for a given Claude PID (tmux only)
    func focusWindow(forClaudePid claudePid: Int) async -> Bool {
        guard await WindowFinder.shared.isYabaiAvailable() else {
            return false
        }

        let windows = await WindowFinder.shared.getAllWindows()
        let tree = ProcessTreeBuilder.shared.buildTree()

        return await focusTmuxInstance(claudePid: claudePid, tree: tree, windows: windows)
    }

    /// Focus the terminal window for a given working directory (tmux only, fallback)
    func focusWindow(forWorkingDirectory workingDirectory: String) async -> Bool {
        guard await WindowFinder.shared.isYabaiAvailable() else { return false }

        return await focusWindow(forWorkingDir: workingDirectory)
    }

    // MARK: - Private Implementation

    private func focusTmuxInstance(claudePid: Int, tree: [Int: ProcessInfo], windows: [YabaiWindow]) async -> Bool {
        // Get working directory for this Claude process
        guard let workingDirectory = ProcessTreeBuilder.shared.getWorkingDirectory(forPid: claudePid) else {
            return false
        }

        // Find the multiplexer target for this Claude process
        guard let (multiplexerType, target) = await TerminalMultiplexer.shared.findTarget(
            claudePid: claudePid,
            workingDir: workingDirectory
        ) else {
            return false
        }

        // Switch to the correct pane
        _ = await TerminalMultiplexer.shared.switchToPane(multiplexerType: multiplexerType, target: target)

        // Extract session name from target for terminal lookup
        let sessionName: String
        if multiplexerType == .tmux, let tmuxTarget = target as? TmuxTarget {
            sessionName = tmuxTarget.session
        } else {
            // For zellij or other types, we don't have session-based terminal lookup
            return true
        }

        // Find terminal for this specific multiplexer session
        if let terminalPid = await findTmuxClientTerminal(forSession: sessionName, tree: tree, windows: windows) {
            return await WindowFocuser.shared.focusTmuxWindow(terminalPid: terminalPid, windows: windows)
        }

        return false
    }

    private func focusWindow(forWorkingDir workingDir: String) async -> Bool {
        let windows = await WindowFinder.shared.getAllWindows()
        let tree = ProcessTreeBuilder.shared.buildTree()

        return await focusTmuxPane(forWorkingDir: workingDir, tree: tree, windows: windows)
    }

    // MARK: - Tmux Helpers

    private func findTmuxClientTerminal(forSession session: String, tree: [Int: ProcessInfo], windows: [YabaiWindow]) async -> Int? {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else { return nil }

        do {
            // Get clients attached to this specific session
            let output = try await ProcessExecutor.shared.run(tmuxPath, arguments: [
                "list-clients", "-t", session, "-F", "#{client_pid}"
            ])

            let clientPids = output.components(separatedBy: "\n")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

            let windowPids = Set(windows.map { $0.pid })

            for clientPid in clientPids {
                var currentPid = clientPid
                while currentPid > 1 {
                    guard let info = tree[currentPid] else { break }
                    if isTerminalProcess(info.command) && windowPids.contains(currentPid) {
                        return currentPid
                    }
                    currentPid = info.ppid
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    /// Check if command is a terminal (nonisolated helper to avoid MainActor access)
    private nonisolated func isTerminalProcess(_ command: String) -> Bool {
        let terminalCommands = ["Terminal", "iTerm", "iTerm2", "Alacritty", "kitty", "WezTerm", "wezterm-gui", "Hyper"]
        return terminalCommands.contains { command.contains($0) }
    }

    private func focusTmuxPane(forWorkingDir workingDir: String, tree: [Int: ProcessInfo], windows: [YabaiWindow]) async -> Bool {
        // Find the multiplexer target for this working directory
        guard let (multiplexerType, target) = await TerminalMultiplexer.shared.findTarget(forWorkingDirectory: workingDir) else {
            return false
        }

        // Switch to the correct pane
        _ = await TerminalMultiplexer.shared.switchToPane(multiplexerType: multiplexerType, target: target)

        // Extract session name from target for terminal lookup
        let sessionName: String?
        if multiplexerType == .tmux, let tmuxTarget = target as? TmuxTarget {
            sessionName = tmuxTarget.session
        } else {
            sessionName = nil
        }

        // Find terminal for this specific multiplexer session
        if let session = sessionName,
           let terminalPid = await findTmuxClientTerminal(forSession: session, tree: tree, windows: windows) {
            return await WindowFocuser.shared.focusTmuxWindow(terminalPid: terminalPid, windows: windows)
        }

        return true
    }
}
