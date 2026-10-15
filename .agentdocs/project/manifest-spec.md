# 清单与配置字段规范

资源库包含三份配置文件，均位于资源根目录的 `config` 下。

## 一、software-manifest.json

管理软件、运行库与工具类资源。顶层为数组，每个条目字段如下：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| id | string | 是 | 唯一标识，建议小写短横线拼接（如 `vcredist-x64`） |
| name | string | 是 | 软件名称 |
| category | string | 是 | 类别：`runtime` / `tool` / `driver` / `application` |
| version | string | 是 | 版本号 |
| architecture | string | 是 | `x64` / `x86` / `Arm64` / `Any` |
| official_url | string | 是 | 官方下载地址或官方发布页面 |
| local_path | string | 是 | 相对资源根目录的本地安装包路径 |
| installer_type | string | 是 | `EXE` / `MSI` / `MSU` / `INF` / `ZIP` |
| silent_args | string | 否 | 经官方文档确认的静默安装参数 |
| sha256 | string | 否 | 文件校验值（小写十六进制）；未知时留空 |
| requires_admin | bool | 是 | 是否需要管理员权限 |
| install_order | int | 是 | 建议安装顺序，升序执行 |
| optional | bool | 是 | 是否可选安装 |
| status | string | 是 | `pending` / `verified` / `installed` / `failed` |

## 二、driver-manifest.json

管理驱动类资源，并记录硬件匹配信息。字段在 software-manifest.json 基础上增加：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| vendor | string | 是 | 厂商（如 Intel、Realtek） |
| device_type | string | 是 | `Ethernet` / `WiFi` / `Bluetooth` / `Chipset` / `GPU` / `Audio` / `Storage` / `Other` |
| hardware_ids | string[] | 否 | 适用的硬件 ID（PnP ID），用于匹配设备 |
| supported_os | string[] | 否 | 适用 Windows 版本与构建号 |
| signature_verified | bool | 否 | 是否已校验驱动签名 |
| risk_level | string | 是 | `low` / `medium` / `high`（存储、启动关键驱动标记为 `high`） |

## 三、settings.json

记录运行环境与路径约定：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| library_root | string | 资源根目录绝对路径 |
| download_cache | string | 下载暂存目录，默认 `08_DownloadCache` |
| log_dir | string | 日志目录，默认 `07_Logs` |
| report_dir | string | 报告目录，默认 `09_Reports` |
| dry_run_default | bool | 是否默认模拟执行，建议 `true` |
| log_retention_days | int | 日志保留天数 |
| target_arch | string | 目标架构，默认 `x64` |

## 四、通用约束

- 敏感配置不得保存密码、激活密钥或其他凭据。
- 清单中的下载地址与安装参数必须经过验证，不得由脚本猜测。
- 新增条目在未计算校验值前 `status` 保持 `pending`，校验通过后改为 `verified`。
