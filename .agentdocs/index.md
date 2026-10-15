# 文档索引（.agentdocs/index.md）

本目录仅面向 AI 代理，沉淀本项目的架构、领域边界、约定与历史决策，帮助快速获取全局上下文，避免重复遍历代码。面向人类的说明见根目录 `readme.md`。

## 使用方式

1. 处理任务前先读本索引，定位需要了解的文档。
2. 修改代码前，先读「编码标准」下的规则。
3. 涉及盘符识别、清单字段、安装安全等设计问题前，先读对应「项目文档」或「架构决策」。
4. 新增文档必须在本索引中归类登记；已有相关文档时优先更新，不新建。

## 项目文档

| 文档 | 说明 |
| --- | --- |
| [project/overview.md](project/overview.md) | 项目目标、分层架构、执行流程、范围边界与安全原则 |
| [project/directory-layout.md](project/directory-layout.md) | 装机硬盘目录结构与资源根目录识别约定 |
| [project/manifest-spec.md](project/manifest-spec.md) | software-manifest.json / driver-manifest.json / settings.json 字段规范 |

## 编码标准

| 文档 | 说明 |
| --- | --- |
| [rules/powershell-style.md](rules/powershell-style.md) | PowerShell 脚本命名、参数、日志、错误处理与安全规则 |

## 架构决策（ADR）

| 文档 | 说明 |
| --- | --- |
| [decisions/ADR-001-resource-root-detection.md](decisions/ADR-001-resource-root-detection.md) | 资源根目录不写死盘符，按标记文件自动识别 |
| [decisions/ADR-002-prepare-only-first.md](decisions/ADR-002-prepare-only-first.md) | 第一阶段只准备资源，默认模拟执行，不自动修改系统 |

## 当前任务文档

| 文档 | 状态 |
| --- | --- |
| [workflow/251015-installkit-mvp.md](workflow/251015-installkit-mvp.md) | 进行中：MVP 资源准备与检测脚本 |

## 已完成任务

存放于 `workflow/done/`，暂无。
