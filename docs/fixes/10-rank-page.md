# 10 · 排行榜（新增功能）

**批次**：第二批（新增功能） · **日期**：2026-10-14 · **状态**：已完成

## 背景

`api.json` 定义的 140+ 接口中，`/rank/list`、`/rank/audio` 一直未接入。
本次补齐排行榜：榜单目录 → 榜单歌曲（分页）→ 播放/加入队列。

## 改动内容

### 1. API 层（`lib/services/music_api.dart`）

```dart
Future<List<RankBoard>> rankList();                       // GET /rank/list
Future<RankSongsPage> rankSongs(String rankId, {page, pageSize});  // GET /rank/audio
```

- `rankList` 解析 `info` 数组，过滤无 id 的条目；
- `rankSongs` 解析 `songlist` → `Song.fromArtistAudio`，返回
  `RankSongsPage(total, songs)`，`total` 用于判断是否还有下一页。

### 2. 模型（`lib/models/music_models.dart`）

- `RankBoard`：`id` / `name` / `classify` / `coverUrl`，带
  `classifyLabel` 把接口的分类码转中文（1 星耀、2 地区、3 特色、
  4 全球、5 曲风）；
- `RankSongsPage`：`total` + `songs`。

解析沿用项目既有的防御性 helper（`asString` / `asInt` / `asMap` /
`asList`），字段缺失不会抛异常。

### 3. 页面（`lib/ui/pages/rank_page.dart`，新增）

- **`RankPage`**：按 `classifyLabel` 分组展示榜单卡片，下拉刷新，
  失败可重试，空态有文案；
- **`RankSongsPage`**：榜单歌曲列表，滚动到底自动分页（`extentAfter < 500`），
  右下「播放全部」浮动按钮，长按可「下一首播放」，当前播放歌曲高亮并
  显示跳动的音波图标；行号 + 封面 + 歌名/歌手的三段式布局，
  样式对齐 `AlbumShopPage`。

### 4. 入口（`lib/ui/pages/search_page.dart`）

搜索页 AppBar `actions` 中新增一个 `Icons.leaderboard_rounded` 图标按钮
（tooltip「排行榜」），点击 push `RankPage`。

## 影响文件

- `lib/services/music_api.dart`
- `lib/models/music_models.dart`
- `lib/ui/pages/rank_page.dart`（新增）
- `lib/ui/pages/search_page.dart`

## 验证方式

- `flutter analyze` 无新增问题。
- 手动验证：搜索页右上角进入排行榜 → 点任一榜单 → 列表加载并可下拉分页 →
  点歌播放 → 「播放全部」从头播。
- ⚠️ 接口可用性取决于后端部署版本，若某榜单返回空属后端数据问题。

## 回归风险与注意事项

- 纯新增页面，未改动任何既有播放逻辑，回归风险低。
- 榜单歌曲用 `Song.fromArtistAudio` 解析（榜单接口结构与歌手歌曲一致），
  与其它列表页的歌曲模型兼容，可正常播放/下载/收藏。
- 后续可扩展方向：榜单分类做成 tab、榜单详情复用 `PlaylistDetailPage`
  （当前为独立实现，便于处理分页与无歌单信息的情况）。