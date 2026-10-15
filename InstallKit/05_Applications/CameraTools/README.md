# 索尼相机连电脑直播 — 通用手册

适用机型：A6400 / A7C / ZV-E10 / A7M4（各机型差异见对应子目录）。

> 本手册记录**索尼 UVC / USB Streaming 通用流程**，所有机型共用。机型特定设置路径、固件差异、HDMI vs USB 直播取舍，请到对应机型子目录（`A6400/` / `A7C/` / `ZV-E10/` / `A7M4/`）的 README 里按真机核对后补齐。

---

## 一、整体方案选型

索尼无反相机做抖音直播，有两条路：

| 方案 | 路径 | 画质 | 延迟 | 推荐场景 |
| --- | --- | --- | --- | --- |
| **A. USB Streaming（UVC）** | 相机 → USB-C → 电脑，作为 USB 摄像头被识别 | 中等（通常 1080p30，部分机型 4K30） | 极低 | 桌面直播、对口型、虚拟背景方便 |
| **B. HDMI 采集卡** | 相机 → HDMI → 采集卡（如 Elgato Cam Link）→ USB → 电脑 | 最高（可传相机原始 HDMI 输出） | 低 | 移动直播、户外、高画质要求 |

本资源库覆盖 **方案 A（UVC）** 的软件栈。HDMI 采集卡方案不在本资源库范围内。

## 二、所需软件（全部放 `03_Runtime` / `05_Applications` 目录）

| 组件 | 来源 | 说明 |
| --- | --- | --- |
| **Sony Imaging Edge Desktop** | 官方 | 驱动 + 远程控制 + Webcam 模式，**安装后会自动注入 UVC 驱动** |
| **OBS Studio** | 官方 | 直播主程序，支持捕捉 UVC 摄像头并推流到抖音 RTMP |

> Sony Imaging Edge Desktop 的内置驱动安装后，Windows 10/11 的设备管理器会多出一个"索尼 USB 视频设备"（UVC），OBS 能直接作为视频源捕捉。

## 三、准备步骤（通用）

### 3.1 电脑端

1. 执行 `Start-Setup.bat` 把 VC++ / DirectX / .NET 8 / 7-Zip / OBS / Sony Imaging Edge Desktop 装完。
2. 重启电脑（Sony Imaging Edge Desktop 驱动安装后建议重启一次）。
3. 打开 `04_Tools\Diagnostics\KeyboardMouseTest\CameraTest\index.html`，点"开始检测"，确认浏览器能枚举到 UVC 设备。
4. 打开 OBS，在"添加源 → 视频采集设备"里看是否能选到索尼相机。

### 3.2 相机端（USB Streaming 通用开启步骤）

> **机型差异提醒**：索尼不同代机器的菜单位置不完全一致。以下路径以 2024 年主流固件为基准，真机核对后把差异写到对应机型子目录。

1. 相机用原装（或兼容的）USB-C 线连电脑（USB 3.x 口优先）。
2. 打开相机菜单 → **Setup（设置）页** → 找到 **USB Connection / USB 连接**：
   - 选项一：`PC Remote Function / PC 远程功能`（较新型号）
   - 选项二：`USB Streaming / USB 串流`（部分型号）
   - 选项三：`MTP Transfer / MTP 传输`（老型号也能用 UVC）
   - 不要选 "Mass Storage / 大容量存储"（只会读 SD 卡，不会出视频）
3. 回到相机菜单 → **Movie / 视频设置**页：
   - 拍摄模式切换到 **Movie / 视频模式**（不是 Photo / 拍照模式），否则 USB Streaming 不出画面
   - 帧率选 30p（抖音直播主流；部分机型 60p 可用但占用带宽更大）
   - 分辨率 1920x1080（UVC 主流上限；4K30 只有部分机型支持）
4. 回到相机菜单 → **Setup 页 → HDMI 设置**（USB Streaming 方案下 HDMI 不开、不影响）。
5. 相机上电开机 → 切到视频模式 → USB 连上。电脑会听到新设备接入声；Sony Imaging Edge Desktop 打开应能识别。

### 3.3 OBS 捕捉与抖音推流

1. 打开 OBS Studio → 新建场景（或用默认）。
2. 右键"来源" → 添加 → **视频采集设备** → 选择索尼相机对应的 UVC 设备名。
3. 右键视频源 → 属性 → 分辨率选择相机在 USB Streaming 里设置的 1080p/30fps。
4. 设置 → 输出 → 直播：
   - 输出模式：高级
   - 编码：x264（软件编码，稳定）或 NVENC / QSV（硬件编码，省电）
   - 分辨率：1920x1080
   - 帧率：30
   - 比特率：4000-6000 Kbps（抖音推荐区间）
   - 关键帧间隔：2 秒
5. **设置 → 流**：
   - 服务：自定义
   - 服务器：从抖音直播中心拿到的 RTMP 推流地址（形如 `rtmp://live-push.byte...live/`）
   - 串流密钥：抖音给的 Stream Key
6. 点"开始直播"。

## 四、相机测试工具

打开 `05_Applications/CameraTools/CameraTest/启动相机测试.bat`：

- **设备枚举**：列出所有摄像头 / 麦克风设备，核对系统是否识别到索尼 UVC
- **摄像头预览**：实时画面 + fps + 分辨率，画面卡住 → 相机端没切到视频模式或 USB 线接反
- **麦克风音量条**：实时看音量反应 → 话筒链路正常
- **录音回放**：录 5 秒再放一遍 → 确认编码 / 解码器完整

## 五、常见问题

| 现象 | 排查 |
| --- | --- |
| OBS 里看不到索尼相机 | ① 相机菜单 USB Connection 是否选了 PC Remote 或 USB Streaming？② 相机是否切到视频模式？③ USB 3 线是否插紧？④ Sony Imaging Edge Desktop 是否安装并重启过？ |
| OBS 能选到但画面黑 | 相机是否开机 + 切到视频模式了？相机内存卡是否已正确插入？ |
| 画面 10-20fps，卡 | 相机视频设置是不是 60p？电脑 USB 是不是 2.0 口（带宽不够）？ |
| 麦克风不工作 | 索尼 UVC 部分机型自带麦克风（选 USB Streaming 时同时出音轨），部分型号不出音轨。如果 OBS 里能找到但音量条不动 → 相机端关闭了内部话筒或选了其他音频源 |
| 推流后抖音里画面花屏 | OBS 里视频源属性 → 格式改成 NV12 或 MJPEG 试试 |

---

## 机型差异待核对清单（按真机填写，存各机型子目录的 README.md）

每个机型需要在对应子目录的 README 里按真机补齐：

1. 菜单位置：USB Connection、USB Streaming、Movie 模式切换的**精确菜单路径 + 图片**
2. USB Streaming 支持的最大分辨率 / 帧率
3. 自带麦克风是否跟随 UVC 输出
4. HDMI 输出在 USB Streaming 开启时是否还能用（某些机型会互斥）
5. 固件版本差异（某版本之前/之后菜单位置变了）
6. 已验证可行的 USB 线型号（有些 Type-C 线只传电不传数据）

### 机型目录

- [A6400 README](./A6400/README.md)
- [A7C README](./A7C/README.md)
- [ZV-E10 README](./ZV-E10/README.md)
- [A7M4 README](./A7M4/README.md)
