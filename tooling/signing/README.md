# Android 签名凭据管理

release 签名密钥**不入库**。本目录只存放**不含机密**的模板与脚本。

## 文件说明

| 文件 | 是否含机密 | 说明 |
|------|-----------|------|
| `key.properties.example` | 否 | `android/key.properties` 的模板，可安全提交 |
| `restore-signing.ps1` | 否 | 从仓库外的加密备份恢复签名到本地 |
| `README.md` | 否 | 本文件 |

以下内容**全部在仓库之外**，本仓库不含任何一份：

- `relko-release.keystore`（工作副本存在，但已被 `.gitignore` 忽略且
  `git rm --cached` 取消跟踪）
- `android/key.properties`（`.gitignore` 已忽略）
- DPAPI 加密备份：`%USERPROFILE%\.relko-secrets\`

## 本地开发：从加密备份恢复签名

前提：本机已存在 `%USERPROFILE%\.relko-secrets\`（用同一 Windows 账户
创建的 DPAPI 备份，别的账户/机器无法解密）。

```powershell
powershell -ExecutionPolicy Bypass -File tooling\signing\restore-signing.ps1
```

脚本会做三件事：

1. 用 **DPAPI（CurrentUser 作用域）** 解密 keystore 到仓库工作副本；
2. 解密口令/别名（`keyPassword` 缺省与 `storePassword` 相同）；
3. 生成 `android/key.properties`，并**关闭 ACL 继承**，仅当前用户可读写。

验证是否就绪：

```bash
# 应无输出（说明两个文件都没被 git 跟踪）
git ls-files | grep -E "keystore|key.properties"
```

未恢复时 `build.gradle.kts` 会打印警告并**回退 debug 签名**——能用，但产出的
APK 不能覆盖安装已发布的正式版。

## CI：签名走 GitHub Secrets

`.github/workflows/android-build.yml` 从以下 4 个 **Repository Secrets**
读取（GitHub 对 secret 值静态加密，界面上永不回显）：

| Secret | 内容 |
|--------|------|
| `ANDROID_KEYSTORE_BASE64` | keystore 文件的 base64（**单行**，无换行） |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 口令 |
| `ANDROID_KEY_ALIAS` | 密钥别名 |
| `ANDROID_KEY_PASSWORD` | 密钥口令 |

生成 base64（Windows PowerShell，输出无换行）：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('relko-release.keystore')) | Set-Content -NoNewline D:\ks.b64
```

CI 在构建时把 base64 解码回 `relko-release.keystore`（CI 工作目录内的
临时文件，任务结束即销毁）并写出 `android/key.properties`。**任一 secret
缺失，CI 直接失败**，不会再静默产出 debug 签名的包发到 R2。

若需要用导出的 base64 在本机恢复：

```powershell
powershell -ExecutionPolicy Bypass -File tooling\signing\restore-signing.ps1 `
  -KeystoreBase64File D:\ks.b64 `
  -StorePassword '<storePassword>' -KeyAlias '<keyAlias>' -KeyPassword '<keyPassword>'
```

> ⚠️ 命令行传参会进 shell 历史，仅限本机临时使用，优先用 DPAPI 备份方式。

## 应急：重新生成签名密钥（会失去覆盖安装能力）

**只有在新机/新环境且确实没有备份时**才用：

```bash
keytool -genkeypair -v -keystore relko-release.keystore \
  -keyalg RSA -keysize 2048 -validity 10000 -alias relko
```

⚠️ 新密钥与线上已发布 APK 的签名不同 → **已安装的用户无法覆盖升级**，只能
卸载重装（会丢本地下载与播放数据）。本项目通过 R2 分发 APK，一旦有用户
安装就必须一直沿用同一把密钥，切勿随意轮换。