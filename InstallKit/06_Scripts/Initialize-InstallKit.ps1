<#
.SYNOPSIS
  初始化并准备装机资源库：建立目录结构、扫描安装包、计算 SHA-256、更新清单、记录日志。
.DESCRIPTION
  对应 MVP 阶段「只准备资源，不修改系统」。本脚本不会安装、不会修改系统设置：
    - 建立资源库目录结构；
    - 扫描 software-manifest.json 中登记的安装包；
    - 计算文件 SHA-256 并回写清单，更新 status；
    - 输出准备结果报告。
  支持 -DryRun 模拟执行：模拟时不建立目录、不写清单、不写报告，仅输出将要执行的动作并写日志。
.EXAMPLE
  .\Initialize-InstallKit.ps1
  .\Initialize-InstallKit.ps1 -Root "E:\InstallKit" -DryRun
#>
[CmdletBinding()]
param(
    [string]$Root,
    [switch]$DryRun
)

. "$PSScriptRoot\Common.ps1"

$Root = Get-InstallKitRoot -Root $Root
$settings = Get-KitSettings -Root $Root

# 未显式给出 -DryRun 时，按 settings.json 的 dry_run_default 决定是否模拟执行
$isDryRun = [bool]$DryRun -or ([bool]$settings.dry_run_default -and -not $PSBoundParameters.ContainsKey('DryRun'))

$component = 'Initialize'
Write-KitLog -Root $Root -Component $component -Message "开始初始化资源库（模拟执行：$isDryRun）。根目录：$Root"

# 资源库标准目录结构
$kitDirs = @(
    'config'
    '00_System\WindowsISO', '00_System\BootMediaNotes'
    '01_Network\Ethernet', '01_Network\WiFi', '01_Network\Bluetooth'
    '02_Drivers\Chipset', '02_Drivers\GPU', '02_Drivers\Audio', '02_Drivers\Storage', '02_Drivers\Other'
    '03_Runtime\VisualCpp\x64', '03_Runtime\VisualCpp\x86', '03_Runtime\DirectX', '03_Runtime\DotNet'
    '04_Tools\Archive', '04_Tools\Browser', '04_Tools\Terminal', '04_Tools\Diagnostics'
    '05_Applications', '06_Scripts', '07_Logs', '08_DownloadCache', '09_Reports'
)

$createdDirs = @()
$existingDirs = 0
foreach ($d in $kitDirs) {
    $full = Join-Path $Root $d
    if (Test-Path -LiteralPath $full) {
        $existingDirs++
        continue
    }
    if ($isDryRun) {
        Write-KitLog -Root $Root -Component $component -Message "[模拟] 将创建目录：$d"
    } else {
        New-Item -ItemType Directory -Path $full -Force | Out-Null
        Write-KitLog -Root $Root -Component $component -Level SUCCESS -Message "已创建目录：$d"
    }
    $createdDirs += $d
}

# 扫描软件清单，计算并校验 SHA-256
$items = Get-KitManifest -Root $Root -Name 'software'
$results = @()
$verifiedCount = 0
$missingCount = 0
$mismatchCount = 0

foreach ($item in $items) {
    $full = Resolve-KitPath -Root $Root -RelativePath $item.local_path
    $record = [pscustomobject]@{
        Id      = $item.id
        Name    = $item.name
        Path    = $item.local_path
        Exists  = $false
        Sha256  = ''
        Matched = $false
        Status  = 'missing'
    }

    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        $missingCount++
        Write-KitLog -Root $Root -Component $component -Level WARN -Message "安装包缺失：$($item.local_path)"
        $results += $record
        continue
    }

    $hash = Get-KitSha256 -Path $full
    $record.Exists = $true
    $record.Sha256 = $hash

    if ([string]::IsNullOrWhiteSpace($item.sha256)) {
        # 清单中未登记校验值：以实际计算值补齐，标记为已验证
        $record.Matched = $true
        $record.Status = 'verified'
        if (-not $isDryRun) { $item.sha256 = $hash; $item.status = 'verified' }
        $verifiedCount++
    } elseif ($hash -eq $item.sha256.ToLower()) {
        $record.Matched = $true
        $record.Status = 'verified'
        if (-not $isDryRun) { $item.status = 'verified' }
        $verifiedCount++
    } else {
        $record.Status = 'failed'
        if (-not $isDryRun) { $item.status = 'failed' }
        $mismatchCount++
        Write-KitLog -Root $Root -Component $component -Level ERROR -Message "校验失败：$($item.id)，清单值 $($item.sha256)，实际值 $hash"
    }

    $results += $record
}

# 回写清单（仅在非模拟执行时）
if (-not $isDryRun) {
    Save-KitJson -Path (Join-Path $Root 'config\software-manifest.json') -InputObject $items
    Write-KitLog -Root $Root -Component $component -Message "已更新软件清单：config\software-manifest.json"
}

# 输出准备结果报告
$summary = "扫描 $($items.Count) 项，已验证 $verifiedCount 项，缺失 $missingCount 项，校验失败 $mismatchCount 项。"
Write-KitLog -Root $Root -Component $component -Level SUCCESS -Message $summary

$reportLines = @(
    "# 资源库准备报告"
    ""
    "- 生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "- 资源根目录：$Root"
    "- 模拟执行：$isDryRun"
    "- 新建目录：$($createdDirs.Count) 个，既有目录：$existingDirs 个"
    "- 清单统计：$summary"
    ""
    "| ID | 名称 | 是否就位 | SHA-256 | 状态 |"
    "| --- | --- | --- | --- | --- |"
)
foreach ($r in $results) {
    $reportLines += "| $($r.Id) | $($r.Name) | $($r.Exists) | $($r.Sha256) | $($r.Status) |"
}

if ($isDryRun) {
    Write-Host ""
    Write-Host "（模拟执行）以下报告未写入文件，实际执行时将保存至 09_Reports：" -ForegroundColor Cyan
    $reportLines | ForEach-Object { Write-Host $_ }
} else {
    $reportPath = Join-Path $Root ("09_Reports\resource-prep-{0}.md" -f (Get-Date -Format 'yyyyMMdd'))
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($reportPath, ($reportLines -join "`r`n"), $utf8NoBom)
    Write-KitLog -Root $Root -Component $component -Level SUCCESS -Message "已生成报告：09_Reports\resource-prep-$(Get-Date -Format 'yyyyMMdd').md"
}
