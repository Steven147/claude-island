//
//  MultiplexerType.swift
//  ClaudeIsland
//
//  Terminal multiplexer type enumeration
//

import Foundation

/// Supported terminal multiplexer types
enum MultiplexerType: Sendable, Equatable {
    case tmux
    case zellij
    case none
}
