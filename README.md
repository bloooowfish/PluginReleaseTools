# PluginReleaseTools

Shared release tooling for `bloooowfish` Dalamud plugin repositories.

Plugin repositories consume this repository as a pinned git submodule at
`tools/release-tools` and keep plugin-specific release settings in
`tools/release.config.psd1`.

Local release command from a plugin repository root:

```powershell
.\tools\release-tools\Invoke-BfRelease.ps1 7.5.x.y
```

CI release workflows should checkout submodules and call:

```powershell
.\tools\release-tools\Build-GitHubRelease.ps1 -Config .\tools\release.config.psd1 -Version <version>
```

Do not commit GitHub CLI auth files, tokens, or local profile data.
