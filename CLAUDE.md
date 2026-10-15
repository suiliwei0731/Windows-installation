# CLAUDE.md

本文件为 Claude 系代理在根目录的入口。项目治理规范的权威来源是 [AGENTS.md](AGENTS.md)，请先阅读。

## 项目简介

面向 Windows 11 纯净装机场景的装机资源库与 PowerShell 自动化脚本（资源准备、检测、安装与更新）。人类向说明见 [readme.md](readme.md)。

## 权威文档

- 治理规范与硬规则：[AGENTS.md](AGENTS.md)
- 项目文档与技术约定索引：[.agentdocs/index.md](.agentdocs/index.md)

## 必须遵守的要点

- 默认使用中文沟通，文档与代码注释均使用中文。
- 修改代码前先给出可选方案并等待确认；未经确认不进行实质性写入、删除、迁移、重构。
- 需求不明确时先提问，不要猜测意图。
- 复杂任务先建任务文档（`.agentdocs/workflow/`），分阶段推进并更新 TODO。
- 不覆盖、回滚或污染用户已有未提交改动。
- 第一阶段只准备资源，安装类脚本默认模拟执行（DryRun），不自动修改系统。
