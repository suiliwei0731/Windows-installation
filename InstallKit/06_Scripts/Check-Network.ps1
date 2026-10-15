<#
.SYNOPSIS
  检查网络状态：网卡识别、IP 与 DNS、官方 HTTPS 站点连通性、是否具备下载条件。
.DESCRIPTION
  纯检测脚本，不修改网络配置。无网络时给出明确提示，并引导使用 01_Network 下的本地离线驱动。
.EXAMPLE
  .\Check-Network.ps1
  .\Check-Network.ps1 -Root "E:\InstallKit" -DryRun
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
$component = 'CheckNetwork'

Write-KitLog -Root $Root -Component $component -Message "开始网络检查（模拟执行：$isDryRun）。"

# 1. 网络适配器识别（按类型区分有线/无线）
$adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
$wired = @($adapters | Where-Object { $_.MediaType -eq '802.3' })
$wireless = @($adapters | Where-Object { $_.MediaType -eq 'Native 802.11' })
$upAdapters = @($adapters | Where-Object { $_.Status -eq 'Up' })

# 2. IP 与 DNS
$ipConfig = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue)
$hasIp = @($ipConfig | Where-Object { $_.IPv4Address -and $_.IPv4Address.IPAddress -notlike '169.254.*' }).Count -gt 0
$dnsServers = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.ServerAddresses.Count -gt 0 } | Select-Object -ExpandProperty ServerAddresses -Unique)

# 3. 官方 HTTPS 站点连通性（TCP 443 探测）
$targets = @('www.microsoft.com', 'learn.microsoft.com', 'dotnet.microsoft.com')
$tcpResults = @()
foreach ($t in $targets) {
    $ok = $false
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect($t, 443, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne(3000)) { $client.EndConnect($async); $ok = $true }
        $client.Close()
    } catch { $ok = $false }
    $tcpResults += [pscustomobject]@{ Target = $t; Reachable = $ok }
}

$reachableCount = @($tcpResults | Where-Object { $_.Reachable }).Count
$networkAvailable = $hasIp -and ($reachableCount -gt 0)

# 4. 输出与结论
Write-Host "网络适配器：有线 $($wired.Count) 个，无线 $($wireless.Count) 个，已连接 $($upAdapters.Count) 个"
foreach ($a in $adapters) {
    Write-Host ("  - {0} | {1} | {2}" -f $a.Name, $a.MediaType, $a.Status)
}
Write-Host "有效 IPv4：$hasIp；DNS：$(if ($dnsServers) { $dnsServers -join ', ' } else { '无' })"
foreach ($r in $tcpResults) {
    Write-Host ("  - {0}:443 可达 {1}" -f $r.Target, $r.Reachable)
}

if ($networkAvailable) {
    Write-KitLog -Root $Root -Component $component -Level SUCCESS -Message "网络可用，具备在线下载条件。"
} else {
    Write-KitLog -Root $Root -Component $component -Level WARN -Message "网络不可用：请使用 01_Network 下的本地离线网卡驱动进行安装。"
    Write-Host ""
    Write-Host "提示：当前不具备在线下载条件。请先安装本地离线网卡驱动（01_Network\Ethernet 或 WiFi）。" -ForegroundColor Yellow
    $offline = Get-ChildItem -Path (Join-Path $Root '01_Network') -Recurse -File -ErrorAction SilentlyContinue
    if ($offline) {
        Write-Host "本地已备网卡驱动文件：" -ForegroundColor Yellow
        $offline | ForEach-Object { Write-Host ("  - {0}" -f $_.FullName) }
    } else {
        Write-Host "  未在 01_Network 下发现离线驱动，请先补充网卡驱动。" -ForegroundColor Yellow
    }
}

if (-not $isDryRun) {
    $reportPath = Join-Path $Root ("09_Reports\check-network-{0}.md" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $lines = @(
        "# 网络检查报告"
        ""
        "- 生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "- 有线网卡：$($wired.Count) 个；无线网卡：$($wireless.Count) 个；已连接：$($upAdapters.Count) 个"
        "- 有效 IPv4：$hasIp"
        "- DNS：$(if ($dnsServers) { $dnsServers -join ', ' } else { '无' })"
        "- 官方站点可达：$reachableCount / $($targets.Count)"
        "- 结论：$(if ($networkAvailable) { '网络可用' } else { '网络不可用，请使用本地离线网卡驱动' })"
    )
    [System.IO.File]::WriteAllText($reportPath, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-KitLog -Root $Root -Component $component -Level SUCCESS -Message "已生成报告：$reportPath"
} else {
    Write-Host "（模拟执行）报告未写入文件。" -ForegroundColor Cyan
}
