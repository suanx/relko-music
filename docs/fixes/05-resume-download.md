# 05 · 断点续传进度可能超过 100% 且文件损坏

**批次**：第一批 · **日期**：2026-10-14 · **状态**：已完成

## 问题现象

下载大文件中断后重试（断点续传），可能出现：

- 进度条超过 100%（如 137%），到顶后卡住不再变化；
- 最终文件大小异常，播放时解码失败。

## 根因

`lib/services/download_service.dart` 的 `_executeTask()` 原来用
`dio.download()` 写 `.part` 文件，进度换算为：

```dart
onReceiveProgress: (received, total) {
  final actualTotal = startOffset + total;      // ← 问题在这里
  final actualReceived = startOffset + received;
  task.onProgress?.call(actualReceived, actualTotal);
}
```

两个缺陷：

1. **服务器忽略 Range 头时**返回 `200` + 全量内容（而非 `206` 分段），
   此时 `total` 已是完整文件大小，再加 `startOffset` 就超了 —— 进度
   必然 >100%，且 `total` 恒定不变导致进度卡住。
2. `dio.download` 在这种情况下会**覆盖** `.part` 文件写入全量内容，
   续传语义失效；旧分片与新内容混合时文件直接损坏。

## 改动内容

改为**手动流式下载**，以便拿到响应状态码做分支判断：

1. 用 `_dio.get(url, options: Options(responseType: ResponseType.stream,
   validateStatus: 允许 200/206))` 发起请求；
2. `response.statusCode == 206` 才算真正续传；否则（200）**清空 .part
   并把 `startOffset` 归零**从头写；
3. 总大小优先取响应头 `Content-Length`（未续传时直接用它，续传时
   `startOffset + Content-Length`），取不到则为 `-1`；
4. 用 `partFile.openWrite(mode: FileMode.append)` 边收边写、累计进度。

## 影响文件

- `lib/services/download_service.dart`

## 验证方式

- `flutter analyze` 无新增问题。
- 手动验证：下载大文件 → 中断 → 重试，观察进度不超过 100%，且完成后
  文件可正常播放。
- 服务器是否支持 Range 取决于 CDN；不支持时应看到「从头重下」而不是
  文件损坏。

## 回归风险与注意事项

- ⚠️ `onProgress` 的 `total` 现在**可能为 -1**（服务端未返回
  Content-Length 时）。调用方 `DownloadController._transfer` 已有
  `total > 0 ? received / total : 0.0` 的保护，但**新增调用方必须自行处理**。
- 取消下载仍走原 `CancelToken`，流式读取会在 cancel 后抛异常，语义不变。