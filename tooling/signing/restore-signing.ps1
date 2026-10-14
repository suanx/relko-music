<#
.SYNOPSIS
    恢复 Android release 签名到本地工作副本（生成 android/key.properties）。

.DESCRIPTION
    签名凭据不入库。本脚本从「仓库外的加密备份」恢复：
      %USERPROFILE%\.relko-secrets\
        relko-release.keystore.dpapi   （keystore 字节，DPAPI 加密）
        storePassword.txt              （口令，DPAPI 加密的 SecureString）
        keyAlias.txt                   （别名，DPAPI 加密的 SecureString）

    DPAPI 以 CurrentUser 作用域加密，**只有当前 Windows 账户**能解密，
    备份文件被拷到别的机器/账户上也无法还原。

    另支持从 GitHub Secrets 的 base64 文本恢复（CI 用的同一份材料）：
      .\restore-signing.ps1 -KeystoreBase64File D:\ks.b64 `
                               -StorePassword  '...' -KeyAlias '...' -KeyPassword '...'

.PARAMETER SecretsDir
    加密备份目录，默认 %USERPROFILE%\.relko-secrets

.PARAMETER KeystoreBase64File
    可选：从该文件读取 base64 keystore（GitHub Secret 的导出形式），
    优先级高于 DPAPI 备份。

.PARAMETER StorePassword / KeyAlias / KeyPassword
    可选：显式传入凭据（配合 -KeystoreBase64File 使用）。
    注意：命令行参数会进入 shell 历史，仅建议在本机临时使用。

.EXAMPLE
    # 常规：从本机 DPAPI 备份恢复
    powershell -ExecutionPolicy Bypass -File tooling\signing\restore-signing.ps1
#>
[CmdletBinding()]
param(
    [string]$SecretsDir = "$env:USERPROFILE\.relko-secrets",
    [string]$KeystoreBase64File,
    [string]$StorePassword,
    [string]$KeyAlias,
    [string]$KeyPassword
)

$ErrorActionPreference = 'Stop'

# 仓库根目录 = 本脚本所在 tooling\signing\ 的上两级
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$keystorePath = Join-Path $repoRoot 'relko-release.keystore'
$keyPropsPath = Join-Path $repoRoot 'android\key.properties'

function ConvertFrom-DpapiSecureString {
    param([string]$Path)
    # 用 .NET 读取并 Trim：跳过可能的 UTF-8 BOM 与尾随换行，
    # 否则 ConvertTo-SecureString 会因前导 BOM 抛 FormatException。
    $raw = [IO.File]::ReadAllText($Path).Trim()
    $secure = $raw | ConvertTo-SecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

# ---- 1. 还原 keystore --------------------------------------------------
if ($KeystoreBase64File) {
    Write-Host "[1/3] 从 base64 文件恢复 keystore: $KeystoreBase64File"
    $b64 = (Get-Content -Path $KeystoreBase64File -Raw) -replace '\s',''
    [IO.File]::WriteAllBytes($keystorePath, [Convert]::FromBase64String($b64))
}
else {
    $dpapiFile = Join-Path $SecretsDir 'relko-release.keystore.dpapi'
    if (-not (Test-Path $dpapiFile)) {
        throw "找不到加密备份：$dpapiFile`n" +
              "请先备份 keystore，或改用 -KeystoreBase64File 从 GitHub Secret 恢复。"
    }
    Write-Host "[1/3] 用 DPAPI 解密 keystore（仅当前 Windows 账户可解）"
    Add-Type -AssemblyName System.Security
    $enc = [IO.File]::ReadAllBytes($dpapiFile)
    $bytes = [Security.Cryptography.ProtectedData]::Unprotect($enc, $null, 'CurrentUser')
    [IO.File]::WriteAllBytes($keystorePath, $bytes)
}

# ---- 2. 还原凭据 -------------------------------------------------------
if (-not $StorePassword -or -not $KeyAlias -or -not $KeyPassword) {
    $storePwFile = Join-Path $SecretsDir 'storePassword.txt'
    $aliasFile   = Join-Path $SecretsDir 'keyAlias.txt'
    if (-not (Test-Path $storePwFile) -or -not (Test-Path $aliasFile)) {
        throw "找不到加密的口令备份（$storePwFile / $aliasFile）`n" +
              "请显式传入 -StorePassword / -KeyAlias / -KeyPassword。"
    }
    if (-not $StorePassword) { $StorePassword = ConvertFrom-DpapiSecureString $storePwFile }
    if (-not $KeyAlias)     { $KeyAlias     = ConvertFrom-DpapiSecureString $aliasFile }
    if (-not $KeyPassword)   { $KeyPassword   = $StorePassword }
}

# ---- 3. 写 android/key.properties --------------------------------------
Write-Host "[2/3] 生成 $keyPropsPath"
$props = @(
    'storeFile=../relko-release.keystore'
    "storePassword=$StorePassword"
    "keyAlias=$KeyAlias"
    "keyPassword=$KeyPassword"
)
# 用 .NET API 写文件并收紧 ACL：仅当前用户可读写
[IO.File]::WriteAllLines($keyPropsPath, $props)
$acl = Get-Acl $keyPropsPath
$acl.SetAccessRuleProtection($true, $false)   # 关闭继承
$rule = New-Object Security.AccessControl.FileSystemAccessRule(
    "$env:USERDOMAIN\$env:USERNAME", 'FullControl', 'Allow')
$acl.SetAccessRule($rule)
Set-Acl -Path $keyPropsPath -AclObject $acl

Write-Host "[3/3] 完成。keystore 与 key.properties 均在 .gitignore 中，不会入库。"
Write-Host "提醒：确认未被 git 跟踪 -> git ls-files | Select-String 'keystore|key.properties'"