# 12 · 下载进度回调节流

**批次**：第三批 · **日期**：2026-10-14 · **状态**：已完成

## 问题现象

批量下载 / 大文件下载时，界面滚动卡顿，「我的」页面整页刷新发白。

## 根因

`lib/controllers/download_controller.dart` 的 `_transfer()` 把 dio 的
`onProgress` 回调**原样透传**给 UI：

```dart
onProgress: (received, total) {
  _downloads[hash] = entry!.copyWith(progress: progress);
  notifyListeners();     // ← 每 chunk 一次，可达每秒数十次
}
```

dio 在每个数据 chunk 到达时都会触发回调（快网下每秒几十次）。每次回调都
`notifyListeners()`，而 `DownloadController` 的订阅者包括「我的」页整页
`CustomScrollView`（`library_page.dart:278` 的 `AnimatedBuilder.merge`），
导致**整页列表高频重建**。

## 改动内容

加时间节流，限制通知频率为最多每 150ms 一次：

```dart
static const _progressThrottleMs = 150;
...
var lastNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);
onProgress: (received, total) {
  final progress = total > 0 ? received / total : 0.0;
  final entry = _downloads[hash];
  if (entry?.status != DownloadStatus.downloading) return;
  final now = DateTime.now();
  if (now.difference(lastNotifyAt).inMilliseconds < _progressThrottleMs) return;
  lastNotifyAt = now;
  _downloads[hash] = entry!.copyWith(progress: progress);
  notifyListeners();
}
```

**完成/失败时的最终 `notifyListeners()` 不受影响**（在 onProgress 之外），
进度条一定能走到 100%。

## 影响文件

- `lib/controllers/download_controller.dart`

## 验证方式

- `flutter analyze` 无新增问题。
- 手动验证：批量下载时进度条仍平滑更新且最终到 100%，界面卡顿明显减轻。

## 回归风险与注意事项

- 150ms 约合 6~7 次/秒刷新，进度条肉眼依然顺滑；过快网络下进度会以
  跳变形式显示（每 150ms 跳一档），属可接受的取舍。
- 调大节流间隔可进一步省开销，但会降低观感，不建议超过 250ms。