# 09 · 队列管理 UI（删除 / 拖拽排序）

**批次**：第二批 · **日期**：2026-10-14 · **状态**：已完成

## 问题背景

原播放页的队列面板（`_showQueue`）是 `ListView.builder` + ListTile，
**只能查看和点击切歌**，无法删除或调整顺序。「下一首播放」功能本来
就存在（各页面长按菜单 → `player.addToQueue(song)`，其内部语义就是把歌曲
插到当前歌曲之后），因此本次**不再重复增加该入口**。

## 改动内容

### 1. Controller 新增两个方法（`lib/controllers/player_controller.dart`）

- `removeFromQueue(int index)`：按下标移除；**当前播放歌曲不可移除**
  （`index == currentIndex` 时直接返回），避免与切歌逻辑打架；
- `reorderQueue(int oldIndex, int newIndex)`：remove + insert 实现移动，
  越界或同位置时安全返回。

两者都会同步 `_audioHandler.setSongQueue(...)`、持久化队列状态并
`notifyListeners()`。

### 2. UI 改造（`lib/ui/pages/player_page.dart` 的 `_showQueue`）

- `ListView.builder` → **`ReorderableListView.builder`**（每个 item 必须有
  key，这里用 `ValueKey('${song.hash}_$index')`）；
- 非当前播放歌曲的 `trailing` 增加：
  - 「×」按钮 → `player.removeFromQueue(index)`；
  - 拖拽手柄 `ReorderableDragStartListener`；
- 当前播放歌曲的 `trailing` 为 `null`（不提供删除/拖拽）；
- 队列为空时显示「播放队列为空」占位文案；
- 加 `proxyDecorator` 给拖拽中的条目加阴影与圆角。

### 3. 使用新版回调 `onReorderItem`

Flutter 3.41 起 `onReorder` 被弃用，改用 `onReorderItem` —— 它会自动
校正「移除旧位置后」的 `newIndex`，与本实现 remove+insert 语义一致。

## 影响文件

- `lib/controllers/player_controller.dart`
- `lib/ui/pages/player_page.dart`

## 验证方式

- `flutter analyze` 无新增问题。
- 手动验证：打开播放页队列 → 拖拽调整顺序 → 关闭重开（顺序应持久化）；
  删除某首 → 队列刷新；点击当前播放歌曲 → 无删除按钮且无法拖动。

## 回归风险与注意事项

- 拖拽排序会改变 `currentIndex` 的含义，但 `currentIndex` getter 是按
  `identical()` 在队列里找当前歌曲的（不是记索引），因此排序后仍指向
  正确的歌。
- 车机模式的队列面板在 `car_left_player_panel.dart` 中，本次**未**改动，
  仍为只读 + 清空队列。