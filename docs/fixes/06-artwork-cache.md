# 06 · 封面图片磁盘缓存 + 解码降采样

**批次**：第一批 · **日期**：2026-10-14 · **状态**：已完成（新增依赖 crypto）

## 问题现象

- 列表快速滚动时封面反复出现加载占位（Shimmer），上下滑动能看到图片重新加载；
- 冷启动后所有封面重新下载一遍；
- 长列表滚动掉帧、内存占用高。

## 根因

全项目封面统一走 `lib/ui/widgets/artwork.dart` 的裸 `Image.network`：

- **无磁盘缓存**：Flutter 只提供**内存** `ImageCache`，冷启动后缓存为空，
  同一张封面会重新下载；
- **无解码降采样**：网络原图多为 480~1000px，而列表里的封面只有
  44~58px，仍按原图尺寸解码，浪费内存和 GPU；
- 同一 URL 在多处重复请求（首页、我的、搜索、歌单详情…）。

## 改动内容

### 1. 新增 `lib/services/artwork_cache_service.dart`

轻量磁盘缓存（临时目录 `artwork_cache/`）：

- 文件名 = `sha1(url)`，命中直接读盘，不再走网络；
- **in-flight 去重**：同一 URL 并发请求合并为一个 Future；
- 先写 `.tmp` 再 rename，避免中断留下半截文件被误判为缓存命中；
- 容量上限 **200MB**，超出时按文件从小到大淘汰；
- 下载超时 15s，失败静默返回 null（降级为占位图，不影响其它封面）。

### 2. `artwork.dart` 改为两段式

- `Artwork.build` 中网络图片分支改用新的 `_CachedNetworkImage`（Stateful，
  `didUpdateWidget` 里 url 变化会重新加载，避免列表复用导致封面错位）；
- `_decodeSize`：按 `size * 3` 夹到 [64, 1024] 并**向上取 2 的幂**，
  传给 `Image.file(cacheWidth/cacheHeight:)`，走更优的解码路径。

### 3. 为什么没直接用 `cached_network_image`

原计划引入该包，但其默认缓存实现依赖 **sqflite**，在 Windows 桌面端
（本项目真实支持音频播放的平台）运行时存在崩溃风险。自研的临时目录方案
零平台风险，且**只新增 `crypto` 一个轻量依赖**（此前仅为传递依赖，
本次显式声明）。

## 影响文件

- `pubspec.yaml`（新增 `crypto: ^3.0.3`）
- `lib/services/artwork_cache_service.dart`（新增）
- `lib/ui/widgets/artwork.dart`

## 验证方式

- `flutter pub get` 通过；`flutter analyze` 无新增问题。
- 手动验证：进首页 → 反复上下滚动列表（应无重复 Shimmer）→ 杀进程
  冷启动（封面应秒出，走本地缓存）。可清 `临时目录/artwork_cache`
  验证回退到网络下载。

## 回归风险与注意事项

- 缓存写在**系统临时目录**，系统清理临时文件后会自动失效，属预期行为。
- 磁盘占用上限 200MB，淘汰策略是「小文件优先」，不是严格 LRU（复杂度换收益）。
- 若将来接入 `cached_network_image`，应替换本服务而不是叠加使用。