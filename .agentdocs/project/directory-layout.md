# 装机硬盘目录结构

## 一、资源库根目录

- 本机实际根目录为 `d:\SUIwin1011\InstallKit`。
- 脚本不得写死盘符，必须按「资源根目录识别约定」定位根目录（见下节）。
- 现有两个 Windows ISO 将归档至 `00_System\WindowsISO`（移动大文件，需用户确认后执行）。

## 二、目录树

```text
InstallKit
├── README.md
├── config
│   ├── software-manifest.json
│   ├── driver-manifest.json
│   └── settings.json
├── 00_System
│   ├── WindowsISO
│   └── BootMediaNotes
├── 01_Network
│   ├── Ethernet
│   ├── WiFi
│   └── Bluetooth
├── 02_Drivers
│   ├── Chipset
│   ├── GPU
│   ├── Audio
│   ├── Storage
│   └── Other
├── 03_Runtime
│   ├── VisualCpp
│   │   ├── x64
│   │   └── x86
│   ├── DirectX
│   └── DotNet
├── 04_Tools
│   ├── Archive
│   ├── Browser
│   ├── Terminal
│   └── Diagnostics
├── 05_Applications
├── 06_Scripts
│   ├── Check-System.ps1
│   ├── Check-Network.ps1
│   ├── Install-Runtimes.ps1
│   ├── Install-Tools.ps1
│   ├── Update-Drivers.ps1
│   └── Start-Setup.ps1
├── 07_Logs
├── 08_DownloadCache
└── 09_Reports
```

## 三、资源根目录识别约定

1. 根目录标记文件为 `config\settings.json`：凡包含该文件的目录即视为资源库根。
2. 识别顺序：
   - 优先使用命令行显式参数（如 `-Root`）。
   - 其次使用 `settings.json` 中记录的 `library_root`。
   - 最后按脚本所在目录向上回溯，找到含 `config\settings.json` 的目录。
3. 若三种方式均未命中，脚本应报错并提示用户指定根目录，不得继续执行。
4. 目录仅作为初始规划，新建目录时不得影响已有文件。

## 四、命名与存放约定

- 驱动按类别存放于 `02_Drivers` 对应子目录；网卡类驱动单独存放于 `01_Network`。
- 运行库按架构分子目录存放（`x64` / `x86`），Arm64 另行区分。
- 下载暂存统一放 `08_DownloadCache`，校验通过后再移动到对应正式目录。
- 日志按日期写入 `07_Logs`，结果报告写入 `09_Reports`。
