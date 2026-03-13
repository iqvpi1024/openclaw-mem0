#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

function uniquePush(arr, value) {
  if (!value) return;
  if (!arr.includes(value)) arr.push(value);
}

function ensureObject(obj, key) {
  if (!obj[key] || typeof obj[key] !== "object" || Array.isArray(obj[key])) {
    obj[key] = {};
  }
  return obj[key];
}

function ensureArray(obj, key) {
  if (!Array.isArray(obj[key])) {
    obj[key] = [];
  }
  return obj[key];
}

function readJson(filePath) {
  if (!fs.existsSync(filePath)) {
    return {};
  }
  const raw = fs.readFileSync(filePath, "utf8");
  if (!raw.trim()) {
    return {};
  }
  return JSON.parse(raw);
}

function writeJson(filePath, data) {
  const parent = path.dirname(filePath);
  fs.mkdirSync(parent, { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(data, null, 2)}\n`, "utf8");
}

function nowStamp() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

const home = os.homedir();
const openclawHome = process.env.OPENCLAW_HOME || path.join(home, ".openclaw");
const configPath = process.env.OPENCLAW_CONFIG || path.join(openclawHome, "openclaw.json");
const mem0Url = process.env.MEM0_URL || "http://127.0.0.1:8765";
const mem0ExtensionPath = process.env.MEM0_EXTENSION_PATH || path.join(openclawHome, "extensions", "mem0-hub");
const kimiApiKey = process.env.KIMI_API_KEY || "<YOUR_KIMI_API_KEY>";
const feishuAppId = process.env.FEISHU_APP_ID || "";
const feishuAppSecret = process.env.FEISHU_APP_SECRET || "";
const enableFeishu = process.env.ENABLE_FEISHU === "1" || (!!feishuAppId && !!feishuAppSecret);
const agentMaxConcurrent = Number.parseInt(process.env.AGENT_MAX_CONCURRENT || "1", 10);
const addTimeoutMs = Number.parseInt(process.env.MEM0_ADD_TIMEOUT_MS || "30000", 10);
const searchTimeoutMs = Number.parseInt(process.env.MEM0_SEARCH_TIMEOUT_MS || "20000", 10);
const searchLimit = Number.parseInt(process.env.MEM0_SEARCH_LIMIT || "5", 10);

const config = readJson(configPath);

if (fs.existsSync(configPath)) {
  const backupPath = `${configPath}.bak.${nowStamp()}`;
  fs.copyFileSync(configPath, backupPath);
  console.log(`backup: ${backupPath}`);
}

config.meta = config.meta || {};
config.meta.lastTouchedAt = new Date().toISOString();

const models = ensureObject(config, "models");
const providers = ensureObject(models, "providers");
providers.kimicode = {
  baseUrl: "https://api.kimi.com/coding",
  apiKey: kimiApiKey,
  api: "anthropic-messages",
  models: [
    {
      id: "kimi-k2.5",
      name: "Kimi K2.5",
      reasoning: false,
      input: ["text"],
      cost: {
        input: 0,
        output: 0,
        cacheRead: 0,
        cacheWrite: 0,
      },
      contextWindow: 256000,
      maxTokens: 8192,
    },
  ],
};

const agents = ensureObject(config, "agents");
const defaults = ensureObject(agents, "defaults");
defaults.model = {
  primary: "kimicode/kimi-k2.5",
  fallbacks: [],
};
defaults.maxConcurrent = Number.isFinite(agentMaxConcurrent) && agentMaxConcurrent > 0 ? agentMaxConcurrent : 1;
defaults.subagents = {
  ...(typeof defaults.subagents === "object" && defaults.subagents ? defaults.subagents : {}),
  maxConcurrent: Number.isFinite(agentMaxConcurrent) && agentMaxConcurrent > 0 ? agentMaxConcurrent : 1,
};

const tools = ensureObject(config, "tools");
const deny = ensureArray(tools, "deny");
for (const item of ["group:memory", "memory_search", "memory_get", "memory_add"]) {
  uniquePush(deny, item);
}
tools.media = tools.media || { concurrency: 1 };
if (!Number.isFinite(Number(tools.media.concurrency)) || Number(tools.media.concurrency) <= 0) {
  tools.media.concurrency = 1;
}

const plugins = ensureObject(config, "plugins");
const allow = ensureArray(plugins, "allow");
uniquePush(allow, "mem0-hub");
if (enableFeishu) uniquePush(allow, "feishu");

const load = ensureObject(plugins, "load");
const paths = ensureArray(load, "paths");
uniquePush(paths, mem0ExtensionPath);

plugins.slots = plugins.slots || {};
plugins.slots.memory = "none";

const entries = ensureObject(plugins, "entries");
entries["mem0-hub"] = {
  enabled: true,
  config: {
    mem0Url,
    searchLimit: Number.isFinite(searchLimit) && searchLimit > 0 ? searchLimit : 5,
    addTimeoutMs: Math.min(Math.max(addTimeoutMs, 1000), 30000),
    searchTimeoutMs: Math.max(searchTimeoutMs, 1000),
    semanticPrompt:
      "请提炼输入中的核心知识点、用户偏好、任务规则和关键约束，形成可长期检索的简洁记忆。",
  },
};

if (enableFeishu) {
  const channels = ensureObject(config, "channels");
  channels.feishu = {
    enabled: true,
    connectionMode: "websocket",
    defaultAccount: "main",
    accounts: {
      main: {
        enabled: true,
        appId: feishuAppId || "<FEISHU_APP_ID>",
        appSecret: feishuAppSecret || "<FEISHU_APP_SECRET>",
        domain: "feishu",
      },
    },
  };

  entries.feishu = {
    ...(typeof entries.feishu === "object" && entries.feishu ? entries.feishu : {}),
    enabled: true,
  };
}

if (!config.gateway || typeof config.gateway !== "object") {
  config.gateway = {};
}
config.gateway.port = Number.parseInt(process.env.OPENCLAW_GATEWAY_PORT || `${config.gateway.port || 18789}`, 10) || 18789;
config.gateway.mode = config.gateway.mode || "local";
config.gateway.bind = config.gateway.bind || "loopback";
if (!config.gateway.auth || typeof config.gateway.auth !== "object") {
  config.gateway.auth = { mode: "none" };
}

writeJson(configPath, config);
console.log(`patched: ${configPath}`);
console.log(`mem0 url: ${mem0Url}`);
console.log(`feishu enabled: ${enableFeishu ? "yes" : "no"}`);
