$RequiredPluginReleaseConfigKeys = @(
    'Owner',
    'RepoName',
    'ProjectPath',
    'ReleaseAssetName',
    'ExpectedGitUserName',
    'ExpectedGitUserEmail',
    'ExpectedRemotes',
    'ReleaseWorkflowFile',
    'MasterOwner',
    'MasterRepoName',
    'MasterWorkflowFile'
)

function Resolve-PluginReleasePath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $BasePath,

        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $expanded = Resolve-PluginReleaseHomePath -Path $Path
    if ([System.IO.Path]::IsPathRooted($expanded)) {
        return [System.IO.Path]::GetFullPath($expanded)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $expanded))
}

function Resolve-PluginReleaseHomePath {
    param([Parameter(Mandatory = $true)][string] $Path)

    if ($Path -eq '~') {
        return $HOME
    }

    if ($Path.StartsWith('~\') -or $Path.StartsWith('~/')) {
        return Join-Path $HOME $Path.Substring(2)
    }

    return $Path
}

function Get-PluginReleaseRepoRoot {
    param([Parameter(Mandatory = $true)][string] $ConfigPath)

    $configDirectory = Split-Path -Parent $ConfigPath
    $repoRoot = (& git -C $configDirectory rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
        throw "Failed to resolve git repository root from config path: $ConfigPath"
    }

    return [System.IO.Path]::GetFullPath(([string] $repoRoot).Trim())
}

function Import-PluginReleaseConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $configPath = Resolve-PluginReleasePath -BasePath (Get-Location).Path -Path $Path
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Missing release config: $configPath"
    }

    $raw = Import-PowerShellDataFile -LiteralPath $configPath
    foreach ($key in $RequiredPluginReleaseConfigKeys) {
        if (-not $raw.ContainsKey($key) -or $null -eq $raw[$key] -or [string]::IsNullOrWhiteSpace([string] $raw[$key])) {
            throw "Release config missing required key: $key"
        }
    }

    $repoRoot = Get-PluginReleaseRepoRoot -ConfigPath $configPath
    $projectPath = Resolve-PluginReleasePath -BasePath $repoRoot -Path ([string] $raw.ProjectPath)
    $projectName = [System.IO.Path]::GetFileNameWithoutExtension($projectPath)
    $projectDir = Split-Path -Parent $projectPath
    $builtPluginDir = if ($raw.ContainsKey('BuiltPluginDir') -and -not [string]::IsNullOrWhiteSpace([string] $raw.BuiltPluginDir)) {
        Resolve-PluginReleasePath -BasePath $repoRoot -Path ([string] $raw.BuiltPluginDir)
    }
    else {
        Join-Path $projectDir "bin\x64\Release\$projectName"
    }

    $testProjectPath = if ($raw.ContainsKey('TestProjectPath') -and -not [string]::IsNullOrWhiteSpace([string] $raw.TestProjectPath)) {
        Resolve-PluginReleasePath -BasePath $repoRoot -Path ([string] $raw.TestProjectPath)
    }
    else {
        $null
    }

    $solutionPath = if ($raw.ContainsKey('SolutionPath') -and -not [string]::IsNullOrWhiteSpace([string] $raw.SolutionPath)) {
        Resolve-PluginReleasePath -BasePath $repoRoot -Path ([string] $raw.SolutionPath)
    }
    else {
        $null
    }

    $ghConfigDir = if ($raw.ContainsKey('GhConfigDir') -and -not [string]::IsNullOrWhiteSpace([string] $raw.GhConfigDir)) {
        Resolve-PluginReleaseHomePath -Path ([string] $raw.GhConfigDir)
    }
    else {
        Join-Path $HOME '.config\gh-bloooowfish'
    }

    $expectedRemotes = @($raw.ExpectedRemotes | ForEach-Object { [string] $_ })
    if ($expectedRemotes.Count -eq 0) {
        throw 'Release config ExpectedRemotes must contain at least one remote URL.'
    }

    $forbiddenIdentityStrings = if ($raw.ContainsKey('ForbiddenIdentityStrings')) {
        @($raw.ForbiddenIdentityStrings | ForEach-Object { [string] $_ })
    }
    else {
        @(
            ('Ayu' + 'mudayo'),
            ('yu' + 'memi'),
            ('github' + '-main'),
            ('github.com/' + 'local'),
            ('MA' + 'RU')
        )
    }

    [PSCustomObject]@{
        ConfigPath = $configPath
        RepoRoot = $repoRoot
        Owner = [string] $raw.Owner
        RepoName = [string] $raw.RepoName
        ProjectPath = $projectPath
        ProjectPathRelative = [string] $raw.ProjectPath
        ProjectName = $projectName
        TestProjectPath = $testProjectPath
        TestProjectPathRelative = if ($raw.ContainsKey('TestProjectPath')) { [string] $raw.TestProjectPath } else { $null }
        SolutionPath = $solutionPath
        SolutionPathRelative = if ($raw.ContainsKey('SolutionPath')) { [string] $raw.SolutionPath } else { $null }
        BuiltPluginDir = $builtPluginDir
        BuiltZipPath = Join-Path $builtPluginDir 'latest.zip'
        DistDir = Join-Path $repoRoot 'dist'
        ReleaseAssetName = [string] $raw.ReleaseAssetName
        ReleaseTitle = if ($raw.ContainsKey('ReleaseTitle')) { [string] $raw.ReleaseTitle } else { "$($raw.RepoName) {0}" }
        ReleaseNotes = if ($raw.ContainsKey('ReleaseNotes')) { [string] $raw.ReleaseNotes } else { "$($raw.RepoName) {0}" }
        ExpectedGitUserName = [string] $raw.ExpectedGitUserName
        ExpectedGitUserEmail = [string] $raw.ExpectedGitUserEmail
        ExpectedRemotes = $expectedRemotes
        ReleaseWorkflowFile = [string] $raw.ReleaseWorkflowFile
        MasterOwner = [string] $raw.MasterOwner
        MasterRepoName = [string] $raw.MasterRepoName
        MasterWorkflowFile = [string] $raw.MasterWorkflowFile
        GhConfigDir = $ghConfigDir
        ForbiddenIdentityStrings = $forbiddenIdentityStrings
    }
}

Export-ModuleMember -Function Import-PluginReleaseConfig, Resolve-PluginReleaseHomePath
