# 03 · 网易云歌曲缓存回读后丢失 source

**批次**：第一批 · **日期**：2026-10-14 · **状态**：已完成（含回归测试）

## 问题现象

从搜索页搜到网易云歌曲 → 播放 → 加入歌单/队列 → 杀进程重启 →
从持久化队列恢复后，该歌曲播放失败（无播放地址 / 请求酷狗接口报错）。

## 根因

`Song` 有三个音源：`kugou`（默认）/ `netease` / `local`（`SongSource` 枚举），
播放分支完全依赖它：

- `netease` → 拼网易云外链 URL；
- `kugou` → 用 hash 请求后端 `songUrl` 接口；
- `local` → 直接用 `song.id` 作为文件路径。

但 `Song.toCache()`（写入队列/历史/首页缓存的通用序列化方法）**没有序列化
`source` 字段**，而 `Song.fromCache()` 也没有恢复它 —— 回读时走默认参数
`source = SongSource.kugou`。

于是网易云歌曲缓存回读后被当成酷狗歌曲，用伪造的 `ne_xxx` hash 去请求
酷狗接口，必然失败。

## 改动内容

`lib/models/music_models.dart`：

1. `toCache()` 增加条件序列化（默认 kugou 不写，节省缓存体积且兼容旧缓存）：

   ```dart
   if (source != SongSource.kugou) 'source': source.name,
   ```

2. `fromCache()` 恢复，用 `asNameMap()` 做安全查表，未知值回退 kugou：

   ```dart
   source: SongSource.values.asNameMap()[asString(json['source'])]
       ?? SongSource.kugou,
   ```

## 影响文件

- `lib/models/music_models.dart`
- `test/song_cache_source_test.dart`（新增）

## 验证方式

新增 5 个回归测试（`flutter test` 全绿）：

- 网易云歌曲缓存回读后 `source == netease`；
- 本地音乐回读后 `source == local`；
- 酷狗歌曲不写 `source` 键、回读为 kugou；
- 未知 source 字符串安全回退 kugou（**旧版本已写入的缓存不会崩**）；
- 云盘标记与其它字段一并正确回读。

## 回归风险与注意事项

- **向后兼容**：旧缓存没有 `source` 键 → 回读为 kugou，与旧行为一致；
  但**旧缓存里的网易云歌曲仍可能处于损坏状态**，用户清一次应用数据或
  让旧缓存过期即可恢复。
- 若将来 `SongSource` 新增枚举值，用 `asNameMap()` 无需改动本处代码。