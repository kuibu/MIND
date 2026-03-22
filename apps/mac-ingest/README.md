# mac-ingest

这部分暂时只保留产品与工程边界，不直接落 Xcode 工程。

第一版职责：

- 接收 iPhone 的实时录屏 chunk
- 管理 session 生命周期
- 做关键帧抽样、OCR、视觉模型抽取、session merge
- 将结果写入 canonical store、evidence store 与索引层

后续接入时，优先复用共享模块中的：

- `MINDProtocol`
- `MINDSchemas`
- `MINDRecipes`
- `MINDServices`
- `MINDPipelines`

不应在 Mac App target 里直接写死：

- 平台 schema
- task pipeline 业务逻辑
- 资源权限模型
