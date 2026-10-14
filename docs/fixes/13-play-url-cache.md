# 13 · 播放地址短期缓存

**批次**：第三批 · **日期**：2026-10-14 · **状态**：已完成

## 问题现象

「上一首 / 下一首」来回切歌、或单曲外重播同一首歌时，每首歌都要重新
请求一次播放地址接口，切歌有明显等待；弱网时尤其明显。

## 根因

`lib/controllers/player_controller.dart` 的 `_resolvePlayUrl()` 每次都调用
`_api.songUrl()` 走网络，**没有任何缓存**。而用户的典型操作（前后切歌、
循环播放、重播）会反复请求同一首歌的同一音质地址。

## 改动内容

在 Controller 内加一层**短期内存缓存**：

```dart
final Map<String, _CachedPlayUrl> _playUrlCache = {};
static const _playUrlCacheTtl = Duration(minutes: 5);
static const _playUrlCacheMaxEntries = 50;
```

- **key** = `"{hash}_{音质}"`，音质不同分开缓存；
- **TTL 5 分钟**：命中且未过期直接返回 `PlayUrl`；
- 容量上限 50 条，超出时淘汰最早写入的条目（简单 LRU）；
- 写入点：正常解析成功后写入；**智能音质降级成功后，按降级音质写入**
  （避免下次又请求高音质再失败一遍）。

## 影响文件

- `lib/controllers/player_controller.dart`

## 验证方式

- `flutter analyze` 无新增问题。
- 手动验证：播放一首歌 → 切走 → 切回（应几乎无等待）；开弱网模式时
  观察日志/网络面板，请求次数明显减少。

## 回归风险与注意事项

- ⚠️ **TTL 是安全边界**：播放地址通常带鉴权参数、有效期远大于 5 分钟；
  若后端存在更短的有效期（分钟级），需**调小 TTL**，否则会出现地址过期
  导致的播放失败。此时的表现是播放失败自动跳歌（见 `08`），不会卡死。
- 缓存只在内存中，应用重启后清空，无磁盘残留。
- 队列恢复流程走 `prepareRestoredSong()` → `_resolvePlayUrl()`，同样受益。