# mac-ingest

这部分已经有真实的 SwiftUI app target 源码，入口在：

- [MINDMacIngestApp.swift](/Users/a/repos/MIND/apps/mac-ingest/Sources/MINDMacIngestApp.swift)

工程生成方式：

```bash
xcodegen generate
open MINDApps.xcodeproj
```

目标 scheme：

- `MINDMacIngest`

当前实现范围：

- 用 SwiftUI 展示 Mac 作为 ingest node 的主界面
- 通过 Bonjour + `NWListener` 作为局域网 ingest node 接收来自 iPhone 的关键帧消息
- 把收到的 keyframe 落到本地热数据目录
- 通过 `LiveIngestCoordinator` 把消息送入 recipe 选择、MiniCPM bridge 抽取、session merge、canonical commit
- 展示 session、最近抽取、GUI recipes 和 3 条 task pipeline 的实时结果
- 把 canonical resources 持久化到本地 JSON snapshot store

当前已经验证：

- `xcodebuild -project MINDApps.xcodeproj -scheme MINDMacIngest CODE_SIGNING_ALLOWED=NO build`

当前还没有接入：

- WebRTC / QUIC 等更强韧的传输层
- OCR / ASR 独立服务化
- evidence / hot-data 清理策略
- 会话回放与人工校正台

应继续复用共享模块中的：

- `MINDProtocol`
- `MINDAppSupport`
- `MINDSchemas`
- `MINDRecipes`
- `MINDServices`
- `MINDPipelines`

不应在 Mac App target 里直接写死：

- 平台 schema
- task pipeline 业务逻辑
- 资源权限模型
- MiniCPM 配方定义
