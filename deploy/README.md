# Deploy Scripts

本目录提供跨平台一键部署脚本，目标是直接把 OpenClaw 改造成 Mem0 First 记忆链路。

> ⚠️ 这些脚本尚未覆盖所有系统组合与 OpenClaw 版本，生产环境请先备份再执行。

推荐做法：先把仓库交给 Codex / Claude Code 按“备份 -> dry-run -> 执行 -> 验收 -> 回滚说明”流程运行，不建议直接盲跑脚本。

## 执行前先备份（强烈建议）

1. 备份 `~/.openclaw`
2. 备份 `~/mem0-local`（或 `%USERPROFILE%\\mem0-local`）
3. 备份 OpenClaw 安装目录与配置目录

## Linux

```bash
chmod +x deploy/linux/one_click.sh
KIMI_API_KEY="<YOUR_KIMI_API_KEY>" OPENCLAW_PACKAGE_DIR="/abs/path/to/openclaw/package" bash deploy/linux/one_click.sh
```

## macOS

```bash
chmod +x deploy/macos/one_click.sh
KIMI_API_KEY="<YOUR_KIMI_API_KEY>" OPENCLAW_PACKAGE_DIR="/abs/path/to/openclaw/package" bash deploy/macos/one_click.sh
```

## Windows (PowerShell)

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy\windows\one_click.ps1 -OpenClawPackageDir "C:\path\to\openclaw\package" -KimiApiKey "<YOUR_KIMI_API_KEY>"
```

## 可选飞书参数

- Linux/macOS:

```bash
ENABLE_FEISHU=1 FEISHU_APP_ID="<FEISHU_APP_ID>" FEISHU_APP_SECRET="<FEISHU_APP_SECRET>"
```

- Windows:

```powershell
-EnableFeishu -FeishuAppId "<FEISHU_APP_ID>" -FeishuAppSecret "<FEISHU_APP_SECRET>"
```

## 自动改造文件

1. `~/.openclaw/openclaw.json`
2. `~/.openclaw/extensions/mem0-hub/index.ts`
3. `~/mem0-local/mem0_api.py`（Windows 为 `%USERPROFILE%\\mem0-local\\mem0_api.py`）
