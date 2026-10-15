<#
.SYNOPSIS
  按清单安装基础工具（解压工具、浏览器、诊断工具等）。
.DESCRIPTION
  从 software-manifest.json 中筛选 category=tool 的条目，默认只安装清单中明确列出的软件：
    - 不捆绑安装广告软件；
    - 不修改浏览器首页、默认搜索引擎或系统安全设置；
    - 支持单项安装（-Id）与失败自动重试（-Retry）。
  默认模拟执行，须显式 -DryRun:$false 才会真正安装。
.EXAMPLE
  .\Install-Tools.ps1
  .\Install-Tools.ps1 -Id 7zip-x64 -Retry -DryRun:$false
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string[]]$Id,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Retry
)

. "$PSScriptRoot\Common.ps1"

$Root = Get-InstallKitRoot -Root $Root
$settings = Get-KitSettings -Root $Root
$isDryRun = [bool]$DryRun -or ([bool]$settings.dry_run_default -and -not $PSBoundParameters.ContainsKey('DryRun'))
$component = 'InstallTools'

Write-KitLog -Root $Root -Component $component -Message "开始安装基础工具（模拟执行：$isDryRun，失败重试：$([bool]$Retry)）。"

$items = Get-KitManifest -Root $Root -Name 'software' | Where-Object { $_.category -eq 'tool' }
if ($Id) { $items = $items | Where-Object { $Id -contains $_.id } }
$items = @($items | Sort-Object install_order)

if (-not $items.Count) {
    Write-KitLog -Root $Root -Component $component -Level WARN -Message "未找到匹配的工具条目，请检查 config\software-manifest.json。"
    return
}

Write-Host "待处理工具（共 $($items.Count) 项）："
$items | ForEach-Object { Write-Host ("  - [{0}] {1}" -f $_.install_order, $_.name) }

$results = @()
$manifest = Get-KitManifest -Root $Root -Name 'software'
foreach ($item in $items) {
    $r = Install-KitItem -Root $Root -Item $item -DryRun:$isDryRun -Force:$Force -Component $component

    # 失败重试一次（仅在非模拟执行时）
    if ($Retry -and -not $isDryRun -and $r.Result -in 'failed', 'error') {
        Write-KitLog -Root $Root -Component $component -Level WARN -Message "重试安装：$($item.id)"
        $r = Install-KitItem -Root $Root -Item $item -DryRun:$isDryRun -Force:$Force -Component $component
    }

    if ($r.Result -eq 'success' -and -not $isDryRun) {
        $target = $manifest | Where-Object { $_.id -eq $item.id }
        if ($target) { $target.status = 'installed' }
    }
    $results += $r
}

if (-not $isDryRun) {
    Save-KitJson -Path (Join-Path $Root 'config\software-manifest.json') -InputObject $manifest
}

$okCount = @($results | Where-Object { $_.Result -in 'success', 'already-installed', 'simulated', 'no-installer' }).Count
$failCount = @($results | Where-Object { $_.Result -in 'failed', 'error', 'package-missing', 'hash-mismatch' }).Count
Write-KitLog -Root $Root -Component $component -Level $(if ($failCount) { 'WARN' } else { 'SUCCESS' }) -Message "工具处理完成：成功 $okCount 项，失败 $failCount 项。"

$reportLines = @(
    "# 工具安装报告"
    ""
    "- 生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "- 模拟执行：$isDryRun"
    ""
    "| ID | 动作 | 退出码 | 结果 |"
    "| --- | --- | --- | --- |"
)
foreach ($r in $results) { $reportLines += "| $($r.Id) | $($r.Action) | $($r.ExitCode) | $($r.Result) |" }
$reportLines | ForEach-Object { Write-Host $_ }

if (-not $isDryRun) {
    $reportPath = Join-Path $Root ("09_Reports\install-tools-{0}.md" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    [System.IO.File]::WriteAllText($reportPath, ($reportLines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-KitLog -Root $Root -Component $component -Level SUCCESS -Message "已生成报告：$reportPath"
}
