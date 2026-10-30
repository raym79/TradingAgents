[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Install', 'Verify', 'Run', 'Updates', 'PrepareUpdate')]
    [string]$Task = 'Verify',
    [string]$Ref,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CliArgs
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $root
try {
    $env:UV_CACHE_DIR = Join-Path $root '.cache\uv'
    $env:UV_LINK_MODE = 'copy'
    $env:PYTHONUTF8 = '1'
    $uv = Join-Path $root '.tools\Scripts\uv.exe'
    $python = Join-Path $root '.venv\Scripts\python.exe'
    function Invoke-Checked {
        param([string]$Command, [string[]]$Arguments)
        & $Command @Arguments
        if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Command $Arguments" }
    }
    function Sync-Environment {
        if (-not (Test-Path -LiteralPath $uv)) { throw 'Run scripts\manage.ps1 Install first.' }
        Invoke-Checked $uv @('sync', '--locked', '--extra', 'dev')
    }
    function Verify-Project {
        Sync-Environment
        Invoke-Checked $uv @('pip', 'check')
        Invoke-Checked (Join-Path $root '.venv\Scripts\ruff.exe') @('check', '.')
        Invoke-Checked $python @('-m', 'pytest', '-q')
        Invoke-Checked $python @('-m', 'cli.main', '--help')
    }
    switch ($Task) {
        'Install' {
            if (-not (Test-Path -LiteralPath '.tools\Scripts\python.exe')) {
                Invoke-Checked 'python' @('-m', 'venv', '.tools')
            }
            Invoke-Checked (Join-Path $root '.tools\Scripts\python.exe') @('-m', 'pip', '--disable-pip-version-check', 'install', 'uv==0.9.5')
            Sync-Environment
            if (-not (Test-Path -LiteralPath '.env')) {
                Copy-Item -LiteralPath '.env.example' -Destination '.env'
            }
            Write-Host 'Installed. Configure your provider in .env, then run scripts\manage.ps1 Run.'
        }
        'Verify' { Verify-Project }
        'Run' {
            Sync-Environment
            $env:TRADINGAGENTS_RESULTS_DIR = Join-Path $root '.runtime\results'
            $env:TRADINGAGENTS_CACHE_DIR = Join-Path $root '.runtime\cache'
            $env:TRADINGAGENTS_MEMORY_LOG_PATH = Join-Path $root '.runtime\memory\trading_memory.md'
            Invoke-Checked $python (@('-m', 'cli.main') + $CliArgs)
        }
        'Updates' {
            if (-not (Test-Path -LiteralPath $python)) { throw 'Run scripts\manage.ps1 Install first.' }
            Invoke-Checked $python @('scripts/upstream_status.py', '--fetch')
        }
        'PrepareUpdate' {
            if ($Ref -notmatch '^(v\d+\.\d+\.\d+|[a-fA-F0-9]{40})$') {
                throw 'Supply -Ref with an exact stable release tag or full 40-character commit SHA.'
            }
            $dirty = & git status --porcelain
            if ($LASTEXITCODE -ne 0) { throw 'Could not read Git status.' }
            if ($dirty) { throw 'Commit or stash your changes before preparing an update.' }
            Invoke-Checked $python @('scripts/upstream_status.py', '--fetch')
            $targetRef = $Ref
            if ($Ref.StartsWith('v')) { $targetRef = "refs/tags/$Ref" }
            $target = & git rev-parse --verify "$targetRef^{commit}"
            if ($LASTEXITCODE -ne 0) { throw 'The requested revision does not exist.' }
            Invoke-Checked 'git' @('merge-base', '--is-ancestor', $target, 'refs/remotes/upstream/main')
            $baseline = Get-Content -LiteralPath 'deployment/upstream.json' -Raw | ConvertFrom-Json
            Invoke-Checked 'git' @('merge-base', '--is-ancestor', $baseline.commit, $target)
            if ($baseline.commit -eq $target) {
                Write-Host 'This upstream revision is already the reviewed baseline.'
                return
            }
            $branch = 'update/upstream-' + $target.Substring(0, 12)
            Invoke-Checked 'git' @('switch', '-c', $branch)
            # Stop on conflicts; never discard local changes or force a merge.
            Invoke-Checked 'git' @('merge', '--no-ff', '--no-commit', $target)
            Invoke-Checked $uv @('lock')
            Verify-Project
            $version = & $python -c 'import tradingagents; print(tradingagents.__version__)'
            if ($LASTEXITCODE -ne 0) { throw 'Could not read package version.' }
            $baseline.commit = $target
            $baseline.version = $version.Trim()
            $json = ($baseline | ConvertTo-Json) + "`n"
            [System.IO.File]::WriteAllText((Join-Path $root 'deployment/upstream.json'), $json, [System.Text.UTF8Encoding]::new($false))
            Write-Host "Update passed validation on $branch. Review git diff HEAD and commit the merge; return to local/main and merge only after review."
        }
    }
}
finally { Pop-Location }
