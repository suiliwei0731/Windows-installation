<#
.SYNOPSIS
  InstallKit 公共函数库：资源根目录识别、日志记录、清单与配置读取。
.DESCRIPTION
  由 06_Scripts 下各脚本 dot-source 引用，集中处理以下共性逻辑，避免各脚本重复实现：
    1. 按标记文件 config\settings.json 自动识别资源库根目录（不写死盘符，见 ADR-001）。
    2. 统一日志输出到 07_Logs。
    3. 统一以 .NET UTF8 读取 JSON，避免中文乱码。
  所有函数均为只读或仅写日志文件，不修改系统。
.EXAMPLE
  . "$PSScriptRoot\Common.ps1"
  $root = Get-InstallKitRoot
#>

# 资源库根目录标记文件：包含该文件的目录即视为资源库根
$script:KitRootMarker = 'config\settings.json'

function Get-InstallKitRoot {
    <#
    .SYNOPSIS
      识别资源库根目录。
    .DESCRIPTION
      定位顺序：显式 -Root 参数 → 从 -StartPath 向上回溯查找标记文件 → 失败即报错。
      定位失败时必须报错，不得静默使用默认路径。
    #>
    [CmdletBinding()]
    param(
        [string]$Root,
        [string]$StartPath = $PSScriptRoot
    )

    if ($Root) {
        if (Test-Path -LiteralPath (Join-Path $Root $script:KitRootMarker)) {
            return (Resolve-Path -LiteralPath $Root).Path
        }
        throw "指定的根目录 '$Root' 中未找到标记文件 $($script:KitRootMarker)。"
    }

    $dir = Get-Item -LiteralPath $StartPath
    while ($null -ne $dir) {
        if (Test-Path -LiteralPath (Join-Path $dir.FullName $script:KitRootMarker)) {
            return $dir.FullName
        }
        $dir = $dir.Parent
    }

    throw "未能识别资源库根目录：请使用 -Root 指定包含 '$($script:KitRootMarker)' 的目录。"
}

function Read-KitJson {
    <#
    .SYNOPSIS
      以 UTF-8 读取 JSON 文件（自动处理 BOM），返回对象。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "配置文件不存在：$Path"
    }
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    return ($text | ConvertFrom-Json)
}

function Get-KitSettings {
    <#
    .SYNOPSIS
      读取资源库配置 settings.json。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    return (Read-KitJson -Path (Join-Path $Root 'config\settings.json'))
}

function Get-KitManifest {
    <#
    .SYNOPSIS
      读取指定清单文件并返回条目数组。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [ValidateSet('software', 'driver')][string]$Name = 'software'
    )
    $path = Join-Path $Root ("config\{0}-manifest.json" -f $Name)
    $data = Read-KitJson -Path $path
    if ($null -eq $data) { return @() }
    return @($data)
}

function Write-KitLog {
    <#
    .SYNOPSIS
      写入日志到 07_Logs 下的按日期与组件命名的日志文件，同时在控制台输出。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')][string]$Level = 'INFO',
        [string]$Component = 'InstallKit'
    )

    $logDir = Join-Path $Root '07_Logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $file = Join-Path $logDir ("{0}-{1}.log" -f (Get-Date -Format 'yyyyMMdd'), $Component)
    $line = "{0} | {1,-7} | {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message

    Add-Content -LiteralPath $file -Value $line -Encoding UTF8

    switch ($Level) {
        'ERROR'   { Write-Host $line -ForegroundColor Red }
        'WARN'    { Write-Host $line -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $line -ForegroundColor Green }
        default   { Write-Host $line }
    }
}

function Test-KitAdmin {
    <#
    .SYNOPSIS
      判断当前进程是否以管理员身份运行。
    #>
    [CmdletBinding()]
    param()
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-KitSha256 {
    <#
    .SYNOPSIS
      计算文件 SHA-256（小写十六进制）；文件不存在返回 $null。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
}

function Resolve-KitPath {
    <#
    .SYNOPSIS
      将清单中的相对路径拼接为绝对路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath
    )
    return (Join-Path $Root ($RelativePath -replace '/', '\'))
}

function ConvertTo-KitJson {
    <#
    .SYNOPSIS
      将对象序列化为可读 JSON 文本（UTF-8 无 BOM，中文不转义）。
    .DESCRIPTION
      Windows PowerShell 5.1 的 ConvertTo-Json 会把非 ASCII 字符转义为 \uXXXX，
      此处还原为可读中文，避免清单文件出现大量转义序列。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$InputObject,
        [int]$Depth = 10
    )
    $json = $InputObject | ConvertTo-Json -Depth $Depth
    return [regex]::Replace($json, '\\u([0-9a-fA-F]{4})', {
            param($m) [char][int]('0x' + $m.Groups[1].Value)
        })
}

function Save-KitJson {
    <#
    .SYNOPSIS
      将对象写入 JSON 文件（UTF-8 无 BOM）。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$InputObject,
        [int]$Depth = 10
    )
    $text = ConvertTo-KitJson -InputObject $InputObject -Depth $Depth
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $text, $utf8NoBom)
}

function Install-KitItem {
    <#
    .SYNOPSIS
      安装清单中的单个条目（含存在性检查、SHA-256 校验、重复执行保护）。
    .DESCRIPTION
      只处理 EXE / MSI 类型；ZIP 视为免安装；INF 交由驱动脚本处理。
      返回结果对象：Id / Action / ExitCode / Result / RestartRequired。
      模拟执行（-DryRun）时只输出将执行的命令，不实际调用安装程序。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Item,
        [switch]$DryRun,
        [switch]$Force,
        [string]$Component = 'Install'
    )

    $result = [pscustomobject]@{
        Id = $Item.id; Action = 'none'; ExitCode = $null; Result = 'pending'; RestartRequired = $false
    }
    $full = Resolve-KitPath -Root $Root -RelativePath $Item.local_path

    # 重复执行保护：清单已标记已安装则跳过
    if ($Item.status -eq 'installed' -and -not $Force) {
        Write-KitLog -Root $Root -Component $Component -Message "跳过（已安装）：$($Item.id)"
        $result.Action = 'skip'; $result.ExitCode = 0; $result.Result = 'already-installed'
        return $result
    }

    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        Write-KitLog -Root $Root -Component $Component -Level ERROR -Message "安装包缺失，跳过：$($Item.local_path)"
        $result.Action = 'abort'; $result.Result = 'package-missing'
        return $result
    }

    # SHA-256 校验：清单已登记校验值时强制比对
    if (-not [string]::IsNullOrWhiteSpace($Item.sha256)) {
        $hash = Get-KitSha256 -Path $full
        if ($hash -ne $Item.sha256.ToLower()) {
            Write-KitLog -Root $Root -Component $Component -Level ERROR -Message "SHA-256 校验失败，拒绝安装：$($Item.id)（实际 $hash）"
            $result.Action = 'abort'; $result.Result = 'hash-mismatch'
            return $result
        }
    }

    if ($Item.installer_type -eq 'ZIP') {
        # 免安装包解压到 ZIP 同级目录下（文件同名去掉扩展名），开箱即用
        $zipItem = Get-Item -LiteralPath $full
        $destDir = Join-Path $zipItem.DirectoryName ([System.IO.Path]::GetFileNameWithoutExtension($zipItem.Name))
        if ($DryRun) {
            Write-KitLog -Root $Root -Component $Component -Message ("[模拟] 将解压 ZIP 到：{0}" -f $destDir)
            $result.Action = 'dry-run'; $result.Result = 'simulated'; return $result
        }
        try {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Expand-Archive -LiteralPath $full -DestinationPath $destDir -Force
            $fileCount = (Get-ChildItem -LiteralPath $destDir -Recurse -File | Measure-Object).Count
            Write-KitLog -Root $Root -Component $Component -Level SUCCESS -Message "解压成功：$($Item.id) -> $destDir（共 $fileCount 个文件）"
            $result.Action = 'extract'; $result.ExitCode = 0; $result.Result = 'success'
        } catch {
            Write-KitLog -Root $Root -Component $Component -Level ERROR -Message "解压失败：$($Item.id)，$($_.Exception.Message)"
            $result.Action = 'extract'; $result.Result = 'error'
        }
        return $result
    }

    # 自解压型安装包（如 DirectX June 2010 运行时）：
    # 官方分发文件本身是自解压程序，无法直接以静默参数安装，须先静默解压到临时目录，
    # 再执行目录内的安装程序。两步均使用 -Wait，确保解压完成后再安装。
    if (-not [string]::IsNullOrWhiteSpace($Item.extract_args)) {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("InstallKit-{0}" -f $Item.id)
        # 用引号包裹解压目标目录，避免路径含空格时参数被拆断
        $extractArgString = $Item.extract_args -replace '\{dest\}', "`"$tempDir`""
        $innerExe = Join-Path $tempDir $Item.inner_exe
        $innerArgs = @()
        if ($Item.inner_args) { $innerArgs = @($Item.inner_args -split '\s+' | Where-Object { $_ }) }

        if ($DryRun) {
            Write-KitLog -Root $Root -Component $Component -Message ("[模拟] 将执行：{0} {1}，随后执行 {2} {3}" -f $full, $extractArgString, $innerExe, ($innerArgs -join ' '))
            $result.Action = 'dry-run'; $result.Result = 'simulated'
            return $result
        }

        Write-KitLog -Root $Root -Component $Component -Message "开始安装（自解压）：$($Item.name)"
        $startTime = Get-Date
        try {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            $extractProc = Start-Process -FilePath $full -ArgumentList $extractArgString -Wait -PassThru -ErrorAction Stop
            if ($extractProc.ExitCode -ne 0) { throw "解压失败，退出码 $($extractProc.ExitCode)" }
            if (-not (Test-Path -LiteralPath $innerExe)) { throw "解压后未找到内部安装程序：$innerExe" }

            $installProc = Start-Process -FilePath $innerExe -ArgumentList $innerArgs -Wait -PassThru -ErrorAction Stop
            $code = $installProc.ExitCode
            $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
            # 0 成功；3010 成功且需重启；1641 已发起重启
            if ($code -in 0, 3010, 1641) {
                $result.Action = 'install'; $result.ExitCode = $code; $result.Result = 'success'
                if ($code -in 3010, 1641) { $result.RestartRequired = $true }
                Write-KitLog -Root $Root -Component $Component -Level SUCCESS -Message "安装成功：$($Item.id)，退出码 $code，耗时 ${elapsed}s"
            } else {
                $result.Action = 'install'; $result.ExitCode = $code; $result.Result = 'failed'
                Write-KitLog -Root $Root -Component $Component -Level ERROR -Message "安装失败：$($Item.id)，退出码 $code，耗时 ${elapsed}s"
            }
        } catch {
            $result.Action = 'install'; $result.Result = 'error'
            Write-KitLog -Root $Root -Component $Component -Level ERROR -Message "安装异常：$($Item.id)，$($_.Exception.Message)"
        } finally {
            if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
        }
        return $result
    }

    # 组装安装命令
    $argList = @()
    if ($Item.silent_args) { $argList = @($Item.silent_args -split '\s+' | Where-Object { $_ }) }

    if ($Item.installer_type -eq 'MSI') {
        $file = 'msiexec.exe'
        if ($argList.Count -eq 0 -or $argList[0] -ne '/i') { $argList = @('/i') + $argList }
        # msiexec 需要安装包路径紧跟 /i 之后，其余静默参数接在其后
        $rest = @()
        if ($argList.Count -gt 1) { $rest = @($argList[1..($argList.Count - 1)] | Where-Object { $_ }) }
        $argList = @($argList[0], "`"$full`"") + $rest
    } else {
        $file = $full
    }

    $cmdText = "$file $($argList -join ' ')"
    if ($DryRun) {
        Write-KitLog -Root $Root -Component $Component -Message "[模拟] 将执行：$cmdText"
        $result.Action = 'dry-run'; $result.Result = 'simulated'
        return $result
    }

    Write-KitLog -Root $Root -Component $Component -Message "开始安装：$($Item.name)"
    $startTime = Get-Date
    try {
        $proc = Start-Process -FilePath $file -ArgumentList $argList -Wait -PassThru -ErrorAction Stop
        $code = $proc.ExitCode
        $endTime = Get-Date
        $elapsed = [int]($endTime - $startTime).TotalSeconds
        # 0 成功；3010 成功且需重启；1641 已发起重启
        if ($code -in 0, 3010, 1641) {
            $result.Action = 'install'; $result.ExitCode = $code; $result.Result = 'success'
            if ($code -in 3010, 1641) { $result.RestartRequired = $true }
            Write-KitLog -Root $Root -Component $Component -Level SUCCESS -Message "安装成功：$($Item.id)，退出码 $code，耗时 ${elapsed}s"
        } else {
            $result.Action = 'install'; $result.ExitCode = $code; $result.Result = 'failed'
            Write-KitLog -Root $Root -Component $Component -Level ERROR -Message "安装失败：$($Item.id)，退出码 $code，耗时 ${elapsed}s"
        }
    } catch {
        $result.Action = 'install'; $result.Result = 'error'
        Write-KitLog -Root $Root -Component $Component -Level ERROR -Message "安装异常：$($Item.id)，$($_.Exception.Message)"
    }
    return $result
}
