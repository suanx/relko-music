# 15 · 包名改为 com.reiko.app + 新增 beta 分支与独立发布通道

**批次**：发布/分支 · **日期**：2026-10-14 · **状态**：已完成（构建结果待 CI 验证）

## 问题现象

正式包 `applicationId` 为 `com.hoilai.mm.music`（外包项目遗留命名）。
用户要求换成自有包名 `com.reiko.app`，并新增一条 beta 分支用于出测试包。

## 根因 / 约束

包名不是改一行 Gradle 就完事，它同时是 **Kotlin 源码的包声明、源码目录
路径、自定义 View 的 XML 全限定名、广播 action 前缀**。只改
`applicationId` 会导致：
- `namespace` 不变时 Kotlin 仍在旧包下，Manifest 里 `.MainActivity`
  解析到旧包 → 运行时 `ClassNotFoundException`；
- `overlay_lyrics.xml` 里的 `com.hoilai.mm.music.KaraokeTextView`
   inflating 失败；
- 歌词悬浮窗的内部广播 action 前缀仍是旧包名（不影响功能，但与包名不自洽）。

另外**包名变更等于换了一个新应用**：Android 依据 applicationId 区分应用，
新包无法覆盖安装旧包，也无法被旧包覆盖升级。这是刻意的——beta 应该与
正式版并存，而不是替换掉正式版。

## 改动内容

### 1. 包名迁移（旧包 → `com.reiko.app`）

| 文件 | 改动 |
|------|------|
| `android/app/build.gradle.kts` | `namespace` 与 `applicationId` 同时改为 `com.reiko.app` |
| `android/app/src/main/kotlin/com/hoilai/mm/music/` → `.../kotlin/com/reiko/app/` | 3 个 Kotlin 文件 `git mv` 到新目录，`package` 声明同步改写 |
| `android/app/src/main/kotlin/com/reiko/app/LyricsOverlayService.kt` | 7 个内部广播 action 常量 + 1 处 `Intent("...")` 前缀改为 `com.reiko.app.*` |
| `android/app/src/main/res/layout/overlay_lyrics.xml` | 自定义 View 全限定名 `com.reiko.app.KaraokeTextView` |
| `linux/CMakeLists.txt` | `set(APPLICATION_ID "com.reiko.app")` |

`AndroidManifest.xml` **无需改动**：其中 `.MainActivity` /
`.LyricsOverlayService` 是相对 `namespace` 解析的，`${applicationId}.fileprovider`
是构建期占位符，会自动跟随。

保留未改：`music.api.hoilai.cn` 等 **API 域名**与应用标识无关。

### 2. beta 分支与独立发布通道

新增 `.github/workflows/android-build-beta.yml`，只在 push 到 `beta` 分支时
触发，且与正式流水线**全隔离**：

| 维度 | 正式（android-build.yml） | beta（android-build-beta.yml） |
|------|--------------------------|------------------------------|
| 触发分支 | master / main | beta |
| 版本码基数 | 1000000 + run | **2000000** + run |
| 版本号 | 3.1.N | 3.1.N**-beta** |
| R2 清单 | `latest.json` | **`beta/latest.json`** |
| R2 安装包 | `releases/` | `beta/releases/` |
| GitHub Release | 普通 release，tag `v3.1.N` | **prerelease**，tag `beta-v3.1.N-beta` |
| 并发组 | android-release | android-beta-release |

**为什么必须隔离**：beta 包与正式包 applicationId 不同。若 beta 构建覆盖了
根目录 `latest.json`，正式用户点「检查更新」会拿到 beta 包——
`versionCode`（2000000+）大于正式包（1000000+）所以一定被判定为「新版本」，
但 Android 会因包名不同拒绝安装，更新功能对**所有正式用户**直接失效。
反向亦然：beta 应用自身的 versionCode 恒大于正式版本，即便回退到
GitHub Releases 也不会把正式包当成升级。

## 影响文件

- `android/app/build.gradle.kts`
- `android/app/src/main/kotlin/com/reiko/app/{MainActivity,KaraokeTextView,LyricsOverlayService}.kt`（含目录移动）
- `android/app/src/main/res/layout/overlay_lyrics.xml`
- `linux/CMakeLists.txt`
- `.github/workflows/android-build-beta.yml`（新增）

## 验证方式

```bash
# 包名残留自检（只应命中 API 域名，不应有 mm.music）
grep -rIn "hoilai\.mm" --exclude-dir=build --exclude-dir=.git .

# 包名与 Kotlin 声明一致性
grep -n "applicationId\|namespace" android/app/build.gradle.kts
head -1 android/app/src/main/kotlin/com/reiko/app/*.kt
```

- 已确认全仓库无 `hoilai.mm` 残留；3 个 Kotlin 文件声明与目录一致。
- **本机无 Java/Android SDK，无法本地编译**，构建正确性由 CI 首次
  beta 构建验证（见「回归风险」）。

## 回归风险与注意事项

1. **beta 首次构建是唯一一次编译验证**。若遗漏引用，编译期会直接报错
   （AGP 的 R 类/资源引用在编译期即失败），不会带到线上；首次 CI 失败请查看
   错误日志定位。
2. **CI 需要先配好 4 个签名 Secret**（见 `fixes/14-signing-secret-untrack.md`）。
   未配置时 beta 流水线会在签名步骤 fail-fast 退出，属预期行为。
3. beta 与正式共用**同一个 keystore**。二者包名不同，可互相覆盖升级的
   风险不存在；将来若要「beta 灰度覆盖正式」则必须换包名，不可混用。
4. beta 应用内「检查更新」指向 `https://dl.suen.us.ci/beta/latest.json`
   （构建时 dart-define 注入），正式应用不受影响。
5. 若要回滚：删除远端 `beta` 分支即可，正式流水线完全不受影响
   （beta 不在 `master`/`main` 历史上）。