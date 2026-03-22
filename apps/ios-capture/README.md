# ios-capture

这部分暂时只保留产品与工程边界，不直接落 Xcode 工程。

第一版职责：

- 使用 iOS 录屏能力采集屏幕流
- 发现同局域网内已配对的 Mac 端
- 把实时 chunk 发送到 `mac-ingest`
- 在本地只保留极小重传缓冲

后续接入时，优先复用共享模块中的：

- `MINDProtocol`
- `MINDServices` 中的 session metadata 定义

不应在 iPhone 端重复实现：

- canonical schema
- 多模态关键帧解析
- 权限分类主逻辑
