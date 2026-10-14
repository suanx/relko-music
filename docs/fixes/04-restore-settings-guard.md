# 04 · 设置恢复失败导致启动永久挂起

**批次**：第一批 · **日期**：2026-10-14 · **状态**：已完成

## 问题现象

极少数用户（prefs 数据异常、JSON 内容被截断等）打开 App 后卡在启动页，
永远不进入主界面，只能杀进程。

## 根因

`lib/controllers/player_controller.dart` 的 `_restoreSettings()` 读取
SharedPreferences 恢复播放器设置，末尾执行：

```dart
if (!_settingsRestored.isCompleted) {
  _settingsRestored.complete();
}
```

但该方法**整体没有 try/catch**。而 `main.dart` 的启动流程存在
`await player.settingsRestored` 之类的等待方：一旦恢复过程中抛异常
（prefs 读取异常、类型转换失败等），`_settingsRestored` 这个 Completer
**永远不会 complete**，等待它的启动流程就永久挂起。

## 改动内容

把 `_restoreSettings` 拆成「安全外壳 + 原实现」两层：

```dart
Future<void> _restoreSettings() async {
  try {
    await _restoreSettingsUnsafe();   // 原有逻辑整体移入
  } catch (e, s) {
    debugPrint('恢复播放器设置失败（使用默认值启动）: $e\n$s');
  } finally {
    if (!_settingsRestored.isCompleted) {
      _settingsRestored.complete();   // 无论如何都放行等待方
    }
  }
}
```

关键点：**`complete()` 放在 `finally`**，保证任何异常路径下启动流程都能继续。

## 影响文件

- `lib/controllers/player_controller.dart`

## 验证方式

- `flutter analyze` 无新增问题。
- 建议手动验证：写入一个非法类型的 prefs 值（如把 bool 键写成字符串），
  冷启动应正常进入主界面（该项设置回落到默认值），日志中打印失败原因。

## 回归风险与注意事项

- 行为变化仅在「原本会崩溃/挂起」的异常路径上；正常路径完全不变。
- 失败时使用**各字段默认值**启动，用户可在设置页重新调整，不会丢数据
  （prefs 中的原始数据不被清除）。