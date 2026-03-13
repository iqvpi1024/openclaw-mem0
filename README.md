# OpenClaw-Mem0: OpenClaw 记忆增强终极方案（Mem0 First）

<p align="center">
  <a href="https://github.com/iqvpi1024/openclaw-mem0/stargazers">
    <img src="https://img.shields.io/github/stars/iqvpi1024/openclaw-mem0?style=for-the-badge" alt="GitHub stars" />
  </a>
  <a href="https://github.com/iqvpi1024/openclaw-mem0/network/members">
    <img src="https://img.shields.io/github/forks/iqvpi1024/openclaw-mem0?style=for-the-badge" alt="GitHub forks" />
  </a>
  <a href="https://github.com/iqvpi1024/openclaw-mem0/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/iqvpi1024/openclaw-mem0?style=for-the-badge" alt="License" />
  </a>
  <img src="https://img.shields.io/badge/OpenClaw-Mem0%20Primary-orange?style=for-the-badge" alt="Mem0 Primary" />
  <img src="https://img.shields.io/badge/Embedding-BAAI%2Fbge--large--zh--v1.5-purple?style=for-the-badge" alt="BGE" />
</p>

> 一句话：把 OpenClaw 从“会话记忆”升级成“Mem0 第一记忆源”，让记忆检索和回写变成后端强制动作。

## 痛点暴击

| 场景 | 传统 OpenClaw（依赖 `soul.md`/上下文） | 本项目（Mem0 第一记忆源） |
|---|---|---|
| 😵 `/new` 后连续性 | 经常像失忆，历史事实断档 | 强制先检索 Mem0，再回答 |
| 🧠 记忆持久化 | 主要靠文件或会话上下文 | 用户输入 + 模型回答双向回写 |
| 🧩 语义理解 | 文本堆积，检索弱 | 向量语义检索（`bge-large-zh-v1.5`） |
| 🔁 多端同步 | Mac / Linux / 飞书记忆割裂 | 统一 `user_id` 可跨端共享同一记忆 |
| ⚙️ 可扩展性 | 检索链路与模型链路耦合重 | 可按场景拆分为中心 Mem0 + 多节点 OpenClaw |

## 架构揭秘

```mermaid
flowchart LR
    A[Feishu / CLI / API] --> B[OpenClaw Gateway]
    B --> C[mem0-hub 插件]
    C --> D[Mem0 API - FastAPI]
    D --> E[本地向量存储/Qdrant]
    B --> F[Kimi K2.5]
```

核心机制：

1. 拦截 `message_received`，异步写入 Mem0（语义提炼后存储）。
2. 拦截 `before_prompt_build`，强制检索 Mem0 并注入 `[历史记忆：...]`。
3. 拦截 `agent_end`，把“用户问题 + AI回答”持续回写 Mem0。
4. 禁用旧 memory tools，避免走 `node:sqlite` 老路径。

## 为什么支持多环境共享记忆

可以实现，而且是本方案的重点能力。

前提只有 3 条：

1. 多个 OpenClaw 指向同一个 Mem0 后端（或本地 sidecar 转发到中心 Mem0）。
2. 全节点统一 embedding 模型版本（`BAAI/bge-large-zh-v1.5`）。
3. 全节点统一 `user_id` 归一化规则（例如 `tenant:acme:user:user001`）。

这样你在 Mac 说过的话，Linux 上新会话也能被召回。

## 给 Claude Code / Codex 的直接执行方式

把下面这段直接贴给你的智能编码代理（在仓库根目录执行）：

```text
请阅读当前仓库 README.md 与 OPENCLAW_MEM0_部署与记忆优化全流程手册.md，
按文档完成以下动作：
1) 检查 openclaw + mem0 服务状态
2) 校验 openclaw.json / mem0 .env 的关键配置项
3) 执行记忆写入与检索验收命令
4) 输出当前问题与修复建议（按严重程度排序）
```

这套文档就是按“AI 代理可直接执行”的结构写的，不需要二次整理。

## 一键部署（Linux / macOS / Windows）

脚本会自动完成：

1. 部署 Mem0 Local API（FastAPI + 向量存储）
2. 注入 `mem0-hub` 插件到 OpenClaw 扩展目录
3. 自动改写 `openclaw.json`（强制 Mem0 First）
4. 启动服务（Linux: systemd，macOS/Windows: 运行脚本）

### Linux

```bash
git clone https://github.com/iqvpi1024/openclaw-mem0.git
cd openclaw-mem0
chmod +x deploy/linux/one_click.sh

KIMI_API_KEY="<YOUR_KIMI_API_KEY>" \
OPENCLAW_PACKAGE_DIR="/abs/path/to/openclaw/package" \
bash deploy/linux/one_click.sh
```

可选飞书：

```bash
KIMI_API_KEY="<YOUR_KIMI_API_KEY>" \
OPENCLAW_PACKAGE_DIR="/abs/path/to/openclaw/package" \
ENABLE_FEISHU=1 \
FEISHU_APP_ID="<FEISHU_APP_ID>" \
FEISHU_APP_SECRET="<FEISHU_APP_SECRET>" \
bash deploy/linux/one_click.sh
```

### macOS

```bash
git clone https://github.com/iqvpi1024/openclaw-mem0.git
cd openclaw-mem0
chmod +x deploy/macos/one_click.sh

KIMI_API_KEY="<YOUR_KIMI_API_KEY>" \
OPENCLAW_PACKAGE_DIR="/abs/path/to/openclaw/package" \
bash deploy/macos/one_click.sh
```

### Windows (PowerShell)

```powershell
git clone https://github.com/iqvpi1024/openclaw-mem0.git
cd openclaw-mem0

powershell -ExecutionPolicy Bypass -File .\deploy\windows\one_click.ps1 `
  -OpenClawPackageDir "C:\path\to\openclaw\package" `
  -KimiApiKey "<YOUR_KIMI_API_KEY>"
```

可选飞书：

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy\windows\one_click.ps1 `
  -OpenClawPackageDir "C:\path\to\openclaw\package" `
  -KimiApiKey "<YOUR_KIMI_API_KEY>" `
  -EnableFeishu `
  -FeishuAppId "<FEISHU_APP_ID>" `
  -FeishuAppSecret "<FEISHU_APP_SECRET>"
```

## 脚本会自动修改的底层文件

1. `~/.openclaw/openclaw.json`
2. `~/.openclaw/extensions/mem0-hub/index.ts`
3. `~/mem0-local/mem0_api.py`（Windows 在 `%USERPROFILE%\\mem0-local`）

## 配置模板

`openclaw.json` 关键项：

```json
{
  "models": {
    "providers": {
      "kimicode": {
        "baseUrl": "https://api.kimi.com/coding",
        "apiKey": "<YOUR_KIMI_API_KEY>",
        "api": "anthropic-messages",
        "models": [{ "id": "kimi-k2.5", "contextWindow": 256000, "maxTokens": 8192 }]
      }
    }
  },
  "tools": {
    "deny": ["group:memory", "memory_search", "memory_get", "memory_add"]
  },
  "plugins": {
    "allow": ["mem0-hub", "feishu"],
    "slots": { "memory": "none" },
    "entries": {
      "mem0-hub": {
        "enabled": true,
        "config": {
          "mem0Url": "http://127.0.0.1:8765",
          "searchLimit": 5,
          "addTimeoutMs": 30000,
          "searchTimeoutMs": 20000
        }
      }
    }
  }
}
```

`mem0 .env` 关键项：

```env
OPENAI_API_KEY=<OPENCLAW_GATEWAY_KEY_OR_DUMMY>
OPENAI_BASE_URL=http://127.0.0.1:18789/v1
MEM0_LLM_PROVIDER=openai
MEM0_LLM_MODEL=kimicode/kimi-k2.5
MEM0_EMBEDDER_PROVIDER=huggingface
MEM0_EMBEDDER_MODEL=BAAI/bge-large-zh-v1.5
MEM0_EMBEDDING_DIMS=1024
MEM0_QDRANT_PATH=./data/qdrant-openclaw-v2
MEM0_HISTORY_DB_PATH=./data/history-openclaw-v2.db
MEM0_COLLECTION_NAME=mem0
```

## 高性能部署方案（本地向量模型升级）

如果你的目标是更高吞吐和更强召回质量，建议把 embedding 层独立成服务，并升级模型：

1. 模型选择：
`BAAI/bge-large-zh-v1.5`（当前默认，中文稳定）或 `BAAI/bge-m3`（多语种/长文本更强）。
2. 服务拆分：
OpenClaw、Mem0 API、向量数据库（Qdrant）分开部署，避免单进程争抢资源。
3. 检索参数：
`searchLimit` 建议 `5~8`，并配合结果去重，降低噪声注入。
4. 高性能节点建议：
`8C16G+` 起步，若有 GPU 可将 embedding 推理迁移到 GPU 服务。

示例（切换到 `bge-m3`）：

```env
MEM0_EMBEDDER_PROVIDER=huggingface
MEM0_EMBEDDER_MODEL=BAAI/bge-m3
MEM0_EMBEDDING_DIMS=1024
```

## 验收

```bash
curl -s http://127.0.0.1:8765/health
curl -s -X POST http://127.0.0.1:8765/memory/add -H 'content-type: application/json' -d '{"user_id":"diag-001","text":"我的昵称是测试用户A","infer":false}'
curl -s -X POST http://127.0.0.1:8765/memory/search -H 'content-type: application/json' -d '{"user_id":"diag-001","query":"我的昵称是什么","limit":5}'
```

飞书验证：

1. `/new`
2. `我叫测试用户A，我在做一个自动化项目`
3. `我的项目代号是 Orion，默认回复中文`
4. `我项目代号是什么？默认回复什么语言？`

## 已踩过的坑（你不用再踩）

1. `node:sqlite` 报错不是 Mem0 故障，是旧 memory 工具链问题。
2. `plugins.slots.memory` 不能设成 `mem0-hub`，必须是 `none`。
3. `addTimeoutMs` 超过 `30000` 会导致配置校验失败。
4. `/new` 后“失忆”通常是 `user_id` 漂移，不是数据丢失。

## 文档

- 跨平台脚本说明：[deploy/README.md](./deploy/README.md)
- 完整部署文档：[OPENCLAW_MEM0_部署与记忆优化全流程手册.md](./OPENCLAW_MEM0_部署与记忆优化全流程手册.md)

## Star 支持

如果这个项目帮你把 OpenClaw 从“短期记忆”升级成“长期记忆”，请点一个 Star：

- ⭐ https://github.com/iqvpi1024/openclaw-mem0

## 赞赏区

为了把这套全自动记忆流跑稳，我熬了不少大夜。  
如果这个方案治好了你的 AI 失忆症，或者帮你省下了高配服务器的钱，欢迎请我喝杯咖啡 ☕️，支持我持续维护。

| 微信赞赏 | 支付宝赞赏 |
|---|---|
| ![wechat-donate](./assets/donate/wechat.png) | ![alipay-donate](./assets/donate/alipay.png) |

> 把你的赞赏码图片放到：
> - `assets/donate/wechat.png`
> - `assets/donate/alipay.png`

## License

MIT
