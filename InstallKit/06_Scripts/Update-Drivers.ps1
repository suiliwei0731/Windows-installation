<#
.SYNOPSIS
  检测、匹配适用驱动；默认仅检测，指定 -Install 时安装 01_Network 下的离线网卡驱动。
.DESCRIPTION
  默认只做检测与整理，不安装、不覆盖任何现有驱动：
    - 获取硬件设备信息与未知/异常设备；
    - 按厂商、型号与硬件 ID 匹配 driver-manifest.json；
    - 校验本地驱动包签名；
    - 对存储控制器等高风险驱动给出明确警告。
  指定 -Install 时，额外使用系统自带的 pnputil 安装 01_Network 下的 .inf 离线网卡驱动
  （仅限网络类低风险驱动；02_Drivers 下的高风险驱动仍不自动安装，需人工在设备管理器处理）。
.EXAMPLE
  .\Update-Drivers.ps1
  .\Update-Drivers.ps1 -Install
  .\Update-Drivers.ps1 -Install -DryRun:$false
#>
[CmdletBinding()]
param(
    [string]$Root,
    [switch]$DryRun,
    [switch]$Install
)

. "$PSScriptRoot\Common.ps1"

$Root = Get-InstallKitRoot -Root $Root
$settings = Get-KitSettings -Root $Root
$isDryRun = [bool]$DryRun -or ([bool]$settings.dry_run_default -and -not $PSBoundParameters.ContainsKey('DryRun'))
$component = 'UpdateDrivers'

Write-KitLog -Root $Root -Component $component -Message "开始驱动检测（模拟执行：$isDryRun）。本脚本默认不覆盖任何现有驱动。"

# 1. 获取设备信息：重点为状态异常（未知设备）的条目
$allDevices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)
$problemDevices = @($allDevices | Where-Object { $_.Status -ne 'OK' })
$netDevices = @($allDevices | Where-Object { $_.Class -in 'Net', 'Bluetooth' })
$displayDevices = @($allDevices | Where-Object { $_.Class -eq 'Display' })

Write-Host "设备统计：共 $($allDevices.Count) 个，异常/未知 $($problemDevices.Count) 个，网络/蓝牙 $($netDevices.Count) 个，显示适配器 $($displayDevices.Count) 个"
if ($problemDevices.Count) {
    Write-Host "异常设备列表："
    $problemDevices | ForEach-Object { Write-Host ("  - {0} | {1} | {2}" -f $_.FriendlyName, $_.Class, $_.Status) }
    Write-KitLog -Root $Root -Component $component -Level WARN -Message "存在 $($problemDevices.Count) 个异常/未知设备，可能需要对应驱动。"
}

# 2. 与清单匹配
$manifest = Get-KitManifest -Root $Root -Name 'driver'
$matched = @()
foreach ($entry in $manifest) {
    # 模板条目（版本/校验值/官方地址均未配置）不参与匹配，避免输出误导性信息
    if ([string]::IsNullOrWhiteSpace($entry.version) -and [string]::IsNullOrWhiteSpace($entry.sha256) -and [string]::IsNullOrWhiteSpace($entry.official_url)) {
        $matched += [pscustomobject]@{
            Id = $entry.id; Name = $entry.name; DeviceType = $entry.device_type
            MatchedDevice = '（模板，未配置）'; PackageExists = $false; Signature = 'n/a'; RiskLevel = $entry.risk_level
        }
        continue
    }
    $device = $null
    if ($entry.hardware_ids -and $entry.hardware_ids.Count) {
        $device = $problemDevices | Where-Object {
            $instanceId = $_.InstanceId
            @($entry.hardware_ids | Where-Object { $instanceId -like "*$_*" }).Count -gt 0
        } | Select-Object -First 1
    }
    if (-not $device) {
        $classMap = @{ Ethernet = 'Net'; WiFi = 'Net'; Bluetooth = 'Bluetooth'; GPU = 'Display' }
        $cls = $classMap[$entry.device_type]
        if ($cls) {
            $device = $allDevices | Where-Object { $_.Class -eq $cls } | Select-Object -First 1
        }
    }

    $pkgPath = Resolve-KitPath -Root $Root -RelativePath $entry.local_path
    $pkgExists = Test-Path -LiteralPath $pkgPath

    # 3. 校验驱动签名（若本地存在 .cat/.sys/.inf）
    $sigStatus = 'n/a'
    if ($pkgExists) {
        $sigFile = Get-ChildItem -Path $pkgPath -Recurse -File -Include *.cat, *.sys, *.inf -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($sigFile) {
            $sig = Get-AuthenticodeSignature -FilePath $sigFile.FullName -ErrorAction SilentlyContinue
            if ($sig) { $sigStatus = $sig.Status.ToString() }
        }
    }

    $matched += [pscustomobject]@{
        Id = $entry.id; Name = $entry.name; DeviceType = $entry.device_type
        MatchedDevice = if ($device) { $device.FriendlyName } else { '未匹配到设备' }
        PackageExists = $pkgExists; Signature = $sigStatus; RiskLevel = $entry.risk_level
    }
}

Write-Host ""
Write-Host "驱动匹配结果："
foreach ($m in $matched) {
    Write-Host ("  - {0} | 设备：{1} | 包就位：{2} | 签名：{3} | 风险：{4}" -f $m.Name, $m.MatchedDevice, $m.PackageExists, $m.Signature, $m.RiskLevel)
}

# 4. 高风险提示
$highRisk = @($matched | Where-Object { $_.RiskLevel -eq 'high' })
if ($highRisk.Count) {
    Write-Host ""
    Write-Host "以下为高风险驱动（存储控制器/启动关键），强制覆盖可能导致系统无法启动，须人工确认后再操作：" -ForegroundColor Yellow
    $highRisk | ForEach-Object { Write-Host ("  - {0}" -f $_.Name) -ForegroundColor Yellow }
    Write-KitLog -Root $Root -Component $component -Level WARN -Message "存在 $($highRisk.Count) 个高风险驱动条目，已提示用户，未执行任何覆盖。"
}

# 5. 安装离线网卡驱动（仅在指定 -Install 时；使用系统自带 pnputil）
$driverResults = @()
if ($Install) {
    Write-Host ""
    Write-Host "== 安装离线网卡驱动（01_Network）==" -ForegroundColor Cyan
    $netRoot = Join-Path $Root '01_Network'
    $infFiles = @(Get-ChildItem -Path $netRoot -Recurse -File -Filter '*.inf' -ErrorAction SilentlyContinue)
    if (-not $infFiles.Count) {
        Write-KitLog -Root $Root -Component $component -Level WARN -Message "01_Network 下未发现 .inf 驱动文件，无法安装网卡驱动；请按硬件型号补充官方驱动后重试。"
        Write-Host "未在 01_Network 找到 .inf 驱动，跳过。请按硬件型号下载官方网卡驱动后重试。" -ForegroundColor Yellow
    } else {
        foreach ($inf in $infFiles) {
            if ($isDryRun) {
                Write-KitLog -Root $Root -Component $component -Message "[模拟] 将执行：pnputil /add-driver `"$($inf.FullName)`" /install"
                $driverResults += [pscustomobject]@{ Inf = $inf.Name; Result = 'simulated' }
                continue
            }
            try {
                # pnputil 为 Windows 自带官方命令；顺序安装，前一个结束再处理下一个
                $proc = Start-Process -FilePath 'pnputil.exe' -ArgumentList @('/add-driver', "`"$($inf.FullName)`"", '/install') -Wait -PassThru -ErrorAction Stop
                if ($proc.ExitCode -in 0, 3010) {
                    Write-KitLog -Root $Root -Component $component -Level SUCCESS -Message "网卡驱动安装成功：$($inf.Name)，退出码 $($proc.ExitCode)"
                    $driverResults += [pscustomobject]@{ Inf = $inf.Name; Result = 'success' }
                } elseif ($proc.ExitCode -eq 259) {
                    # 259：驱动包已在驱动存储中或无需更新，视为已完成（重复执行时不误报失败）
                    Write-KitLog -Root $Root -Component $component -Level SUCCESS -Message "网卡驱动已存在/无需更新：$($inf.Name)，退出码 259"
                    $driverResults += [pscustomobject]@{ Inf = $inf.Name; Result = 'already-installed' }
                } else {
                    Write-KitLog -Root $Root -Component $component -Level ERROR -Message "网卡驱动安装失败：$($inf.Name)，退出码 $($proc.ExitCode)"
                    $driverResults += [pscustomobject]@{ Inf = $inf.Name; Result = 'failed' }
                }
            } catch {
                Write-KitLog -Root $Root -Component $component -Level ERROR -Message "网卡驱动安装异常：$($inf.Name)，$($_.Exception.Message)"
                $driverResults += [pscustomobject]@{ Inf = $inf.Name; Result = 'error' }
            }
        }
    }
}

if ($Install) {
    Write-KitLog -Root $Root -Component $component -Message "驱动处理完成：已尝试安装 01_Network 下的离线网卡驱动；02_Drivers 下的高风险驱动仍不自动安装。"
} else {
    Write-KitLog -Root $Root -Component $component -Message "驱动检测完成：未覆盖现有驱动；如需安装离线网卡驱动可加 -Install 参数。"
}

$reportLines = @(
    "# 驱动检测报告"
    ""
    "- 生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "- 异常/未知设备：$($problemDevices.Count) 个"
    "- 说明：默认仅检测与整理，不覆盖当前正常驱动。"
    "- 网卡驱动安装：$(if ($Install) { '已尝试（01_Network）' } else { '未执行（默认仅检测）' })"
    ""
    "| ID | 名称 | 设备类型 | 匹配设备 | 包就位 | 签名 | 风险 |"
    "| --- | --- | --- | --- | --- | --- | --- |"
)
foreach ($m in $matched) { $reportLines += "| $($m.Id) | $($m.Name) | $($m.DeviceType) | $($m.MatchedDevice) | $($m.PackageExists) | $($m.Signature) | $($m.RiskLevel) |" }
if ($driverResults.Count) {
    $reportLines += ""
    $reportLines += "## 离线网卡驱动安装结果"
    $reportLines += ""
    $reportLines += "| INF | 结果 |"
    $reportLines += "| --- | --- |"
    foreach ($dr in $driverResults) { $reportLines += "| $($dr.Inf) | $($dr.Result) |" }
}

if (-not $isDryRun) {
    $reportPath = Join-Path $Root ("09_Reports\driver-detect-{0}.md" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    [System.IO.File]::WriteAllText($reportPath, ($reportLines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-KitLog -Root $Root -Component $component -Level SUCCESS -Message "已生成报告：$reportPath"
} else {
    Write-Host "（模拟执行）报告未写入文件。" -ForegroundColor Cyan
}
