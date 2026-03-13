# AGENTS.md

本文件用于指导 Claude Code / Codex / 其他 AI coding agent 在本仓库执行自动化运维任务。

## 目标

把 OpenClaw 运行在 Mem0 第一记忆源模式：

1. 强制记忆写入（message_received -> memory/add）
2. 强制记忆检索（before_prompt_build -> memory/search）
3. 强制问答回写（agent_end -> memory/add）

## 关键路径

- 完整教程：`OPENCLAW_MEM0_部署与记忆优化全流程手册.md`
- 快速总览：`README.md`
- 部署脚本：
  - Linux: `deploy/linux/one_click.sh`
  - macOS: `deploy/macos/one_click.sh`
  - Windows: `deploy/windows/one_click.ps1`

## 代理执行优先顺序

1. 先备份：`~/.openclaw`、`mem0-local`、OpenClaw 安装目录（若存在）
2. 检查服务状态：`ensure-swap-4g.service`、`openclaw-gateway.service`、`mem0-local.service`
3. 验证配置：
   - OpenClaw: `~/.openclaw/openclaw.json`
   - Mem0: `/root/mem0-local/.env`
4. 验证链路：
   - `GET /health`
   - `POST /memory/add`
   - `POST /memory/search`
5. 查看日志：
   - `journalctl -u openclaw-gateway.service -n 200 --no-pager`
   - `journalctl -u mem0-local.service -n 200 --no-pager`

## 必须遵守

1. 不得提交真实密钥到仓库。
2. 不得把 `plugins.slots.memory` 设置为 `mem0-hub`（应为 `none`）。
3. 不得恢复旧 memory tool 路径（`memory_search/memory_get/memory_add`）。
4. 低配机器默认并发必须保守（workers=1, maxConcurrent=1）。
5. 对一键脚本先 dry-run 说明改动，再执行。

## 常见问题判定

- 若出现 `node:sqlite` 报错：优先判定为旧 memory 工具链误触发。
- 若 `/new` 后失忆：优先检查 `user_id` 映射漂移。
- 若 `addTimeoutMs` 校验失败：检查是否 > 30000。

## 输出格式要求

代理输出需包含：

1. 当前状态（通过/失败）
2. 失败原因（按严重度）
3. 可执行修复命令
4. 验证步骤
