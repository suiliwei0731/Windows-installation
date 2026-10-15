<#
.SYNOPSIS
  按清单安装运行库（Visual C++、DirectX 旧组件、指定 .NET Runtime）。
.DESCRIPTION
  从 software-manifest.json 中筛选 category=runtime 的条目，按 install_order 顺序安装：
    - 校验安装包存在性与 SHA-256；
    - 已标记为 installed 的条目自动跳过（重复执行保护）；
    - 记录开始/结束时间、退出码与结果；
    - 需要重启时仅提示，不擅自强制重启。
  默认模拟执行，须显式 -DryRun:$false 才会真正安装。
.EXAMPLE
  .\Install-Runtimes.ps1
  .\Install-Runtimes.ps1 -Id vcredist-2015-2022-x64 -DryRun:$false
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string[]]$Id,
    [switch]$DryRun,
    [switch]$Force
)

. "$PSScriptRoot\Common.ps1"

$Root = Get-InstallKitRoot -Root $Root
$settings = Get-KitSettings -Root $Root
$isDryRun = [bool]$DryRun -or ([bool]$settings.dry_run_default -and -not $PSBoundParameters.ContainsKey('DryRun'))
$component = 'InstallRuntimes'

Write-KitLog -Root $Root -Component $component -Message "开始安装运行库（模拟执行：$isDryRun）。"

# 读取完整清单，其中 runtime 条目即为待处理项（保留引用以便回写状态）
$manifest = Get-KitManifest -Root $Root -Name 'software'
$items = @($manifest | Where-Object { $_.category -eq 'runtime' })
if ($Id) { $items = @($items | Where-Object { $Id -contains $_.id }) }
$items = @($items | Sort-Object install_order)

if (-not $items.Count) {
    Write-KitLog -Root $Root -Component $component -Level WARN -Message "未找到匹配的运行库条目，请检查 config\software-manifest.json。"
    return
}

Write-Host "待处理运行库（共 $($items.Count) 项）："
$items | ForEach-Object { Write-Host ("  - [{0}] {1}" -f $_.install_order, $_.name) }

$results = @()
$restartNeeded = $false
foreach ($item in $items) {
    $r = Install-KitItem -Root $Root -Item $item -DryRun:$isDryRun -Force:$Force -Component $component
    if ($r.Result -eq 'success' -and -not $isDryRun) { $item.status = 'installed' }
    if ($r.RestartRequired) { $restartNeeded = $true }
    $results += $r
}

if (-not $isDryRun) {
    Save-KitJson -Path (Join-Path $Root 'config\software-manifest.json') -InputObject $manifest
}

# 汇总
$okCount = @($results | Where-Object { $_.Result -in 'success', 'already-installed', 'simulated', 'no-installer' }).Count
$failCount = @($results | Where-Object { $_.Result -in 'failed', 'error', 'package-missing', 'hash-mismatch' }).Count
Write-KitLog -Root $Root -Component $component -Level $(if ($failCount) { 'WARN' } else { 'SUCCESS' }) -Message "运行库处理完成：成功 $okCount 项，失败/跳过问题 $failCount 项。"

if ($restartNeeded) {
    Write-Host "注意：部分组件安装后需要重启才能生效，请自行安排重启（脚本不会强制重启）。" -ForegroundColor Yellow
    Write-KitLog -Root $Root -Component $component -Level WARN -Message "存在需要重启的组件，已提示用户，未强制重启。"
}

$reportLines = @(
    "# 运行库安装报告"
    ""
    "- 生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "- 模拟执行：$isDryRun"
    "- 需要重启：$restartNeeded"
    ""
    "| ID | 动作 | 退出码 | 结果 |"
    "| --- | --- | --- | --- |"
)
foreach ($r in $results) { $reportLines += "| $($r.Id) | $($r.Action) | $($r.ExitCode) | $($r.Result) |" }

if (-not $isDryRun) {
    $reportPath = Join-Path $Root ("09_Reports\install-runtimes-{0}.md" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    [System.IO.File]::WriteAllText($reportPath, ($reportLines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-KitLog -Root $Root -Component $component -Level SUCCESS -Message "已生成报告：$reportPath"
} else {
    Write-Host "（模拟执行）报告未写入文件。" -ForegroundColor Cyan
}
