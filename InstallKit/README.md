# InstallKit 使用说明

Windows 11 纯净装机资源库。用于系统重装后的驱动、运行库与基础软件准备和安装。

- 资源根目录：本目录（可用 `-Root` 指定，脚本按 `config\settings.json` 自动识别，不写死盘符）。
- 设计原则：优先官方来源、SHA-256 校验、可重复执行、风险操作需人工确认。
- 当前阶段：**第一阶段只准备资源，不自动修改系统**；安装类脚本默认模拟执行。

## 一、目录结构

```text
InstallKit
├── config                     清单与配置
│   ├── software-manifest.json  软件与运行库清单
│   ├── driver-manifest.json    驱动清单
│   └── settings.json           全局设置（根目录、日志、DryRun 默认值等）
├── 00_System                   系统镜像与启动盘说明
├── 01_Network                  网卡与蓝牙驱动（优先准备）
├── 02_Drivers                  芯片组/显卡/声卡/存储等驱动
├── 03_Runtime                  Visual C++ / DirectX / .NET 运行库
├── 04_Tools                    解压、浏览器、终端、诊断工具
├── 05_Applications             其他应用
├── 06_Scripts                  全部 PowerShell 脚本与报告模板
├── 07_Logs                     运行日志
├── 08_DownloadCache            下载暂存
└── 09_Reports                  结果报告
```

## 二、准备资源

1. 将 Windows ISO 放入 `00_System\WindowsISO`。
2. 按官方页面下载清单中登记的安装包，放到 `local_path` 指定的位置。
3. 编辑 `config\software-manifest.json`，补充版本号、官方地址与 SHA-256。
4. 运行准备脚本，自动建目录、扫描安装包并回填 SHA-256：

```powershell
# 模拟执行（默认，不写文件）
.\06_Scripts\Initialize-InstallKit.ps1

# 真实执行：建立目录、回写清单、生成报告
.\06_Scripts\Initialize-InstallKit.ps1 -DryRun:$false
```

## 三、执行脚本

统一入口（推荐）：

```powershell
# 模拟执行全部步骤并生成计划
.\06_Scripts\Start-Setup.ps1

# 真实执行（需管理员 + 输入 YES 确认；settings 中 dry_run_default=true 时需再加 -Force）
.\06_Scripts\Start-Setup.ps1 -Execute -Force
```

单步执行：

```powershell
.\06_Scripts\Check-System.ps1                              # 系统环境检查
.\06_Scripts\Check-Network.ps1                             # 网络检查
.\06_Scripts\Update-Drivers.ps1                            # 驱动检测（不覆盖）
.\06_Scripts\Install-Runtimes.ps1                          # 运行库（默认模拟）
.\06_Scripts\Install-Runtimes.ps1 -DryRun:$false           # 真实安装运行库
.\06_Scripts\Install-Tools.ps1 -Id 7zip-x64 -Retry         # 单项安装并重试
```

参数说明：`-Root` 指定根目录；`-DryRun` 模拟执行（默认按 settings 取值）；`-Id` 仅处理指定条目；`-Force` 忽略“已安装”跳过标记或确认约束。

## 四、排查失败

1. 查看 `07_Logs\YYYYMMDD-<组件>.log`，定位失败条目与退出码。
2. 查看 `09_Reports` 下对应报告，确认包是否就位、SHA-256 是否匹配。
3. 常见原因：
   - 安装包缺失 → 按清单 `local_path` 补齐文件后重跑。
   - SHA-256 不匹配 → 从官方渠道重新下载，勿使用第三方来源。
   - 退出码非 0/3010/1641 → 查阅该软件官方文档的静默参数。
   - 无网络 → 先装 `01_Network` 下的离线网卡驱动。
4. 修复后重跑即可：脚本对已标记 `installed` 的条目自动跳过。

## 五、更新安装包

1. 从官方页面下载新版本到 `08_DownloadCache`。
2. 计算并核对 SHA-256，确认与官方值一致。
3. 更新 `software-manifest.json` 的 `version`、`official_url`、`sha256`、`local_path`，`status` 改回 `pending`。
4. 移动包到正式目录，运行 `Initialize-InstallKit.ps1 -DryRun:$false` 回填校验值。

## 六、验收清单

- [ ] 网络连接正常，可访问官方 HTTPS 站点
- [ ] 设备管理器无未解决的关键设备异常
- [ ] Windows Update 无待处理关键更新（或已记录未完成原因）
- [ ] 必要运行库安装结果正常
- [ ] 安装过程未发生意外重启
- [ ] 全部操作可从 `07_Logs` 与 `09_Reports` 追溯

## 七、安全约定

- 仅使用微软、硬件厂商与软件项目官方来源。
- 不关闭 Windows Defender、UAC 或驱动签名验证。
- 不使用万能驱动包、DLL 合集、破解软件或系统精简工具。
- 清单中的下载地址与静默参数必须经官方文档验证，不得由脚本猜测。
