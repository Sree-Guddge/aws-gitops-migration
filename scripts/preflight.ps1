#!/usr/bin/env pwsh
# scripts/preflight.ps1
# One-shot pre-demo verification for the AWS GitOps repo.
#
# Runs the repo's correctness properties plus a tooling/git readiness check and
# prints PASS / FAIL / WARN for each. Designed to be run right before the handover demo.
#
# Usage (from anywhere):
#   pwsh -File scripts/preflight.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/preflight.ps1
#
# Exit code: 0 when all hard checks pass, 1 otherwise.
# Missing optional tools (tfsec/checkov/jq) are warnings, not failures.

$ErrorActionPreference = 'Continue'

# Repo root = the parent directory of this script (scripts/..)
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$script:fail = 0
function Pass($m) { Write-Host "[PASS] $m" -ForegroundColor Green }
function Fail($m) { Write-Host "[FAIL] $m" -ForegroundColor Red; $script:fail++ }
function Warn($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Info($m) { Write-Host $m -ForegroundColor Cyan }

Info "=== Preflight: AWS GitOps demo checks ==="
Info "Repo root: $RepoRoot"
Write-Host ""

# Files we treat as "source" for the region/key/format properties.
$srcExt   = '*.tf', '*.yml', '*.yaml', '*.tfvars'
$srcFiles = Get-ChildItem -Recurse -Include $srcExt -File |
    Where-Object { $_.FullName -notlike '*\.terraform\*' -and $_.FullName -notlike '*\.git\*' }

# --- Check 0: tooling availability -------------------------------------------
Info "--- Tooling ---"
$tools = @{}
foreach ($t in 'terraform', 'aws', 'gh', 'tfsec', 'checkov', 'jq') {
    $cmd = Get-Command $t -ErrorAction SilentlyContinue
    $tools[$t] = [bool]$cmd
    if ($cmd) { Pass "tool present: $t" }
    elseif ($t -in 'terraform', 'aws', 'gh') { Fail "required tool MISSING: $t" }
    else { Warn "optional tool missing: $t (security-scan / json helpers won't run locally)" }
}
Write-Host ""

# --- Check 1: terraform fmt ---------------------------------------------------
Info "--- Property: terraform fmt ---"
if ($tools['terraform']) {
    terraform fmt -check -recursive ./infra ./modules ./envs *> $null
    if ($LASTEXITCODE -eq 0) {
        Pass "terraform fmt: all files formatted"
    }
    else {
        Fail "terraform fmt: files need formatting -> run: terraform fmt -recursive ./infra ./modules ./envs"
    }
}
else {
    Warn "skipped (terraform not installed)"
}
Write-Host ""

# --- Check 2: no hardcoded region strings ------------------------------------
Info "--- Property 1: no hardcoded region strings (us-west-2 / eu-west-2) ---"
$region = $srcFiles | Select-String -Pattern 'us-west-2', 'eu-west-2'
if (($region | Measure-Object).Count -eq 0) {
    Pass "no hardcoded region strings (region is injected at runtime)"
}
else {
    Fail "found hardcoded region strings:"
    $region | ForEach-Object { Write-Host ("    {0}:{1}: {2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()) }
}
Write-Host ""

# --- Check 3: no hardcoded AZ names ------------------------------------------
Info "--- Property 2: no hardcoded AZ names (us-west-2a/b/c) ---"
$az = $srcFiles | Where-Object { $_.Extension -eq '.tf' } | Select-String -Pattern 'us-west-2[abc]'
if (($az | Measure-Object).Count -eq 0) {
    Pass "no hardcoded AZ names (resolved via data.aws_availability_zones)"
}
else {
    Fail "found hardcoded AZ names:"
    $az | ForEach-Object { Write-Host ("    {0}:{1}: {2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()) }
}
Write-Host ""

# --- Check 4: no AWS access keys ---------------------------------------------
Info "--- Property 3: no AWS access keys (AKIA...) in the repo ---"
$allFiles = Get-ChildItem -Recurse -File |
    Where-Object { $_.FullName -notlike '*\.terraform\*' -and $_.FullName -notlike '*\.git\*' }
$akia = $allFiles | Select-String -Pattern 'AKIA[A-Z0-9]{16}'
if (($akia | Measure-Object).Count -eq 0) {
    Pass "no AWS access keys committed in the repo"
}
else {
    Fail "found possible AWS access keys (rotate immediately):"
    $akia | ForEach-Object { Write-Host ("    {0}:{1}" -f $_.Path, $_.LineNumber) }
}
Write-Host ""

# --- Check 5: OIDC property (every AWS auth uses role-to-assume) -------------
Info "--- Property 4: every configure-aws-credentials usage pairs with role-to-assume ---"
$wf = Get-ChildItem -Recurse -Include '*.yml', '*.yaml' -File |
    Where-Object { $_.FullName -notlike '*\.terraform\*' -and $_.FullName -notlike '*\.git\*' }
$totalUses = 0; $totalRoles = 0; $badFiles = @()
foreach ($f in $wf) {
    $u = (Select-String -Path $f.FullName -Pattern 'aws-actions/configure-aws-credentials' | Measure-Object).Count
    $r = (Select-String -Path $f.FullName -Pattern 'role-to-assume' | Measure-Object).Count
    $totalUses += $u; $totalRoles += $r
    if ($u -gt $r) { $badFiles += $f.FullName }
}
if ($totalUses -eq 0) {
    Warn "no configure-aws-credentials usages found in workflows"
}
elseif ($badFiles.Count -eq 0) {
    Pass "OIDC-only: $totalUses AWS-auth steps, all paired with role-to-assume ($totalRoles found)"
}
else {
    Fail "configure-aws-credentials without matching role-to-assume in:"
    $badFiles | ForEach-Object { Write-Host "    $_" }
}
Write-Host ""

# --- Check 6: git readiness --------------------------------------------------
Info "--- Git readiness ---"
$branch = (git rev-parse --abbrev-ref HEAD 2>$null)
if ($branch) { Info "branch: $branch" }
$porcelain = git status --porcelain=v1 2>$null
$modifiedTracked = $porcelain | Where-Object { $_ -match '^[ MARCD][MD]' -or $_ -match '^[MARCD]' }
$untracked = $porcelain | Where-Object { $_ -match '^\?\?' }
if (-not $porcelain) {
    Pass "working tree clean"
}
else {
    if ($modifiedTracked) {
        Warn "uncommitted changes to tracked files (consider committing before demo):"
        $modifiedTracked | ForEach-Object { Write-Host "    $_" }
    }
    else {
        Pass "no uncommitted changes to tracked files"
    }
    if ($untracked) {
        Info "untracked files (informational):"
        $untracked | ForEach-Object { Write-Host "    $_" }
    }
}
Write-Host ""

# --- Summary -----------------------------------------------------------------
if ($script:fail -eq 0) {
    Write-Host "=== PREFLIGHT PASSED - repo is demo-ready ===" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "=== PREFLIGHT FAILED - $($script:fail) hard check(s) need attention ===" -ForegroundColor Red
    exit 1
}
