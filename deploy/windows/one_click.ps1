param(
  [string]$OpenClawPackageDir = "",
  [string]$OpenClawHome = "$env:USERPROFILE\.openclaw",
  [string]$Mem0Dir = "$env:USERPROFILE\mem0-local",
  [int]$Mem0Port = 8765,
  [int]$OpenClawGatewayPort = 18789,
  [string]$KimiApiKey = "<YOUR_KIMI_API_KEY>",
  [string]$FeishuAppId = "",
  [string]$FeishuAppSecret = "",
  [switch]$EnableFeishu
)

$ErrorActionPreference = "Stop"

function Require-Cmd($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "missing command: $name"
  }
}

function Detect-OpenClawDir {
  param([string]$Preferred)
  $candidates = @(
    $Preferred,
    $env:OPENCLAW_PACKAGE_DIR,
    "$env:USERPROFILE\openclaw-work\extracted\package",
    "C:\openclaw-work\extracted\package"
  ) | Where-Object { $_ -and $_.Trim() -ne "" }

  foreach ($c in $candidates) {
    if (Test-Path (Join-Path $c "openclaw.mjs")) {
      return (Resolve-Path $c).Path
    }
  }
  return ""
}

Require-Cmd node
Require-Cmd python
Require-Cmd curl

Write-Host "[WARN] one_click.ps1 is not fully validated across all OpenClaw/system combinations."
Write-Host "[WARN] Backup recommended before continue: %USERPROFILE%\\.openclaw, %USERPROFILE%\\mem0-local, OpenClaw install dir."

$OpenClawPackageDir = Detect-OpenClawDir -Preferred $OpenClawPackageDir
if (-not $OpenClawPackageDir) {
  throw "openclaw.mjs not found. Please pass -OpenClawPackageDir"
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\.." )).Path
$CommonDir = Join-Path $RepoRoot "deploy\common"
$TemplateDir = Join-Path $RepoRoot "templates\mem0-hub"
$Mem0Url = "http://127.0.0.1:$Mem0Port"
$Mem0ExtensionPath = Join-Path $OpenClawHome "extensions\mem0-hub"

Write-Host "[INFO] openclaw dir: $OpenClawPackageDir"
Write-Host "[INFO] openclaw home: $OpenClawHome"
Write-Host "[INFO] mem0 dir: $Mem0Dir"

New-Item -ItemType Directory -Force -Path $Mem0Dir, (Join-Path $Mem0Dir "data"), $Mem0ExtensionPath, $OpenClawHome | Out-Null
Copy-Item -Force (Join-Path $CommonDir "mem0_api.py") (Join-Path $Mem0Dir "mem0_api.py")
Copy-Item -Force (Join-Path $CommonDir "requirements.txt") (Join-Path $Mem0Dir "requirements.txt")
Copy-Item -Force (Join-Path $TemplateDir "index.ts") (Join-Path $Mem0ExtensionPath "index.ts")

if (-not (Test-Path (Join-Path $Mem0Dir ".venv\Scripts\python.exe"))) {
  python -m venv (Join-Path $Mem0Dir ".venv")
}

$PyExe = Join-Path $Mem0Dir ".venv\Scripts\python.exe"
& $PyExe -m pip install -U pip
& $PyExe -m pip install -r (Join-Path $Mem0Dir "requirements.txt")

$envText = @"
OPENAI_API_KEY=openclaw-local
OPENAI_BASE_URL=http://127.0.0.1:$OpenClawGatewayPort/v1

MEM0_LLM_PROVIDER=openai
MEM0_LLM_MODEL=kimicode/kimi-k2.5

MEM0_EMBEDDER_PROVIDER=huggingface
MEM0_EMBEDDER_MODEL=BAAI/bge-large-zh-v1.5
MEM0_EMBEDDING_DIMS=1024
HF_ENDPOINT=https://hf-mirror.com

MEM0_QDRANT_PATH=./data/qdrant-openclaw
MEM0_HISTORY_DB_PATH=./data/history-openclaw.db
MEM0_COLLECTION_NAME=mem0
"@
Set-Content -Path (Join-Path $Mem0Dir ".env") -Value $envText -Encoding UTF8

$env:OPENCLAW_HOME = $OpenClawHome
$env:OPENCLAW_CONFIG = Join-Path $OpenClawHome "openclaw.json"
$env:MEM0_URL = $Mem0Url
$env:MEM0_EXTENSION_PATH = $Mem0ExtensionPath
$env:KIMI_API_KEY = $KimiApiKey
$env:OPENCLAW_GATEWAY_PORT = "$OpenClawGatewayPort"

if ($EnableFeishu.IsPresent) {
  if (-not $FeishuAppId -or -not $FeishuAppSecret) {
    throw "EnableFeishu requires -FeishuAppId and -FeishuAppSecret"
  }
  $env:ENABLE_FEISHU = "1"
  $env:FEISHU_APP_ID = $FeishuAppId
  $env:FEISHU_APP_SECRET = $FeishuAppSecret
} else {
  $env:ENABLE_FEISHU = "0"
}

node (Join-Path $CommonDir "patch_openclaw_config.mjs")

$RunHome = "$env:USERPROFILE\.openclaw-mem0"
$RunDir = Join-Path $RunHome "run"
$LogDir = Join-Path $RunHome "logs"
$BinDir = Join-Path $RunHome "bin"
New-Item -ItemType Directory -Force -Path $RunDir, $LogDir, $BinDir | Out-Null

$startOpenClaw = @"
`$node = (Get-Command node).Source
`$proc = Start-Process -FilePath `$node -ArgumentList './openclaw.mjs --no-color gateway run' -WorkingDirectory '$OpenClawPackageDir' -RedirectStandardOutput '$LogDir\\openclaw.out.log' -RedirectStandardError '$LogDir\\openclaw.err.log' -PassThru
Set-Content -Path '$RunDir\\openclaw.pid' -Value `$proc.Id
Write-Host "openclaw started pid=`$(`$proc.Id)"
"@
Set-Content -Path (Join-Path $BinDir "start-openclaw.ps1") -Value $startOpenClaw -Encoding UTF8

$startMem0 = @"
`$py = '$Mem0Dir\\.venv\\Scripts\\python.exe'
`$args = '-m uvicorn mem0_api:app --host 127.0.0.1 --port $Mem0Port --workers 1'
`$proc = Start-Process -FilePath `$py -ArgumentList `$args -WorkingDirectory '$Mem0Dir' -RedirectStandardOutput '$LogDir\\mem0.out.log' -RedirectStandardError '$LogDir\\mem0.err.log' -PassThru
Set-Content -Path '$RunDir\\mem0.pid' -Value `$proc.Id
Write-Host "mem0 started pid=`$(`$proc.Id)"
"@
Set-Content -Path (Join-Path $BinDir "start-mem0.ps1") -Value $startMem0 -Encoding UTF8

$stopStack = @"
foreach (`$name in @('mem0','openclaw')) {
  `$pidFile = '$RunDir\\' + `$name + '.pid'
  if (Test-Path `$pidFile) {
    `$pid = Get-Content `$pidFile | Select-Object -First 1
    if (`$pid) {
      Stop-Process -Id [int]`$pid -Force -ErrorAction SilentlyContinue
    }
    Remove-Item `$pidFile -Force -ErrorAction SilentlyContinue
  }
}
"@
Set-Content -Path (Join-Path $BinDir "stop-stack.ps1") -Value $stopStack -Encoding UTF8

$statusStack = @"
foreach (`$name in @('openclaw','mem0')) {
  `$pidFile = '$RunDir\\' + `$name + '.pid'
  if (Test-Path `$pidFile) {
    `$pid = [int](Get-Content `$pidFile | Select-Object -First 1)
    `$p = Get-Process -Id `$pid -ErrorAction SilentlyContinue
    if (`$p) { Write-Host "`$name running pid=`$pid" } else { Write-Host "`$name stopped" }
  } else {
    Write-Host "`$name stopped"
  }
}
try {
  curl "http://127.0.0.1:$Mem0Port/health"
} catch {}
"@
Set-Content -Path (Join-Path $BinDir "status-stack.ps1") -Value $statusStack -Encoding UTF8

& (Join-Path $BinDir "start-openclaw.ps1")
Start-Sleep -Seconds 2
& (Join-Path $BinDir "start-mem0.ps1")
Start-Sleep -Seconds 2
& (Join-Path $BinDir "status-stack.ps1")

Write-Host "[DONE] Windows one-click completed."
Write-Host "Run scripts:"
Write-Host "  $BinDir\\start-openclaw.ps1"
Write-Host "  $BinDir\\start-mem0.ps1"
Write-Host "  $BinDir\\stop-stack.ps1"
Write-Host "  $BinDir\\status-stack.ps1"
