param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $Version,

    [string] $Config,

    [switch] $ValidateOnly,

    [switch] $PreflightOnly,

    [switch] $SkipGitHubRelease
)

$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($Config)) {
    $Config = Join-Path (Split-Path -Parent $ScriptRoot) 'release.config.psd1'
}

Import-Module (Join-Path $ScriptRoot 'PluginReleaseConfig.psm1') -Force
$ReleaseConfig = Import-PluginReleaseConfig -Path $Config

if ([string]::IsNullOrWhiteSpace($env:GH_CONFIG_DIR)) {
    $env:GH_CONFIG_DIR = $ReleaseConfig.GhConfigDir
}

$login = (& gh api user --jq .login 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($login)) {
    Write-Error "GitHub CLI login for GH_CONFIG_DIR is missing. Run: `$env:GH_CONFIG_DIR='$($ReleaseConfig.GhConfigDir)'; gh auth login --hostname github.com --git-protocol ssh --web"
    exit 1
}

if (([string] $login).Trim() -ne $ReleaseConfig.Owner) {
    Write-Error "GitHub CLI login for GH_CONFIG_DIR is '$(([string] $login).Trim())'; expected '$($ReleaseConfig.Owner)'."
    exit 1
}

$arguments = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    (Join-Path $ScriptRoot 'Release.ps1'),
    '-Version',
    $Version,
    '-Config',
    $ReleaseConfig.ConfigPath
)

if ($ValidateOnly) {
    $arguments += '-ValidateOnly'
}

if ($PreflightOnly) {
    $arguments += '-PreflightOnly'
}

if ($SkipGitHubRelease) {
    $arguments += '-SkipGitHubRelease'
}

& powershell @arguments
exit $LASTEXITCODE
