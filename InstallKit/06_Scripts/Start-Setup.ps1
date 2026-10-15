<#
.SYNOPSIS
  InstallKit 统一入口：检查环境、识别根目录、展示待执行项、确认后按顺序执行。
.DESCRIPTION
  执行顺序：检查系统 → 检查网络 → 驱动检测 → 安装运行库 → 安装基础工具 → 生成报告。
  不默认执行系统重置、磁盘格式化、分区删除、引导修复、驱动强制覆盖或安全设置修改。
  默认模拟执行（DryRun），真正执行需显式 -Execute 且经用户确认。
.EXAMPLE
  .\Start-Setup.ps1
  .\Start-Setup.ps1 -Execute
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string[]]$Steps,
    [switch]$Execute,
    [switch]$Force
)

. "$PSScriptRoot\Common.ps1"

$Root = Get-InstallKitRoot -Root $Root
$settings = Get-KitSettings -Root $Root

# 未指定 -Execute 时按 settings.json 的 dry_run_default 决定是否模拟执行
$isDryRun = -not $Execute
if ($Execute -and $settings.dry_run_default -and -not $Force) {
    Write-Host "settings.json 中 dry_run_default=true。如确需真实执行，请加 -Force 明确确认。" -ForegroundColor Yellow
    $isDryRun = $true
}

$component = 'StartSetup'
Write-KitLog -Root $Root -Component $component -Message "启动统一入口（根目录：$Root，模拟执行：$isDryRun）。"

# 1. 环境与权限检查
Write-Host "== 环境检查 ==" -ForegroundColor Cyan
& "$PSScriptRoot\Check-System.ps1" -Root $Root -DryRun:$isDryRun

$isAdmin = Test-KitAdmin
if (-not $isAdmin) {
    Write-KitLog -Root $Root -Component $component -Level WARN -Message "当前非管理员，安装步骤可能失败，建议以管理员身份运行。"
    Write-Host "警告：当前不是管理员，安装运行库/工具可能失败。" -ForegroundColor Yellow
}

# 2. 计划执行的步骤
$allSteps = [ordered]@{
    'check-network'    = '检查网络状态'
    'update-drivers'   = '驱动检测（只检测，不覆盖）'
    'install-runtimes' = '安装运行库'
    'install-tools'    = '安装基础工具'
}
$stepScript = @{
    'check-network'    = 'Check-Network.ps1'
    'update-drivers'   = 'Update-Drivers.ps1'
    'install-runtimes' = 'Install-Runtimes.ps1'
    'install-tools'    = 'Install-Tools.ps1'
}

$planKeys = if ($Steps) { @($Steps | Where-Object { $allSteps.Contains($_) }) } else { @($allSteps.Keys) }

# 3. 展示待执行项目并要求确认
Write-Host ""
Write-Host "== 待执行项目（按顺序）==" -ForegroundColor Cyan
$i = 0
foreach ($k in $planKeys) { $i++; Write-Host ("  {0}. {1}" -f $i, $allSteps[$k]) }
Write-Host ""
Write-Host "执行模式：$(if ($isDryRun) { '模拟执行（不修改系统）' } else { '真实执行（会修改系统）' })" -ForegroundColor $(if ($isDryRun) { 'Green' } else { 'Yellow' })

if (-not $isDryRun) {
    $confirm = Read-Host "将真实执行以上步骤，是否继续？输入 YES 确认"
    if ($confirm -ne 'YES') {
        Write-KitLog -Root $Root -Component $component -Level WARN -Message "用户未确认，已取消执行。"
        Write-Host "已取消。" -ForegroundColor Yellow
        return
    }
}

# 4. 按顺序执行
$results = @()
foreach ($k in $planKeys) {
    Write-Host ""
    Write-Host "== 执行：$($allSteps[$k]) ==" -ForegroundColor Cyan
    try {
        & (Join-Path $PSScriptRoot $stepScript[$k]) -Root $Root -DryRun:$isDryRun
        $results += [pscustomobject]@{ Step = $k; Result = 'done' }
    } catch {
        $results += [pscustomobject]@{ Step = $k; Result = 'error' }
        Write-KitLog -Root $Root -Component $component -Level ERROR -Message "步骤 $k 执行异常：$($_.Exception.Message)"
        Write-Host "步骤 $k 失败，停止后续依赖步骤。" -ForegroundColor Red
        break
    }
}

# 5. 生成总体报告
$reportLines = @(
    "# InstallKit 执行报告"
    ""
    "- 生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "- 资源根目录：$Root"
    "- 执行模式：$(if ($isDryRun) { '模拟执行' } else { '真实执行' })"
    "- 管理员权限：$isAdmin"
    ""
    "| 步骤 | 结果 |"
    "| --- | --- |"
)
foreach ($r in $results) { $reportLines += "| $($r.Step) | $($r.Result) |" }
$reportLines | ForEach-Object { Write-Host $_ }

if (-not $isDryRun) {
    $reportPath = Join-Path $Root ("09_Reports\setup-{0}.md" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    [System.IO.File]::WriteAllText($reportPath, ($reportLines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-KitLog -Root $Root -Component $component -Level SUCCESS -Message "已生成总体报告：$reportPath"
} else {
    Write-Host "（模拟执行）报告未写入文件，确认无误后可用 -Execute 真实执行。" -ForegroundColor Cyan
}
