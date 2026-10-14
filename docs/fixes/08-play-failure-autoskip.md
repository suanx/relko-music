# 08 · 播放失败自动重试 / 自动跳下一首

**批次**：第二批 · **日期**：2026-10-14 · **状态**：已完成

## 问题现象

队列里某首歌无播放地址（云盘过期、VIP 失效、网络中断）时，播放直接
停下并显示错误，用户必须手动点「下一首」。连续几首失效时体验很差。

## 根因

`lib/controllers/player_controller.dart` 的 `playSong()` 在 catch 分支
只做了两件事：设置 `errorMessage`、结束 loading，**没有任何后续处理**。
原有唯一的容错是「智能音质降级」（仅作用于 `songUrl` 接口解析阶段），
**不覆盖**解码失败、404、播放中断等情况。

## 改动内容

1. 新增连续失败计数与上限：

   ```dart
   int _consecutiveFailures = 0;
   static const _maxAutoSkipFailures = 3;
   ```

2. `playSong()` 成功后（`_audioHandler.play()` 之后）计数归零；
3. catch 分支中计数 +1，若未达上限且队列中还有下一首 → 延迟 600ms
   自动调用 `next()`：

   ```dart
   final canSkip = _consecutiveFailures < _maxAutoSkipFailures &&
       (_nextSong() != null);
   if (canSkip) {
     unawaited(Future<void>.delayed(const Duration(milliseconds: 600),
         () => next()));
   }
   ```

## 影响文件

- `lib/controllers/player_controller.dart`

## 验证方式

- `flutter analyze` 无新增问题（`return _api.songUrl(...)` 那处
  `unawaited_return_in_try_block` 警告为改动前既有，见 `工作日志.md`）。
- 手动验证：构造一个失效歌曲（如清空其播放地址的云盘歌曲）置于队首，
  应自动跳到下一首；连续 3 首失败后停止并显示错误。

## 回归风险与注意事项

- ⚠️ 上限 3 次是**连续**计数：任意一首播放成功即归零，所以「隔一首歌失败
  一次」的场景可以无限自动跳过，属预期。
- 600ms 延迟是为了让 errorMessage 有短暂展示时间，避免用户看到界面闪一下
  就换歌。若嫌慢可调小。
- 私人 FM 模式下 `_nextSong()` 走 FM 续批逻辑，自动跳过同样生效。