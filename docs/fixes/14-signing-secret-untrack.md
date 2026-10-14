# 14 · 签名密钥与口令移出仓库

**批次**：安全专项 · **日期**：2026-10-14 · **状态**：已完成（历史清理待用户决策）

## 问题现象

`relko-release.keystore`（release 签名私钥）自 2026-09-29 起被 git 跟踪并
提交到远端仓库（`suanx/relko-music`）。更严重的是，keystore 的**口令与别名
以明文写在已提交的 CI workflow 里**。

## 根因

`.gitignore` 里其实**早已**有 `*.keystore` 与 `key.properties` 规则，
`build.gradle.kts` 也早已改用 `android/key.properties` 读取签名。但：

1. keystore 在加入 ignore 规则**之前**就已被 `git add`，
   而 **.gitignore 对已跟踪文件无效** → 规则形同虚设；
2. CI 的「Write signing config」步骤直接 `cat` 出含明文口令的
   key.properties，口令与别名随 workflow 一并入库
   （值仅存于 git 历史，本文**刻意不复述**，避免二次泄露）；
3. 于是「本地不入库」做了，「CI 不入库」漏了——**口令比密钥本身更致命**，
   因为有口令就能用密钥给任意 APK 签名。

## 改动内容

### 1. 加密备份到仓库外（动手前先做）

先备份再删，避免丢失签名能力（丢了就无法覆盖安装已发布的正式版）：

| 文件 | 位置 | 加密方式 |
|------|------|----------|
| keystore | `%USERPROFILE%\.relko-secrets\relko-release.keystore.dpapi` | DPAPI（CurrentUser） |
| storePassword | 同目录 `storePassword.txt` | DPAPI SecureString |
| keyAlias | 同目录 `keyAlias.txt` | DPAPI SecureString |

DPAPI 以 **CurrentUser 作用域**加密：备份文件即使被拷到其它机器或账户，
也**无法解密**。已验证解密结果与原 keystore 的 SHA256 完全一致。

### 2. 取消 git 跟踪 + 强化 ignore

- `git rm --cached relko-release.keystore`（保留本地文件供构建）；
- `.gitignore` 追加显式规则 `relko-release.keystore` 与
  `android/key.properties`（`*.keystore` 只挡后缀，改名即失效）。

验证：`git ls-files | grep -E "keystore|key.properties"` → 无输出。

### 3. CI 改用 GitHub Secrets

`.github/workflows/android-build.yml` 的签名步骤改为读 4 个 Repository
Secrets（GitHub 对 secret 静态加密、界面不回显、不进 git 历史）：

- `ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` /
  `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`

CI 内 base64 解码出 keystore（工作目录临时文件，任务结束即销毁），
写出 key.properties；**任一 secret 缺失即 `exit 1`**，不会再静默产出
debug 签名的包推到 R2。

### 4. 新增 `tooling/signing/`（不含任何机密，可入库）

| 文件 | 作用 |
|------|------|
| `README.md` | 签名凭据管理说明（本地恢复 / CI secrets / 应急重建） |
| `key.properties.example` | key.properties 模板，无真实凭据 |
| `restore-signing.ps1` | 从 DPAPI 备份或 base64 恢复签名到本地 |

`restore-signing.ps1` 还会**收紧 `android/key.properties` 的 ACL**：
关闭继承，仅当前 Windows 账户 FullControl（已验证）。

## 影响文件

- `.github/workflows/android-build.yml`
- `.gitignore`
- `tooling/signing/`（新增 3 个文件）
- 仓库状态：`relko-release.keystore` 由「已跟踪」变为「已删除（索引）」

## 验证方式

```bash
# 1. 签名文件不再被 git 跟踪（应无输出）
git ls-files | grep -E "keystore|key.properties"

# 2. 恢复脚本可用（解密后 SHA256 应与备份一致）
powershell -ExecutionPolicy Bypass -File tooling\signing\restore-signing.ps1
```

- 已实测：删掉本地 keystore 与 key.properties 后，脚本从 DPAPI 备份完整
  还原（SHA256 `659D22FB...BC7BC` 一致），并生成权限收紧的 key.properties。
- PowerShell 5.1 读取无 BOM 的 UTF-8 脚本会按 ANSI 解码导致中文乱码、
  语法解析失败：脚本文件已存为 **UTF-8 with BOM**。后续修改请保持 BOM。

## ⚠️ 残留风险（必须由用户决策，本轮未执行）

1. **git 历史里仍有密钥**：keystore 与明文口令仍存在于历史提交
   `3c24408`（2026-09-29）。`git rm --cached` 只影响 HEAD，**不删除历史**。
   任何在此之前克隆过仓库的人都能取出密钥与口令。
2. 彻底清除需二选一：
   - **A. 重写历史**（`git filter-repo` / BFG）—— 能删掉密钥文件，但
     **明文口令曾在 workflow 中**，`filter-repo` 可一并处理；代价是所有
     commit SHA 变化，**必须 force push 并通知协作者重新克隆**。
   - **B. 轮换密钥** —— 生成新 keystore 并作废旧密钥；但 Android 要求
     升级包签名一致，**已安装用户将无法覆盖升级**（只能卸载重装，丢本地
     下载与播放数据）。本项目经 R2 分发，已有用户安装即不可轻易轮换。
3. 在上述决策落地前，**远端仍是公开的**（`https://github.com/suanx/relko-music`），
   风险持续存在。

> 上述两项均涉及 force push / 破坏性操作，按工作区规则**未经用户明确指令
> 不执行**，故登记在此待决策。

## 未做但相关的加固建议

- CI 中的 `secrets.GITHUB_TOKEN` 写法冗余（`permissions: contents: write`
  已自动注入内置 token），可清理。
- `build.gradle.kts` 本地未配置 key.properties 时会**回退 debug 签名**并
  仅打印警告。CI 侧已 fail-fast 兜住，但本地若忘记恢复签名，产出的包
  无法覆盖安装正式版且不易察觉 —— 可考虑本地 release 构建直接报错。