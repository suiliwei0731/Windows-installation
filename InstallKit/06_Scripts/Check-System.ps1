<#
.SYNOPSIS
  检查系统环境：Windows 版本与构建号、系统架构、管理员权限、磁盘空间、资源库路径与必要安装包。
.DESCRIPTION
  纯检测脚本，不修改任何系统设置。结果输出到控制台，并在非模拟执行时生成报告到 09_Reports。
.EXAMPLE
  .\Check-System.ps1
  .\Check-System.ps1 -Root "E:\InstallKit" -DryRun
#>
[CmdletBinding()]
param(
    [string]$Root,
    [switch]$DryRun
)

. "$PSScriptRoot\Common.ps1"

$Root = Get-InstallKitRoot -Root $Root
$settings = Get-KitSettings -Root $Root
$isDryRun = [bool]$DryRun -or ([bool]$settings.dry_run_default -and -not $PSBoundParameters.ContainsKey('DryRun'))
$component = 'CheckSystem'

Write-KitLog -Root $Root -Component $component -Message "开始系统环境检查（模拟执行：$isDryRun）。"

# 1. Windows 版本与构建号
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$currentVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
$displayVersion = $currentVersion.DisplayVersion
$buildNumber = $os.BuildNumber
$ubr = $currentVersion.UBR

# 2. 系统架构
$osArch = $os.OSArchitecture
$procArch = $env:PROCESSOR_ARCHITECTURE
$targetArch = $settings.target_arch
$archMatches = ($targetArch -eq 'x64' -and $osArch -like '*64*')

# 3. 管理员权限
$isAdmin = Test-KitAdmin

# 4. 磁盘空间（资源库所在卷）
$driveLetter = (Split-Path -Qualifier $Root).TrimEnd(':')
$volume = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$driveLetter`:'"
$freeGB = [math]::Round($volume.FreeSpace / 1GB, 2)
$totalGB = [math]::Round($volume.Size / 1GB, 2)
$spaceOk = $freeGB -ge 5

# 5. 必要安装包（清单中 optional=false 的条目）
$required = Get-KitManifest -Root $Root -Name 'software' | Where-Object { -not $_.optional }
$missing = @()
foreach ($item in $required) {
    $full = Resolve-KitPath -Root $Root -RelativePath $item.local_path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { $missing += $item.id }
}

# 汇总结果
$lines = @(
    "# 系统环境检查报告"
    ""
    "- 生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "- 操作系统：$($os.Caption)（版本 $displayVersion，构建 $buildNumber.$ubr）"
    "- 系统架构：$osArch（进程 $procArch，目标 $targetArch，匹配：$archMatches）"
    "- 管理员权限：$isAdmin"
    "- 资源根目录：$Root"
    "- 磁盘空间：${freeGB} GB 可用 / ${totalGB} GB 总计（充足：$spaceOk）"
    "- 必要安装包缺失：$(if ($missing.Count) { $missing -join ', ' } else { '无' })"
)
$lines | ForEach-Object { Write-Host $_ }

if ($missing.Count) {
    Write-KitLog -Root $Root -Component $component -Level WARN -Message "以下必要安装包缺失：$($missing -join ', ')"
} else {
    Write-KitLog -Root $Root -Component $component -Level SUCCESS -Message "必要安装包齐备。"
}
if (-not $isAdmin) {
    Write-KitLog -Root $Root -Component $component -Level WARN -Message "当前非管理员运行，后续安装步骤需管理员权限。"
}

if (-not $isDryRun) {
    $reportPath = Join-Path $Root ("09_Reports\check-system-{0}.md" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    [System.IO.File]::WriteAllText($reportPath, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-KitLog -Root $Root -Component $component -Level SUCCESS -Message "已生成报告：$reportPath"
} else {
    Write-Host "（模拟执行）报告未写入文件。" -ForegroundColor Cyan
}
