# 11 · 睡眠定时器倒计时不再每秒重建整个 App

**批次**：第三批 · **日期**：2026-10-14 · **状态**：已完成

## 问题现象

开启「定时播放」后，App 在倒计时期间明显发烫/掉帧，切歌、切页面都有
明显延迟，关掉定时器即恢复。

## 根因

`lib/controllers/player_controller.dart` 的睡眠定时器每秒 tick 一次，
每次更新剩余时间后调用 **`notifyListeners()`**：

```dart
sleepTimerRemaining = remaining;
notifyListeners();   // ← 全 app 重建
```

`PlayerController` 是一个全 app 共享的 `ChangeNotifier`，其订阅者包含
`AppShell`、首页、播放页、迷你播放器等。**为一行动态文本，每秒把整棵
widget 树重建一次**。

## 改动内容

### 1. Controller 新增专用通知器

```dart
final ValueNotifier<Duration?> sleepTimerNotifier = ValueNotifier(null);
```

- `setSleepTimer()` 启动时写入初值；
- **每秒 tick 只写 `sleepTimerNotifier.value`，不再调 `notifyListeners()`**；
- `cancelSleepTimer()` / `_executeSleepTimer()` 中置 null；
- `dispose()` 中 `sleepTimerNotifier.dispose()`（防泄漏）。

### 2. UI 改为局部订阅

- `lib/ui/widgets/sleep_timer_sheet.dart` 的 `_ActiveTimerDisplay` 改为
  `AnimatedBuilder(animation: Listenable.merge([player.sleepTimerNotifier,
  player]))`：倒计时每秒只刷新**这一个组件**；合并 `player` 是为了
  「播完歌曲再停止」开关切换等低频状态变化也能重绘。
- `lib/ui/pages/player_page.dart` 操作面板里「定时播放」的副标题改为
  `ValueListenableBuilder`，同样只刷新这一行。

### 3. `SongSheetAction` 支持 Widget 副标题

原 `subtitle` 是 `String?`，无法承载局部刷新的控件。新增字段
`subtitleWidget`（`Widget?`，非空时优先于 `subtitle`），并在三处渲染点
（车机面板 ListTile、底部弹窗 ListTile、网格卡片）都支持。

## 影响文件

- `lib/controllers/player_controller.dart`
- `lib/ui/widgets/sleep_timer_sheet.dart`
- `lib/ui/pages/player_page.dart`
- `lib/ui/widgets/song_action_sheets.dart`

## 验证方式

- `flutter analyze` 无新增问题。
- 手动验证：开启定时播放 → 观察「剩余 mm:ss」仍逐秒变化（说明刷新正常）
  → 同时用 Flutter DevTools 的 rebuild 计数确认每秒重建数大幅下降。

## 回归风险与注意事项

- `isSleepTimerActive` 等 getter 语义不变，仍读 `sleepTimerRemaining` 字段。
- 新增 `SongSheetAction.subtitleWidget` 是**可选参数**，所有既有调用点
  不受影响。
- ⚠️ 以后新增「需要高频刷新的局部 UI」时，请沿用专用 `ValueNotifier`
  模式，不要在高频回调里调 `notifyListeners()`。