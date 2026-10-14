# 18 · 修复封面加载失败 + 正式版无法覆盖 beta 安装 + 删除 beta 分支

**批次**：线上问题修复 · **日期**：2026-10-14 · **状态**：已完成

## 问题现象（用户报告两件）

1. **v3.1.21/22 封面全部加载不了**（显示占位图），v3.1.19 还正常；
2. 手机上装过 beta 包后再装正式版，Android 提示「版本过高/不能降级」，
   正式版装不进去。

## 根因

### 1. 封面：缓存目录从未创建（fix 06 引入的 bug）

`ArtworkCacheService` 把缓存文件写在
`getTemporaryDirectory()/artwork_cache/<sha1>.jpg`，但 `artwork_cache`
这个**子目录从未被 `create`**。向不存在的目录写文件会抛
`FileSystemException`，而 `_fetch` 用 `on Exception` 捕获后返回 null——
于是**每一张封面的下载都在写盘那一步失败**，全部静默降级成占位图。

时间线完全吻合：v3.1.19 还是裸 `Image.network`（正常），
v3.1.21 起换成缓存服务（全挂）。由于失败被吞，日志里只有
`_loading` 永不复位的骨架屏，测试和 analyze 都抓不到。

连带修掉的两处隐患：

- `on Exception` 接不住 `Error`：`MissingPluginException` 这类插件异常
  继承自 `Error` 而非 `Exception`，一旦抛出会让 `fetch()` 的 Future 以
  异常收场，UI 侧 `_load()` 没兜底就会**永远停在骨架屏**。现在服务层
  改为 `catch (_)`，UI 层 `_load()` 也加了 try/catch 双保险。
- 哈希输入用了 `url.codeUnits`：code unit 可能大于 255，超出字节范围，
  对非 ASCII URL 会产生歧义哈希；改为 `utf8.encode(url)`。

### 2. 版本码：beta 段位高于正式段位

正式流水线 `VERSION_CODE_BASE=1000000`，beta 曾用 `2000000+run` 发包。
两者**共用同一个 applicationId（com.reiko.app）**，所以装过 beta
（versionCode 2000004）的设备再装正式版（1000022）会被 Android 判定为
降级、拒绝安装。

修复：正式流水线基数 **1000000 → 2000000**。下一次正式包
（2000000+run ≥ 2000023）高于任何 beta 包，可直接覆盖安装；对从未装过
beta 的用户无任何影响（只是版本码数字变大了，比较逻辑不变）。

> beta 分支已按用户要求删除，此注释保留在 workflow 里作为历史依据。

## 改动内容

| 文件 | 改动 |
|------|------|
| `lib/services/artwork_cache_service.dart` | `_cacheDir` 拆出 `_ensureCacheDir()`，**首次使用时 `create(recursive: true)`**；`on Exception` → `catch (_)`；哈希输入改 `utf8.encode`；`_enforceDiskLimit` 的排序从「按文件大小（注释却写按时间）」修正为真正的按 mtime 最旧优先 |
| `lib/ui/widgets/artwork.dart` | `_CachedNetworkImage._load()` 加 try/catch，保证 `_loading` 任何情况下都会复位（骨架屏不会永久卡住） |
| `.github/workflows/android-build.yml` | `VERSION_CODE_BASE` 1000000 → 2000000，注释说明原因 |
| `.github/workflows/android-build-beta.yml` | **从 master 删除**（beta 分支整体下线） |
| `test/artwork_cache_dir_test.dart` | 新增：把「向不存在目录写文件会抛异常 / create 后成功」的平台行为固化成回归测试 |

远端操作：删除 `beta` 分支、删除全部 beta 前缀的 GitHub prerelease 与 tag
（`beta-v3.1.*`）。R2 上的 `beta/latest.json` 与 `beta/releases/` 残留
（本机无 R2 凭据，未清理；无人再引用，无害）。

## 影响文件

见上表 + 本文档与 `docs/工作日志.md`。

## 验证方式

```bash
flutter analyze                    # 4 条既有告警，零新增
flutter test                       # 37 -> 39 全部通过
```

真机/产物验证（CI 构建完成后）：

1. `latest.json` 的 versionCode ≥ 2000023（高于 beta 的 2000004）；
2. APK 内字符串检索确认「浩渺声场」「悦耳人声」存在；
3. 安装到之前装过 beta 的设备，应能直接覆盖安装；
4. 首页/搜索/播放页封面恢复正常（占位图 → 真实封面）。

## 回归风险与注意事项

1. **两批用户、两条升级路径**：
   - 装过 beta 的设备 → 装 v3.1.23+ 直接覆盖（版本码已抬高）；
   - 装着 v3.1.21/22 的设备 → versionCode 2000023 > 1000022，正常升级。
2. 封面缓存修复后，**老用户已积累的占位图状态会自动恢复**（缓存目录
   首次写入时创建，无需清数据）。
3. `_enforceDiskLimit` 现在真的按 mtime 淘汰，行为与注释一致；触发条件
   仍是 >200MB，普通用户感知不到。
4. 教训记录：**「下载成功 ≠ 落盘成功」**。缓存服务引入了第二个失败点
   （文件系统），而吞异常策略把它藏住了。今后凡是新加磁盘缓存，
   必须先验证目录创建路径，或在测试里覆盖一次完整写入。
