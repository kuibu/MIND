# ios-capture

这部分已经有真实的 SwiftUI app target 源码，入口在：

- [MINDiOSCaptureApp.swift](/Users/a/repos/MIND/apps/ios-capture/Sources/MINDiOSCaptureApp.swift)

工程生成方式：

```bash
xcodegen generate
open MINDApps.xcodeproj
```

目标 scheme：

- `MINDiOSCapture`

当前实现范围：

- 使用 SwiftUI 展示局域网发现、配对、采集预设、开始/结束推流的核心流程
- 使用 `NWBrowser` 发现同一局域网中的 `MIND Mac Ingest` 节点
- 使用 `NWConnection` 把关键帧消息实时发往 Mac
- 在 simulator 下按 `CaptureIntentPreset` 生成结构化 demo frame hint，便于验证 canonical commit
- 在设备上通过 `ReplayKit` 采集当前 App 的屏幕帧并按 1fps 节流发送
- 通过共享 `App Group` 把采集预设和配对结果同步给 `Broadcast Upload Extension`

当前还没有接入：

- 更稳的重传 / chunk ack 协议
- 真正的极小 ring buffer 落盘与崩溃恢复
- 更细的配对信任模型和二维码配对

应继续复用共享模块中的：

- `MINDProtocol`
- `MINDAppSupport`
- `MINDServices` 中与 session metadata、stream state、discovery state 相关的抽象

不应在 iPhone 端重复实现：

- canonical schema
- 多模态关键帧解析
- 权限分类主逻辑
- task pipeline

运行注意：

- 设备运行需要允许本地网络访问
- 当前 `Info.plist` 已包含 `NSLocalNetworkUsageDescription` 与 `NSBonjourServices`
- 如果需要系统级录屏，要从 App 内调起 `Broadcast Upload Extension`
