# ios-broadcast-upload

这部分是 iPhone 端的 `Broadcast Upload Extension`，入口在：

- [SampleHandler.swift](/Users/a/repos/MIND/apps/ios-broadcast-upload/Sources/SampleHandler.swift)

当前实现范围：

- 通过共享 `App Group` 读取主 App 里保存的采集预设和已配对 Mac relay
- 使用 `RPBroadcastSampleHandler` 接收系统级录屏视频帧
- 按约 1fps 节流，把 JPEG 关键帧通过 `NWConnection` 发到 Mac ingest 节点
- 在广播开始和结束时发送 `startSession` / `stopSession` 控制消息

当前还没有接入：

- 音频样本上传
- chunk ack / 重传
- 断线后的自动恢复与补传
- 更细的 extension 侧错误可视化

依赖条件：

- 主 App 和 extension 共享同一个 `App Group`
- 已在主 App 内完成局域网发现和 Mac 配对
- 设备侧允许本地网络访问
