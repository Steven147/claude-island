//
//  ZellijTarget.swift
//  ClaudeIsland
//
//  Data model for zellij session/tab targeting
//

import Foundation

/// Represents a zellij target (session + tab index)
struct ZellijTarget: Sendable {
    let sessionName: String
    let tabIndex: Int  // Note: zellij tab index starts from 1
    let paneId: String?  // Optional, for future precise pane targeting

    nonisolated var targetString: String {
        "\(sessionName):tab:\(tabIndex)"
    }

    nonisolated init(sessionName: String, tabIndex: Int, paneId: String? = nil) {
        self.sessionName = sessionName
        self.tabIndex = tabIndex
        self.paneId = paneId
    }
}
