# Claude Island Zellij 支持设计文档

**日期**: 2026-03-21
**状态**: 设计阶段
**作者**: Claude Assistant

## 概述

为 Claude Island 添加 Zellij 终端复用器支持，实现与 tmux 并存的独立实现，通过自动检测选择使用哪个后端。

## 目标

### 主要目标
- 支持 Zellij 作为 tmux 之外的终端复用器选项
- 实现最小可行版本：检测、查找目标 pane、切换功能
- 保持 tmux 实现完全不变，确保稳定性

### 非目标
- 不实现审批功能（批准/拒绝）- 留作后续迭代
- 不重构现有 tmux 代码
- 不提供用户手动选择复用器的 UI（自动检测即可）

## 架构设计

### 整体架构

```
┌─────────────────────────────────┐
│      NotchViewModel / UI        │
│   (无需改动，调用统一接口)        │
└────────────┬────────────────────┘
             │
    ┌────────▼──────────────┐
    │ TerminalMultiplexer   │  ← 新增：路由层
    │   (检测并选择后端)      │
    └────┬─────────┬────────┘
         │         │
    ┌────▼──┐  ┌──▼──────┐
    │ Tmux  │  │ Zellij  │
    │Controller│Controller│  ← 完全独立
    │(保留不动)│ │(新建)   │
    └───────┘  └─────────┘
```

### 设计原则

1. **独立性**: tmux 和 zellij 实现完全隔离，互不影响
2. **稳定性**: 保留现有 tmux 代码不动，降低风险
3. **可扩展**: 为未来添加其他复用器预留空间
4. **优雅降级**: 所有错误都不影响应用核心功能

## 组件设计

### 文件结构

```
ClaudeIsland/Services/
├── Tmux/                          # 现有，不动
│   ├── TmuxController.swift
│   ├── TmuxPathFinder.swift
│   ├── TmuxTargetFinder.swift
│   ├── TmuxSessionMatcher.swift
│   └── ToolApprovalHandler.swift
│
├── Zellij/                        # 新增
│   ├── ZellijController.swift      # 主控制器
│   ├── ZellijPathFinder.swift      # 查找可执行文件
│   ├── ZellijLayoutParser.swift    # 解析 dump-layout 输出
│   ├── ZellijTargetFinder.swift    # 查找目标 pane
│   └── ZellijApprovalHandler.swift # 发送审批按键（预留，暂不实现）
│
├── TerminalMultiplexer/           # 新增
│   ├── TerminalMultiplexer.swift   # 路由层 + 检测
│   └── MultiplexerType.swift       # 枚举定义
│
└── Models/
    ├── TmuxTarget.swift           # 现有
    └── ZellijTarget.swift         # 新增
```

### 核心数据结构

```swift
// MultiplexerType.swift
enum MultiplexerType {
    case tmux
    case zellij
    case none
}

// ZellijTarget.swift
struct ZellijTarget: Sendable {
    let sessionName: String
    let tabIndex: Int
    let paneId: String?  // 可选，用于未来精确 pane 定位

    var targetString: String {
        "\(sessionName):tab:\(tabIndex)"
    }
}

// ZellijLayoutParser 解析结果
struct ZellijPane: Sendable {
    let cwd: String
    let command: String?
    let isFloating: Bool
}

struct ZellijTab: Sendable {
    let name: String
    let index: Int
    let panes: [ZellijPane]
}

struct ZellijLayout: Sendable {
    let sessionName: String
    let tabs: [ZellijTab]
}
```

### 组件职责

#### TerminalMultiplexer（新增）
- **职责**: 检测当前使用的终端复用器，路由调用到对应实现
- **输入**: Claude 进程 PID、工作目录
- **输出**: 目标标识（TmuxTarget 或 ZellijTarget）
- **依赖**: TmuxController, ZellijController

#### ZellijController（新增）
- **职责**: zellij 操作的高层协调器
- **主要方法**:
  - `findTarget(forClaudePid:workingDir:)` - 查找目标
  - `switchToPane(target:)` - 切换到目标 pane
- **依赖**: ZellijPathFinder, ZellijTargetFinder

#### ZellijPathFinder（新增）
- **职责**: 查找 zellij 可执行文件路径
- **实现**: 检查标准路径（/opt/homebrew/bin, /usr/local/bin 等）
- **缓存**: 首次找到后缓存路径

#### ZellijLayoutParser（新增）
- **职责**: 解析 `zellij action dump-layout` 的输出
- **输入**: 布局字符串
- **输出**: ZellijLayout 结构
- **挑战**: 处理嵌套的 pane 结构

#### ZellijTargetFinder（新增）
- **职责**: 通过工作目录匹配找到目标 tab
- **方法**: 遍历布局中的所有 tab，匹配 pane 的 cwd 字段
- **返回**: ZellijTarget 或 nil

## 数据流设计

### 场景 1: 检测终端复用器

```
应用启动 / 会话创建
    ↓
TerminalMultiplexer.detectMultiplexer()
    ↓
检查环境变量
  - ZELLIJ_SESSION_NAME → .zellij
  - TMUX → .tmux
    ↓
检查进程（如果环境变量都没有）
  - ps aux | grep zellij
  - ps aux | grep tmux
    ↓
返回 MultiplexerType (.zellij / .tmux / .none)
    ↓
缓存结果到单例
```

**检测优先级**: 环境变量 > 进程检查

### 场景 2: 查找 Claude 会话对应的 pane

```
ClaudeSessionMonitor 检测到新会话
    ↓
TerminalMultiplexer.findTarget(claudePid: Int, workingDir: String)
    ↓
根据缓存的 multiplexer 类型路由
    ├─ .tmux  → TmuxController.findTarget(forClaudePid:)
    │           └─ TmuxTargetFinder.findTarget()
    │               ├─ 列出所有 pane PID
    │               └─ 进程树匹配
    │
    └─ .zellij → ZellijController.findTarget(workingDir:)
                └─ ZellijTargetFinder.findTarget()
                    ├─ ZellijPathFinder.getLayout()
                    │   └─ zellij action dump-layout
                    ├─ ZellijLayoutParser.parse()
                    │   └─ 解析为 ZellijLayout 结构
                    └─ 遍历 tabs，匹配 cwd
                        └─ 返回 ZellijTarget
```

**关键差异**:
- tmux: 使用进程树匹配（PID 层级关系）
- zellij: 使用工作目录匹配（cwd 字段）

### 场景 3: 切换到目标 pane

```
用户点击通知 / 需要聚焦
    ↓
TerminalMultiplexer.switchToPane(target:)
    ↓
根据 target 类型分发
    ├─ TmuxTarget → TmuxController.switchToPane()
    │               └─ tmux select-window + select-pane
    │
    └─ ZellijTarget → ZellijController.switchToPane()
                    └─ zellij action go-to-tab <index>
```

**限制**: zellij 只能切换到 tab 级别，无法精确定位到具体 pane

### 场景 4: 发送审批操作（预留接口）

```
用户点击批准/拒绝
    ↓
TerminalMultiplexer.sendApproval(action:, target:)
    ↓
根据 target 类型分发
    ├─ TmuxTarget → ToolApprovalHandler.approveOnce/Always/Reject()
    │               └─ tmux send-keys
    │
    └─ ZellijTarget → ZellijApprovalHandler.sendApproval()
                    └─ zellij action write-chars (预留)
```

**状态**: 此功能暂不实现，留作后续迭代

## Zellij 命令验证结果

### 已验证可用命令

| 功能 | 命令 | 输出格式 | 用途 |
|------|------|---------|------|
| 列出会话 | `zellij list-sessions` | 会话名称列表 | 检测活动会话 |
| 导出布局 | `zellij action dump-layout` | 结构化文本 | 获取所有 pane 的 cwd 和 command |
| 切换 tab | `zellij action go-to-tab <index>` | 无输出 | 切换到指定 tab |
| 发送字符 | `zellij action write-chars <chars>` | 无输出 | 向 pane 发送按键（预留） |
| 捕获内容 | `zellij action dump-screen -f <path>` | 写入文件 | 捕获 pane 内容（预留） |

### dump-layout 输出示例

```
layout {
    cwd "/Users/lsq"
    tab name="env" hide_floating_panes=true {
        pane size=1 borderless=true {
            plugin location="zellij:tab-bar"
        }
        pane split_direction="vertical" {
            pane command="claude" cwd="env" size="50%" {
                start_suspended true
            }
            pane size="50%" {
                pane cwd="env" size="50%"
                pane command="lazygit" cwd="env" size="50%" {
                    start_suspended true
                }
            }
        }
        pane size=1 borderless=true {
            plugin location="zellij:status-bar"
        }
    }
}
```

**关键字段**:
- `command="claude"` - 运行的命令
- `cwd="env"` - 工作目录（可用于匹配）
- `tab name="env"` - tab 名称
- 嵌套的 `pane` 结构需要递归解析

### 与 tmux 的关键差异

| 特性 | tmux | zellij |
|------|------|--------|
| 目标标识 | `session:window.pane` | session + tab index |
| 精确定位 pane | ✅ 支持 | ❌ 只能到 tab 级别 |
| 获取 pane PID | ✅ `#{pane_pid}` | ❌ 无直接方法 |
| 获取工作目录 | ✅ `#{pane_current_path}` | ✅ 通过 dump-layout |
| 捕获内容 | ✅ `capture-pane -p` | ✅ `dump-screen -f` |
| 发送按键 | ✅ `send-keys` | ✅ `write-chars` |

## 错误处理设计

### 错误类型

```swift
enum TerminalMultiplexerError: Error {
    case notDetected                    // 未检测到终端复用器
    case commandNotFound(String)        // 可执行文件不存在
    case executionFailed(String, Int)   // 命令执行失败
    case layoutParseError               // 布局解析失败
    case targetNotFound                 // 找不到目标 pane
}
```

### 错误处理策略

#### 1. 检测阶段
```swift
case .none:
    // 静默处理，不报错
    logger.info("No terminal multiplexer detected")
    // UI 继续显示会话，但不提供 pane 切换功能
```

#### 2. 路径查找阶段
```swift
// 找不到可执行文件
guard let zellijPath = ZellijPathFinder.shared.getZellijPath() else {
    logger.warning("Zellij executable not found")
    return nil
}
```

#### 3. 布局解析阶段
```swift
do {
    let layout = try ZellijLayoutParser.parse(output)
} catch {
    logger.error("Failed to parse layout: \(error)")
    return nil
}
```

#### 4. 目标查找阶段
```swift
// 找不到匹配的工作目录
logger.info("No matching pane for working directory: \(workingDir)")
return nil
```

#### 5. 切换 pane 阶段
```swift
do {
    _ = try await ProcessExecutor.shared.run(zellijPath, arguments: [...])
    return true
} catch {
    logger.error("Failed to switch tab: \(error)")
    return false
}
```

### 错误处理原则
- **不崩溃**: 所有错误都优雅降级
- **详细日志**: 记录所有失败情况用于调试
- **返回可选值**: 失败返回 nil 而不是抛出异常
- **用户透明**: UI 层不显示错误，功能静默失效

## 测试策略

### 单元测试

#### ZellijLayoutParserTests.swift
- `testParseSimpleLayout()` - 解析简单布局
- `testParseLayoutWithMultipleTabs()` - 解析多 tab 布局
- `testParseLayoutWithNestedPanes()` - 解析嵌套 pane
- `testParseEmptyLayout()` - 解析空布局
- `testParseInvalidLayout()` - 解析无效格式

#### ZellijTargetFinderTests.swift
- `testFindTargetByWorkingDirectory()` - 通过工作目录匹配
- `testFindTargetNotFound()` - 找不到目标
- `testFindTargetInMultipleTabs()` - 在多个 tab 中查找

### 集成测试

#### ZellijControllerIntegrationTests.swift
- `testDetectZellijSession()` - 检测 zellij 会话
- `testGetLayoutFromRealSession()` - 从真实会话获取布局
- `testSwitchToTab()` - 切换 tab

#### TerminalMultiplexerTests.swift
- `testDetectTmuxPriority()` - tmux 优先级
- `testDetectZellijPriority()` - zellij 优先级
- `testDetectNone()` - 都没有的情况
- `testRoutingLogic()` - 路由逻辑

### 手动测试清单

#### 环境准备
- [ ] 在 zellij 中启动一个会话
- [ ] 在某个 tab 中运行 Claude Code
- [ ] 记录 tab 索引和工作目录

#### 基础功能
- [ ] 应用启动后能检测到 zellij
- [ ] 点击通知能切换到正确的 tab
- [ ] 在 notch UI 中能看到会话状态

#### 边界情况
- [ ] 同时运行 tmux 和 zellij，检测优先级正确
- [ ] zellij 会话中没有 Claude，功能静默失效
- [ ] zellij 命令路径不在标准位置，能找到或静默失败

#### 对比测试
- [ ] 同样的会话，对比 tmux 和 zellij 的切换行为
- [ ] 验证 tmux 功能未受影响

### 测试数据

```swift
// Mock 数据用于单元测试
let sampleZellijLayout = """
layout {
    cwd "/Users/test"
    tab name="env" {
        pane cwd="project/env" command="claude"
        pane cwd="project/env"
    }
    tab name="docs" {
        pane cwd="project/docs"
    }
}
"""
```

## 实现计划

### 阶段 1: 核心数据结构和路径查找
- 创建 `MultiplexerType.swift`
- 创建 `ZellijTarget.swift`
- 实现 `ZellijPathFinder.swift`

### 阶段 2: 布局解析
- 实现 `ZellijLayoutParser.swift`
- 编写单元测试验证解析逻辑

### 阶段 3: 目标查找
- 实现 `ZellijTargetFinder.swift`
- 集成布局解析和工作目录匹配

### 阶段 4: 控制器实现
- 实现 `ZellijController.swift`
- 实现检测和切换逻辑

### 阶段 5: 路由层
- 实现 `TerminalMultiplexer.swift`
- 集成 tmux 和 zellij 实现

### 阶段 6: 集成和测试
- 编写集成测试
- 执行手动测试清单
- 修复发现的问题

## 风险和缓解措施

### 风险 1: Zellij 布局解析复杂
**风险**: dump-layout 输出格式复杂，嵌套结构解析可能出错
**缓解**:
- 编写充分的单元测试覆盖各种布局情况
- 解析失败时优雅降级，返回 nil
- 详细日志记录解析错误

### 风险 2: Tab 级别切换不够精确
**风险**: 只能切换到 tab，无法精确定位 pane
**缓解**:
- 在最小可行版本中接受这个限制
- 文档中明确说明限制
- 如果 tab 内有多个 pane，用户需要手动切换

### 风险 3: 环境变量检测不可靠
**风险**: 某些情况下环境变量可能不存在
**缓解**:
- 提供进程检测作为后备方案
- 多重检测机制确保可靠性

### 风险 4: 同时运行 tmux 和 zellij
**风险**: 用户可能同时运行两个复用器
**缓解**:
- 定义明确的优先级（环境变量优先）
- 文档中说明检测逻辑
- 确保不会选择错误的复用器

## 未来扩展

### 短期（后续迭代）
- 实现审批功能（批准/拒绝）
- 支持捕获 pane 内容用于文本匹配
- 优化 pane 精确定位（如果 zellij 支持）

### 长期
- 支持更多终端复用器（screen 等）
- 用户可手动选择复用器类型
- 提供更精细的 pane 控制

## 参考资料

### Zellij 文档
- 官方文档: https://zellij.dev/
- GitHub: https://github.com/zellij-org/zellij

### 相关代码
- Tmux 实现: `ClaudeIsland/Services/Tmux/`
- ProcessExecutor: `ClaudeIsland/Services/Shared/ProcessExecutor.swift`

## 附录

### dump-layout 解析伪代码

```swift
func parseLayout(_ text: String) throws -> ZellijLayout {
    var lines = text.split(separator: "\n").makeIterator()
    return try parseLayoutBlock(&lines)
}

func parseLayoutBlock(_ lines: inout Iterator) throws -> ZellijLayout {
    // 解析 layout { ... }
    // 递归解析 tab 和 pane
}

func parseTabBlock(_ lines: inout Iterator) throws -> ZellijTab {
    // 解析 tab name="..." { ... }
    // 提取 tab 名称和索引
    // 递归解析 pane
}

func parsePaneBlock(_ lines: inout Iterator) throws -> ZellijPane {
    // 解析 pane [command="..."] [cwd="..."] { ... }
    // 提取 cwd 和 command
}
```

### 环境变量检测代码

```swift
func detectFromEnvironment() -> MultiplexerType {
    let env = ProcessInfo.processInfo.environment

    if env["ZELLIJ_SESSION_NAME"] != nil {
        return .zellij
    }

    if env["TMUX"] != nil {
        return .tmux
    }

    return .none
}
```

### 进程检测代码

```swift
func detectFromProcess() -> MultiplexerType {
    // 检查 zellij 进程
    if let output = try? ProcessExecutor.shared.runSyncOrNil(
        "/usr/bin/env", arguments: ["ps", "aux"]
    ), output.contains("zellij") {
        return .zellij
    }

    // 检查 tmux 进程
    if let output = try? ProcessExecutor.shared.runSyncOrNil(
        "/usr/bin/env", arguments: ["ps", "aux"]
    ), output.contains("tmux") {
        return .tmux
    }

    return .none
}
```
