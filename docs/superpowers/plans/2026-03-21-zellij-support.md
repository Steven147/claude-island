# Claude Island Zellij 支持实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Claude Island 添加 Zellij 终端复用器支持，实现与 tmux 并存的独立实现，通过自动检测选择使用哪个后端。

**Architecture:** 创建独立的 Zellij 实现（ZellijController、ZellijPathFinder、ZellijLayoutParser、ZellijTargetFinder），通过 TerminalMultiplexer 路由层自动检测和选择后端，保持现有 tmux 代码完全不变。

**Tech Stack:** Swift 5.9+, macOS 15.6+, Foundation, os.log

---

## 文件结构映射

### 新建文件

```
ClaudeIsland/Models/
├── ZellijTarget.swift              # Zellij 目标标识（session + tab index）

ClaudeIsland/Services/Zellij/
├── ZellijController.swift           # 主控制器，协调所有 zellij 操作
├── ZellijPathFinder.swift           # 查找 zellij 可执行文件路径
├── ZellijLayoutParser.swift         # 解析 dump-layout 输出
├── ZellijTargetFinder.swift         # 通过工作目录查找目标 tab
└── ZellijApprovalHandler.swift      # 预留，暂不实现（空文件）

ClaudeIsland/Services/TerminalMultiplexer/
├── MultiplexerType.swift            # 枚举定义（tmux/zellij/none）
└── TerminalMultiplexer.swift        # 路由层 + 检测逻辑
```

### 不修改的文件

```
ClaudeIsland/Services/Tmux/          # 所有文件保持不变
├── TmuxController.swift
├── TmuxPathFinder.swift
├── TmuxTargetFinder.swift
├── TmuxSessionMatcher.swift
└── ToolApprovalHandler.swift
```

---

## 任务分解

### Task 1: 核心数据结构和枚举

**Files:**
- Create: `ClaudeIsland/Models/ZellijTarget.swift`
- Create: `ClaudeIsland/Services/TerminalMultiplexer/MultiplexerType.swift`

- [ ] **Step 1: 创建 MultiplexerType 枚举**

创建文件 `ClaudeIsland/Services/TerminalMultiplexer/MultiplexerType.swift`:

```swift
//
//  MultiplexerType.swift
//  ClaudeIsland
//
//  Terminal multiplexer type enumeration
//

import Foundation

/// Supported terminal multiplexer types
enum MultiplexerType: Sendable {
    case tmux
    case zellij
    case none
}
```

- [ ] **Step 2: 创建 ZellijTarget 数据结构**

创建文件 `ClaudeIsland/Models/ZellijTarget.swift`:

```swift
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
```

- [ ] **Step 3: 提交基础数据结构**

```bash
git add ClaudeIsland/Services/TerminalMultiplexer/MultiplexerType.swift
git add ClaudeIsland/Models/ZellijTarget.swift
git commit -m "feat: add core data structures for zellij support"
```

---

### Task 2: Zellij 可执行文件查找

**Files:**
- Create: `ClaudeIsland/Services/Zellij/ZellijPathFinder.swift`

- [ ] **Step 1: 创建 ZellijPathFinder**

创建文件 `ClaudeIsland/Services/Zellij/ZellijPathFinder.swift`:

```swift
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
```

- [ ] **Step 2: 验证 ZellijPathFinder 编译**

运行: `xcodebuild -scheme ClaudeIsland -configuration Debug build 2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)"`
预期: BUILD SUCCEEDED

- [ ] **Step 3: 提交 ZellijPathFinder**

```bash
git add ClaudeIsland/Services/Zellij/ZellijPathFinder.swift
git commit -m "feat: add ZellijPathFinder to locate zellij executable"
```

---

### Task 3: Zellij 布局解析器

**Files:**
- Create: `ClaudeIsland/Services/Zellij/ZellijLayoutParser.swift`

- [ ] **Step 1: 创建布局解析数据结构**

创建文件 `ClaudeIsland/Services/Zellij/ZellijLayoutParser.swift`:

```swift
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
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
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
        sessionName = ProcessInfo.processInfo.environment["ZELLIJ_SESSION_NAME"] ?? "default"

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
```

- [ ] **Step 2: 验证 ZellijLayoutParser 编译**

运行: `xcodebuild -scheme ClaudeIsland -configuration Debug build 2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)"`
预期: BUILD SUCCEEDED

- [ ] **Step 3: 提交 ZellijLayoutParser**

```bash
git add ClaudeIsland/Services/Zellij/ZellijLayoutParser.swift
git commit -m "feat: add ZellijLayoutParser to parse dump-layout output"
```

---

### Task 4: Zellij 目标查找器

**Files:**
- Create: `ClaudeIsland/Services/Zellij/ZellijTargetFinder.swift`

- [ ] **Step 1: 创建 ZellijTargetFinder**

创建文件 `ClaudeIsland/Services/Zellij/ZellijTargetFinder.swift`:

```swift
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
```

- [ ] **Step 2: 验证 ZellijTargetFinder 编译**

运行: `xcodebuild -scheme ClaudeIsland -configuration Debug build 2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)"`
预期: BUILD SUCCEEDED

- [ ] **Step 3: 提交 ZellijTargetFinder**

```bash
git add ClaudeIsland/Services/Zellij/ZellijTargetFinder.swift
git commit -m "feat: add ZellijTargetFinder to locate Claude sessions"
```

---

### Task 5: Zellij 控制器

**Files:**
- Create: `ClaudeIsland/Services/Zellij/ZellijController.swift`
- Create: `ClaudeIsland/Services/Zellij/ZellijApprovalHandler.swift` (空文件，预留)

- [ ] **Step 1: 创建 ZellijApprovalHandler 占位文件**

创建文件 `ClaudeIsland/Services/Zellij/ZellijApprovalHandler.swift`:

```swift
//
//  ZellijApprovalHandler.swift
//  ClaudeIsland
//
//  Handles Claude tool approval operations via zellij
//  NOTE: Not implemented in MVP - reserved for future use
//

import Foundation

/// Handles tool approval and rejection for Claude instances (reserved for future)
actor ZellijApprovalHandler {
    static let shared = ZellijApprovalHandler()

    private init() {}

    // TODO: Implement approval functions
    // - approveOnce(target:)
    // - approveAlways(target:)
    // - reject(target:message:)
}
```

- [ ] **Step 2: 创建 ZellijController**

创建文件 `ClaudeIsland/Services/Zellij/ZellijController.swift`:

```swift
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
```

- [ ] **Step 3: 验证 ZellijController 编译**

运行: `xcodebuild -scheme ClaudeIsland -configuration Debug build 2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)"`
预期: BUILD SUCCEEDED

- [ ] **Step 4: 提交 Zellij 控制器**

```bash
git add ClaudeIsland/Services/Zellij/ZellijController.swift
git add ClaudeIsland/Services/Zellij/ZellijApprovalHandler.swift
git commit -m "feat: add ZellijController for high-level operations"
```

---

### Task 6: 终端复用器路由层

**Files:**
- Create: `ClaudeIsland/Services/TerminalMultiplexer/TerminalMultiplexer.swift`

- [ ] **Step 1: 创建 TerminalMultiplexer**

创建文件 `ClaudeIsland/Services/TerminalMultiplexer/TerminalMultiplexer.swift`:

```swift
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
        let env = ProcessInfo.processInfo.environment

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
```

- [ ] **Step 2: 验证 TerminalMultiplexer 编译**

运行: `xcodebuild -scheme ClaudeIsland -configuration Debug build 2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)"`
预期: BUILD SUCCEEDED

- [ ] **Step 3: 提交 TerminalMultiplexer**

```bash
git add ClaudeIsland/Services/TerminalMultiplexer/TerminalMultiplexer.swift
git commit -m "feat: add TerminalMultiplexer routing layer"
```

---

### Task 7: 集成到现有代码（修改调用点）

**Files:**
- Modify: `ClaudeIsland/Services/Window/YabaiController.swift`
- Modify: `ClaudeIsland/Core/NotchViewModel.swift` (可能需要，待确认)

**注意**: 这个任务需要仔细检查哪些地方调用了 TmuxController，需要改为通过 TerminalMultiplexer 路由。

- [ ] **Step 1: 查找所有 TmuxController 调用点**

运行: `grep -rn "TmuxController" ClaudeIsland/ --include="*.swift"`
预期输出: 列出所有调用 TmuxController 的位置

**重要**: 在修改前，先检查 YabaiController 中是否有 workingDirectory 变量可用。如果没有，需要查看函数签名和上下文，确定如何获取 Claude 会话的工作目录。

- [ ] **Step 2: 修改 YabaiController.swift**

打开文件，找到以下行（约第41行和第46行）：
```swift
guard let target = await TmuxController.shared.findTmuxTarget(forClaudePid: claudePid) else {
    return false
}

_ = await TmuxController.shared.switchToPane(target: target)
```

替换为：
```swift
guard let (multiplexerType, target) = await TerminalMultiplexer.shared.findTarget(
    claudePid: claudePid,
    workingDir: workingDirectory
) else {
    return false
}

_ = await TerminalMultiplexer.shared.switchToPane(multiplexerType: multiplexerType, target: target)
```

**注意**: 需要确认 `workingDirectory` 变量是否可用，如果不可用需要从其他地方获取。

- [ ] **Step 3: 验证集成编译**

运行: `xcodebuild -scheme ClaudeIsland -configuration Debug build 2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)"`
预期: BUILD SUCCEEDED

- [ ] **Step 4: 提交集成修改**

```bash
git add ClaudeIsland/Services/Window/YabaiController.swift
git commit -m "feat: integrate TerminalMultiplexer into YabaiController"
```

---

### Task 8: 手动测试

**环境准备:**

- [ ] **Step 1: 准备测试环境**

1. 启动一个 zellij 会话:
   ```bash
   zellij -s test-session
   ```

2. 在 zellij 中打开一个 tab，运行 Claude Code:
   ```bash
   cd /path/to/test/project
   claude
   ```

3. 记录当前 tab 索引（从1开始计数）和工作目录

- [ ] **Step 2: 编译并运行应用**

```bash
xcodebuild -scheme ClaudeIsland -configuration Release build
open "/Users/lsq/Library/Developer/Xcode/DerivedData/ClaudeIsland-*/Build/Products/Release/Claude Island.app"
```

- [ ] **Step 3: 测试检测功能**

1. 检查应用日志，确认检测到 zellij:
   ```bash
   log stream --predicate 'subsystem == "com.claudeisland"' --level debug
   ```

2. 预期看到: `"Detected zellij from environment variable"` 或 `"Detected zellij from running process"`

- [ ] **Step 4: 测试切换功能**

1. 在 Claude 中触发一个通知（比如完成某个任务）
2. 点击通知，观察是否切换到正确的 zellij tab
3. 预期: 切换到运行 Claude 的 tab

- [ ] **Step 5: 测试 tmux 兼容性**

1. 在 tmux 中启动另一个 Claude 会话
2. 验证 tmux 功能仍然正常工作
3. 预期: tmux 切换功能不受影响

- [ ] **Step 6: 测试边界情况**

1. 同时运行 tmux 和 zellij，验证优先级
2. 关闭所有复用器，验证应用不崩溃
3. 在 zellij 中有多个 tab 相同工作目录，验证行为

---

### Task 9: 代码审查和优化

- [ ] **Step 1: 检查所有新文件的代码风格**

确保:
- 文档注释完整
- 错误处理恰当
- 日志记录充分
- 符合 Swift 代码规范

- [ ] **Step 2: 检查编译警告**

运行: `xcodebuild -scheme ClaudeIsland -configuration Debug clean build 2>&1 | grep -i "warning"`
预期: 无严重警告

- [ ] **Step 3: 性能检查**

检查:
- ZellijPathFinder 缓存是否正常
- 布局解析是否高效
- 避免不必要的重复检测

- [ ] **Step 4: 最终提交**

```bash
git add -A
git commit -m "refactor: optimize zellij integration code"
```

---

### Task 10: 文档更新

- [ ] **Step 1: 更新 README.md**

在 `README.md` 中添加 zellij 支持说明:

```markdown
## Requirements

- macOS 15.6+
- Claude Code CLI
- Terminal multiplexer (optional): tmux or zellij

## Features

- **Notch UI** — Animated overlay that expands from the MacBook notch
- **Live Session Monitoring** — Track multiple Claude Code sessions in real-time
- **Permission Approvals** — Approve or deny tool executions directly from the notch
- **Chat History** — View full conversation history with markdown rendering
- **Auto-Setup** — Hooks install automatically on first launch
- **Terminal Multiplexer Support** — Works with both tmux and zellij (auto-detected)
```

- [ ] **Step 2: 创建 CHANGELOG 条目**

如果有 CHANGELOG.md，添加:
```markdown
## [Unreleased]

### Added
- Zellij terminal multiplexer support alongside tmux
- Auto-detection of terminal multiplexer (tmux/zellij)
```

- [ ] **Step 3: 提交文档更新**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: add zellij support documentation"
```

---

## 完成标准

- [ ] 所有代码编译通过，无严重警告
- [ ] 在 zellij 环境中测试通过（检测、切换）
- [ ] tmux 功能不受影响（对比测试）
- [ ] 代码审查完成
- [ ] 文档更新完成
- [ ] 所有提交信息清晰

## 风险和注意事项

1. **Zellij tab 索引起始值**: 需要在实现时验证是从0还是从1开始（规格审查建议）
2. **多个 pane 相同工作目录**: 当前实现返回第一个匹配的 tab（规格审查建议）
3. **API 类型安全**: TerminalMultiplexer 使用 Any 类型，未来可以改进为协议或枚举（规格审查建议）
4. **YabaiController 集成**: 需要确认 workingDirectory 变量是否可用
5. **测试覆盖**: 项目当前无单元测试框架，依赖手动测试

## 回滚计划

如果 zellij 功能出现问题，可以通过以下方式快速回退:

1. 注释掉 TerminalMultiplexer 调用，直接使用 TmuxController
2. 或者在 TerminalMultiplexer.detectMultiplexer() 中硬编码返回 .tmux
3. 所有 tmux 代码保持不变，可以随时完全回退
