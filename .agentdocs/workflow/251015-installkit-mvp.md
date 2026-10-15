# 任务：InstallKit MVP 资源准备与检测

- 创建日期：2026-10-15
- 目标：先实现最小可用版本（MVP）——自动识别装机硬盘、建立目录、生成软件清单、检查安装包、计算 SHA-256、记录日志。第一阶段只准备资源，不自动修改系统。

## 一、现状分析

- 资源根目录现状：`d:\SUIwin1011` 下仅有 `readme.md`、`AGENTS.md` 与两个 Windows ISO，尚无 `InstallKit` 目录结构、配置文件与脚本。
- 交付依据：`readme.md`（架构与脚本要求）、`.agentdocs/project/`（目录与清单规范）、`.agentdocs/decisions/`（根目录识别、模拟执行）。

## 二、阶段与 TODO

### 阶段 1：资源库骨架与清单（已完成）

- [x] 建立 `InstallKit` 目录结构与 `config` 子目录
- [x] 将两个 Windows ISO 归档至 `00_System\WindowsISO`
- [x] 生成 `software-manifest.json`、`driver-manifest.json`、`settings.json` 示例
- [x] 编写 `Check-System.ps1`、`Check-Network.ps1`（纯检测，无系统修改）
- [x] 编写 `Initialize-InstallKit.ps1`：建目录、扫描安装包、计算 SHA-256、回写清单、写日志
- [x] 输出第一阶段「模拟执行」结果并留存日志

### 阶段 2：运行库与工具安装（脚本已就绪，真实安装待确认）

- [x] `Install-Runtimes.ps1`：按清单安装 VC++、DirectX 旧组件、指定 .NET Runtime
- [x] `Install-Tools.ps1`：安装解压工具、浏览器等基础软件（支持 `-Id` 单项与 `-Retry`）
- [x] 两脚本均默认 `-DryRun`，校验 SHA-256，记录退出码与重启提示
- [ ] 用户确认后执行真实安装并归档报告

### 阶段 3：驱动与环境初始化（脚本已就绪，真实执行待确认）

- [x] `Update-Drivers.ps1`：检测、匹配硬件、校验签名、提示高风险，默认不覆盖
- [x] `Start-Setup.ps1`：统一入口，环境检查 → 权限检查 → 识别根目录 → 展示项 → 确认 → 顺序执行 → 出报告
- [x] 报告与日志模板落地（`06_Scripts/templates`）
- [ ] 装机验收清单按实际环境逐项核对

### 阶段 4：一键启动器与离线网卡驱动安装（已完成）

- [x] `Start-Setup.bat`（项目根目录）：UAC 提权 → 资源齐全性检查 → 确认 → 顺序安装
- [x] `Update-Drivers.ps1` 增加 `-Install`：用系统自带 `pnputil` 安装 `01_Network` 下的离线网卡驱动
  （`pnputil /add-driver` 退出码 259=已存在/无需更新，视为成功；重复执行不误报失败）
- [x] `Start-Setup.ps1` 增加 `-InstallDrivers`，保持「前一个装完再装下一个」的顺序执行
- [x] 修复 DirectX 自解压静默安装：`extract_args`/`inner_exe`/`inner_args`（先解压再执行 `DXSETUP.exe /silent`）
- [x] ZIP 条目真实解压：Sysinternals Suite 等免安装包解压到 ZIP 同级同名目录，DryRun 输出目标路径
- [x] `Initialize-InstallKit.ps1` 末尾加 exit 1：关键包（`optional=false`）缺失/校验失败时中止，bat 的 `if errorlevel 1` 真正生效
- [x] 全部脚本语法校验 + 全流程 DryRun 干跑通过（无系统变更）
- [ ] 目标机实机执行（需用户先将官方网卡驱动放入 `01_Network`）

## 三、关键设计约束

- 根目录按标记文件 `config\settings.json` 识别，不写死盘符（见 ADR-001）。
- 第一阶段不修改系统，安装类脚本默认模拟执行（见 ADR-002）。
- 脚本遵守 `.agentdocs/rules/powershell-style.md`。

## 四、验收标准

- 目录结构与规范一致，清单可被脚本解析。
- 检测脚本能在无网络、无网卡驱动的情况下给出明确提示与本地离线方案。
- 同一脚本重复执行不产生重复安装或副作用。
- 所有动作可从 `07_Logs` 与 `09_Reports` 追溯。
