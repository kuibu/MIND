# MIND 编码子步骤提示词

> 基于 [task-driven-architecture.md](./task-driven-architecture.md) 的第一轮 Codex 实施提示词

这些提示词不是“讨论题”，而是可以直接交给 Codex 连续执行的实现任务。顺序按依赖关系安排，前一步产出的结构会被后一步复用。

## Step 1: 初始化可编译仓库骨架

**提示词**

```text
根据 docs/task-driven-architecture.md，把仓库初始化成一个可编译的 Swift Package。目标是为 iPhone + Mac 的 MIND 第一版建立核心模块骨架，而不是直接开发完整 UI。请创建共享模块，至少包括：
- MINDProtocol
- MINDSchemas
- MINDRecipes
- MINDServices
- MINDPipelines

要求：
1. 用 Swift Package Manager 管理。
2. 平台至少声明 macOS 和 iOS。
3. 模块职责要和文档里的四层架构一致。
4. 代码先偏“核心内核”，不要先做具体 UI。
5. 提交后要能跑 swift test。
```

**完成标准**

- 有 `Package.swift`
- 有共享模块和基础测试目标
- 目录结构开始接近文档中的代码框架

## Step 2: 实现 session / observation / canonical schema

**提示词**

```text
在 Swift Package 中实现 MIND 的第一批核心数据类型，覆盖：
- 实时录屏 session 与 chunk 元数据
- keyframe 与 frame context
- OCR / UI Text / UI Event / UI Object / File Reference observation
- GUI recipe 定义
- canonical resources: Identity, Conversation, Message, Attachment, FileAsset, Expense, Merchant, Order, Trip, ContentItem, CollectionEvent, MetricSnapshot, EvidenceRef, PermissionPolicy

要求：
1. 这些类型必须能表达 docs/task-driven-architecture.md 里的三条任务链路。
2. 先做稳定 schema，不要夹杂过多业务逻辑。
3. 模型要可测试、可序列化、可跨模块复用。
```

**完成标准**

- `MINDProtocol` 与 `MINDSchemas` 可独立被 import
- 任务 A/B/C 所需的数据字段都有明确位置

## Step 3: 实现 MiniCPM 导向的感知服务边界

**提示词**

```text
围绕“Mac 本地跑 MiniCPM-o 4.5，iPhone 只做轻量采集”的前提，实现第一版感知层抽象。请提供：
- SessionChunkBuffer
- FrameSampler
- VisionExtractor 协议
- StubVisionExtractor 或 Mock 实现
- SessionMerger
- RecipeRegistry

要求：
1. 明确 adapter、extractor service、recipe 的边界。
2. VisionExtractor 不要写死在某个平台里，要做成共享感知内核。
3. SessionMerger 要能把多帧 observation 合并成更稳定的结果。
4. 先做 stub / mock，给后续接 MiniCPM 留出协议边界。
```

**完成标准**

- 服务层能围绕 recipe 跑通一轮“关键帧 -> observation -> 合并”数据流
- 还没有真实模型也能被测试

## Step 4: 实现任务导向 pipeline

**提示词**

```text
根据 docs/task-driven-architecture.md 里的三个 Agent 任务，实现三条可测试的 pipeline：
1. WeeklyExpenseSummaryPipeline
2. AttachmentSearchPipeline
3. SavedVideoTimelinePipeline

要求：
1. Pipeline 输出面向任务，不要只返回底层 raw records。
2. Expense pipeline 要有 rule-based 的分类器，至少支持 差旅 / 餐饮 / 其他。
3. Attachment pipeline 要体现“文件依赖会话上下文”的设计。
4. Collection pipeline 必须返回“收藏当时的点赞数”，而不是当前值。
```

**完成标准**

- 三条 pipeline 都有明确输入输出
- 结果类型适合直接给 Agent 或 API 层使用

## Step 5: 写测试，固定住第一版系统行为

**提示词**

```text
为三个 pipeline 和关键 service 写基础测试，使用最小但真实感强的 fixture：
- 支付宝 / 美团 / 滴滴消费
- 微信好友陈攀会话里的 PDF 附件
- 抖音 / 小红书收藏视频及收藏时点赞数

要求：
1. 测试必须覆盖三个用户任务的核心判断。
2. 测试要验证排序、分类、关联关系和时间点快照。
3. 所有测试都要通过 swift test。
```

**完成标准**

- 仓库不再只有文档
- 已有一套可回归的核心行为测试

## Step 6: 为 iPhone 与 Mac App 留出接入位

**提示词**

```text
在仓库中新增 apps/ios-capture 和 apps/mac-ingest 的占位结构与 README，说明这两个客户端未来如何对接共享模块，尤其说明：
- iPhone 端负责什么
- Mac 端负责什么
- 哪些逻辑必须留在共享核心模块
- 哪些逻辑以后再放到 Xcode App target 中
```

**完成标准**

- 仓库层面已经承认双端结构
- 未来接 UI/App 时不会推翻核心模块
