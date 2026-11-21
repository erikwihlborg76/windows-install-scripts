# Running and validating the installer

[Back to the README](../README.md).

## Setup results

A transcript is saved to `%TEMP%\windows-install-<timestamp>.log`. The final summary lists operations that could not be completed:

| Exit code | Meaning |
| --- | --- |
| `0` | Completed successfully, or cancelled before setup |
| `1` | Stopped on an error |
| `2` | Finished with warnings; review the summary and transcript |

Optional missing private files and already-absent applications are expected skips. `-SkipConfirmation` skips the setup-plan confirmation; mode and profile selection are still required. `-NoPause` skips the final pause before exit.

## Development and validation

The repository separates Windows configuration and application preferences in `modules/SystemSetup` from private sync discovery and links in `modules/SyncProfile`. `Install.ps1` orchestrates the setup; `00-install.ps1` is the download bootstrap.

Run the local validator from the repository root with Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\validate.ps1
```

Install the pinned test tools once, then run the same checks as CI:

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser -Force
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\test.ps1
```

The runner also accepts `-PesterModulePath` and `-ScriptAnalyzerModulePath` for isolated copies of those versions. Tests use temporary files, isolated registry keys, and mocked setup operations; they do not run the real installer against Windows settings. CI runs the validator, PSScriptAnalyzer, and Pester.
