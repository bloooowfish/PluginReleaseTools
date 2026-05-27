$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configModule = Join-Path $repoRoot 'PluginReleaseConfig.psm1'
$releaseScript = Join-Path $repoRoot 'Release.ps1'
$invokeScript = Join-Path $repoRoot 'Invoke-BfRelease.ps1'
$buildScript = Join-Path $repoRoot 'Build-GitHubRelease.ps1'
$identityScript = Join-Path $repoRoot 'Verify-RepoIdentity.ps1'

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)][object] $Actual,
        [Parameter(Mandatory = $true)][object] $Expected,
        [Parameter(Mandatory = $true)][string] $Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

function Assert-Match {
    param(
        [Parameter(Mandatory = $true)][string] $Actual,
        [Parameter(Mandatory = $true)][string] $Pattern,
        [Parameter(Mandatory = $true)][string] $Message
    )

    if ($Actual -notmatch $Pattern) {
        throw "$Message Pattern=[$Pattern] Actual=[$Actual]"
    }
}

function Assert-NotMatch {
    param(
        [Parameter(Mandatory = $true)][string] $Actual,
        [Parameter(Mandatory = $true)][string] $Pattern,
        [Parameter(Mandatory = $true)][string] $Message
    )

    if ($Actual -match $Pattern) {
        throw "$Message Pattern=[$Pattern] Actual=[$Actual]"
    }
}

foreach ($path in @($configModule, $releaseScript, $invokeScript, $buildScript, $identityScript)) {
    if (-not (Test-Path $path)) {
        throw "Missing release tool file: $path"
    }
}

Import-Module $configModule -Force

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "PluginReleaseToolsTests-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force $tempRoot | Out-Null
try {
    & git -C $tempRoot init | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to initialize temp git repo.'
    }

    New-Item -ItemType Directory -Force (Join-Path $tempRoot 'tools') | Out-Null
    New-Item -ItemType Directory -Force (Join-Path $tempRoot 'SamplePlugin') | Out-Null
    New-Item -ItemType File -Force (Join-Path $tempRoot 'SamplePlugin\SamplePlugin.csproj') | Out-Null
    New-Item -ItemType File -Force (Join-Path $tempRoot 'SamplePlugin.Tests.csproj') | Out-Null

    $configPath = Join-Path $tempRoot 'tools\release.config.psd1'
    @"
@{
    Owner = 'bloooowfish'
    RepoName = 'SamplePlugin'
    ProjectPath = 'SamplePlugin\SamplePlugin.csproj'
    TestProjectPath = 'SamplePlugin.Tests.csproj'
    ReleaseAssetName = 'SamplePlugin-{0}.zip'
    ExpectedGitUserName = 'bloooowfish'
    ExpectedGitUserEmail = '285025450+bloooowfish@users.noreply.github.com'
    ExpectedRemotes = @('github-bf:bloooowfish/SamplePlugin.git')
    ReleaseWorkflowFile = 'release.yml'
    MasterOwner = 'bloooowfish'
    MasterRepoName = 'MyPluginMaster'
    MasterWorkflowFile = 'update-repo.yml'
    GhConfigDir = '~\.config\gh-bloooowfish'
}
"@ | Set-Content -LiteralPath $configPath -Encoding UTF8

    $config = Import-PluginReleaseConfig -Path $configPath
    Assert-Equal -Actual $config.RepoRoot -Expected $tempRoot -Message 'Config loader should resolve the plugin repo root from config path.'
    Assert-Equal -Actual $config.Owner -Expected 'bloooowfish' -Message 'Config loader should expose repo owner.'
    Assert-Equal -Actual $config.RepoName -Expected 'SamplePlugin' -Message 'Config loader should expose repo name.'
    Assert-Equal -Actual $config.ProjectPath -Expected (Join-Path $tempRoot 'SamplePlugin\SamplePlugin.csproj') -Message 'Config loader should resolve project path.'
    Assert-Equal -Actual $config.TestProjectPath -Expected (Join-Path $tempRoot 'SamplePlugin.Tests.csproj') -Message 'Config loader should resolve test project path.'
    Assert-Match -Actual $config.GhConfigDir -Pattern '\\.config\\gh-bloooowfish$' -Message 'Config loader should expand gh config dir.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$releaseScriptText = Get-Content -Raw $releaseScript
Assert-Match -Actual $releaseScriptText -Pattern 'param\(' -Message 'Release script should expose parameters.'
Assert-Match -Actual $releaseScriptText -Pattern '-Config' -Message 'Release script should accept a config path.'
Assert-Match -Actual $releaseScriptText -Pattern 'Assert-OnMainBranch' -Message 'Release script should guard against non-main releases.'
Assert-Match -Actual $releaseScriptText -Pattern 'Assert-BranchSynchronized' -Message 'Release script should require local main to match origin/main.'
Assert-Match -Actual $releaseScriptText -Pattern 'Assert-TagAvailable' -Message 'Release script should reject duplicate tags before publishing.'
Assert-Match -Actual $releaseScriptText -Pattern 'Assert-GitHubReleaseAvailable' -Message 'Release script should reject duplicate GitHub releases before publishing.'
Assert-Match -Actual $releaseScriptText -Pattern 'Release workflow preflight passed' -Message 'Release script should support no-mutation workflow preflight mode.'
Assert-Match -Actual $releaseScriptText -Pattern 'workflow'',\s*''run' -Message 'Release script should trigger GitHub Actions workflow.'
Assert-Match -Actual $releaseScriptText -Pattern 'displayTitle' -Message 'Release script should match workflow runs by display title correlation.'
Assert-Match -Actual $releaseScriptText -Pattern '\[Guid\]::NewGuid' -Message 'Release script should generate unique workflow correlation ids.'
Assert-Match -Actual $releaseScriptText -Pattern 'correlation_id=' -Message 'Release script should pass correlation ids into workflow_dispatch inputs.'
Assert-Match -Actual $releaseScriptText -Pattern 'run'',\s*''watch' -Message 'Release script should watch workflow completion before continuing.'
Assert-Match -Actual $releaseScriptText -Pattern '--interval'',\s*''1''' -Message 'Release script should refresh workflow watch progress every second.'
Assert-Match -Actual $releaseScriptText -Pattern 'Release and master repository update completed' -Message 'Release script should report completion after both workflows finish.'
Assert-Match -Actual $releaseScriptText -Pattern 'function Invoke-ScalarCommand' -Message 'Release script should use a scalar native-command helper.'
Assert-Match -Actual $releaseScriptText -Pattern 'function Invoke-CommandCapture' -Message 'Release script should capture expected native-command failures without terminating.'
Assert-NotMatch -Actual $releaseScriptText -Pattern 'dotnet\s*'',\s*''build' -Message 'Release trigger script should not build locally.'
Assert-NotMatch -Actual $releaseScriptText -Pattern 'Set-ProjectVersion' -Message 'Release trigger script should not mutate local version metadata.'
Assert-NotMatch -Actual $releaseScriptText -Pattern 'rev-parse\s+HEAD\s*\|' -Message 'Release script should not pipe git rev-parse HEAD before checking native exit codes.'
Assert-NotMatch -Actual $releaseScriptText -Pattern 'gh api user --jq \.login.*\|' -Message 'Release script should not pipe gh identity checks before checking native exit codes.'

$invokeScriptText = Get-Content -Raw $invokeScript
Assert-Match -Actual $invokeScriptText -Pattern 'GH_CONFIG_DIR' -Message 'Invoke script should manage GH_CONFIG_DIR.'
Assert-Match -Actual $invokeScriptText -Pattern 'gh api user --jq \.login' -Message 'Invoke script should check gh login.'
Assert-Match -Actual $invokeScriptText -Pattern 'Split-Path -Parent \$ScriptRoot' -Message 'Invoke script default config should be relative to tools, not caller cwd.'

$buildScriptText = Get-Content -Raw $buildScript
Assert-Match -Actual $buildScriptText -Pattern 'Set-ProjectVersion' -Message 'GitHub build script should update the project version in CI.'
Assert-Match -Actual $buildScriptText -Pattern "FilePath 'dotnet'.+?'build'" -Message 'GitHub build script should build the plugin in CI.'
Assert-Match -Actual $buildScriptText -Pattern 'release'',\s*''create' -Message 'GitHub build script should create the GitHub release asset in CI.'
Assert-Match -Actual $buildScriptText -Pattern "'checkout', 'main'" -Message 'GitHub build script should commit from main, not detached HEAD.'
Assert-Match -Actual $buildScriptText -Pattern 'Assert-TagAvailable' -Message 'GitHub build script should re-check tag availability in CI.'
Assert-Match -Actual $buildScriptText -Pattern 'Assert-GitHubReleaseAvailable' -Message 'GitHub build script should re-check release availability in CI.'
Assert-NotMatch -Actual $buildScriptText -Pattern 'RepoJsonPath|Write-RepoJson|Get-GitHubZipDownloadCount|DownloadCount|ConvertTo-Json' -Message 'GitHub build script should not generate plugin-store repo.json; MyPluginMaster owns repo metadata.'

$identityScriptText = Get-Content -Raw $identityScript
Assert-Match -Actual $identityScriptText -Pattern 'ExpectedRemotes' -Message 'Identity script should use config-driven expected remotes.'
Assert-Match -Actual $identityScriptText -Pattern 'https\?://' -Message 'Identity script should reject HTTPS remotes.'
Assert-Match -Actual $identityScriptText -Pattern 'ForbiddenIdentityStrings' -Message 'Identity script should scan config-driven forbidden identity strings.'

Write-Host 'Release tools tests passed.'
