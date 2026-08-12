# 一键上传到 GitHub 并触发自动编译
# 使用 GitHub 官方命令行工具 gh（浏览器登录，最安全简单）
# 用法: powershell -ExecutionPolicy Bypass -File upload_to_github.ps1

$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ROOT

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  语音待办 - 一键上传 GitHub" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "[错误] 未检测到 git。请先安装 Git for Windows：" -ForegroundColor Red
    Write-Host "       https://git-scm.com/download/win"
    exit 1
}

# ---------- 1. 检查/安装 gh ----------
$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    Write-Host "[提示] 缺少 GitHub 官方命令行工具 gh。" -ForegroundColor Yellow
    $ans = Read-Host "是否自动安装（需要联网，会用系统自带 winget 安装）？[Y/n]"
    if ($ans -notmatch "^[Yy]$" -and $ans -ne "") {
        Write-Host "[已取消] 脚本结束。可自行安装后重跑：winget install --id GitHub.cli"
        exit 0
    }
    Write-Host "[安装] 正在通过 winget 安装 GitHub CLI ..."
    winget install --id GitHub.cli --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[错误] 安装失败。请手动安装后重试：https://cli.github.com/" -ForegroundColor Red
        exit 1
    }
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}
Write-Host "[OK] 找到 gh。" -ForegroundColor Green

# ---------- 2. 登录 ----------
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$null = & gh auth status 2>&1
$loggedIn = ($LASTEXITCODE -eq 0)
if (-not $loggedIn) {
    Write-Host ""
    Write-Host "[登录] 即将打开浏览器窗口，请按提示登录 GitHub 账号。" -ForegroundColor Cyan
    Write-Host "       （只要登录，权限只需创建仓库即可）"
    & gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[错误] 登录失败。请重跑脚本。"
        $ErrorActionPreference = $prevEap
        exit 1
    }
}
$ErrorActionPreference = $prevEap
Write-Host "[OK] 已登录 GitHub。" -ForegroundColor Green

# ---------- 3. 仓库名 ----------
$defaultName = "voice-todo"
Write-Host ""
$repoName = Read-Host "仓库名称 [回车用默认 $defaultName]"
if ([string]::IsNullOrWhiteSpace($repoName)) { $repoName = $defaultName }

# ---------- 4. 创建私有仓库并推送 ----------
Write-Host "[上传] 正在创建私有仓库 $repoName 并推送代码 ..." -ForegroundColor Cyan
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& gh repo create $repoName --private --source $ROOT --push
if ($LASTEXITCODE -ne 0) {
    Write-Host "[错误] 创建/推送失败。可能仓库已存在，可重跑时换一个名字。" -ForegroundColor Red
    $ErrorActionPreference = $prevEap
    exit 1
}
$ErrorActionPreference = $prevEap
Write-Host "[OK] 代码已上传。" -ForegroundColor Green

# ---------- 5. 打开 Actions 页面 ----------
$login = & gh api user -q .login 2>&1 | Out-String
$login = $login.Trim()
$url = "https://github.com/$login/$repoName/actions"
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  代码已上传，正在自动编译！" -ForegroundColor Green
Write-Host "  打开任务页面试查看进度:" -ForegroundColor White
Write-Host "  $url" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[打开] 正在浏览器打开任务页..."
Start-Process $url

Write-Host ""
Write-Host "接下来的步骤见 docs/SETUP.md：" -ForegroundColor Yellow
Write-Host "  等 Actions 变绿 -> 下载 VoiceTodo-ipa -> Sideloadly/AltStore 签名安装" -ForegroundColor Yellow
