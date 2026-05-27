param(
    [string] $Config
)

$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($Config)) {
    $Config = Join-Path (Split-Path -Parent $ScriptRoot) 'release.config.psd1'
}

Import-Module (Join-Path $ScriptRoot 'PluginReleaseConfig.psm1') -Force
$ReleaseConfig = Import-PluginReleaseConfig -Path $Config
$repoRoot = $ReleaseConfig.RepoRoot

function Fail([string] $Message) {
    Write-Error $Message
    exit 1
}

Push-Location $repoRoot
try {
    $name = (& git config --local user.name).Trim()
    if ($name -ne $ReleaseConfig.ExpectedGitUserName) {
        Fail "Unexpected local git user.name: '$name'. Expected '$($ReleaseConfig.ExpectedGitUserName)'."
    }

    $email = (& git config --local user.email).Trim()
    if ($email -ne $ReleaseConfig.ExpectedGitUserEmail) {
        Fail "Unexpected local git user.email: '$email'. Expected '$($ReleaseConfig.ExpectedGitUserEmail)'."
    }

    $origin = (& git remote get-url origin).Trim()
    if ($origin -notin $ReleaseConfig.ExpectedRemotes) {
        Fail "Unexpected origin remote: '$origin'. Expected one of: $($ReleaseConfig.ExpectedRemotes -join ', ')."
    }

    $remotes = & git remote -v
    if ($remotes -match 'https?://') {
        Fail "HTTPS remote detected:`n$($remotes -join [Environment]::NewLine)"
    }

    $forbidden = @($ReleaseConfig.ForbiddenIdentityStrings | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($forbidden.Count -gt 0) {
        $pattern = ($forbidden | ForEach-Object { [regex]::Escape($_) }) -join '|'
        $rg = Get-Command rg -ErrorAction SilentlyContinue
        if ($null -eq $rg) {
            Fail 'ripgrep (rg) is required for identity scanning.'
        }

        & $rg.Source -n -i $pattern . `
            -g '!*bin*' `
            -g '!*obj*' `
            -g '!Reference/**' `
            -g '!.vs/**' `
            -g '!.git/**'
        $scanExitCode = $LASTEXITCODE
        if ($scanExitCode -eq 0) {
            Fail 'Forbidden main-account identity string found in repository source.'
        }

        if ($scanExitCode -ne 1) {
            Fail "Identity scan failed with rg exit code $scanExitCode."
        }
    }

    Write-Host "Repo identity verified:"
    Write-Host "  user.name  = $name"
    Write-Host "  user.email = $email"
    Write-Host "  origin     = $origin"
    Write-Host "  remotes    = SSH-only"
    Write-Host "  scan       = no forbidden identity strings"
}
finally {
    Pop-Location
}
