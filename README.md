# Windows Install Scripts

Opinionated, interactive provisioning for personal and work Windows computers. The installer can configure Windows by itself, add the repository's application set, and optionally restore links and application state from OneDrive or Dropbox.

> [!WARNING]
> This installer runs as administrator and has no automatic rollback. It disables automatic Windows Update, Edge SmartScreen, telemetry-related features, services, and scheduled tasks; HOME also creates placeholder MDM enrollment entries. Review [profile configuration](config/Profiles.psd1), [LGPO policy](resources/LGPO/global_policy_objects.txt), and the [SystemSetup module](modules/SystemSetup/SystemSetup.psm1) before running. Create a backup or restore point first.

## Requirements

- Windows 10, Windows 11, or Windows Server 2025
- Windows PowerShell 5.1
- WinGet/App Installer
- An interactive UAC session
- Administrator credentials

The installer verifies that `winget.exe` can run before it presents or applies a setup plan. On Windows 24H2 IoT, install it as follows if the guard reports that it is unavailable:

1. Run `wsreset -i` to enable Microsoft Store.
2. Open the [App Installer page in Microsoft Store](https://apps.microsoft.com/detail/9nblggh4nns1?hl=en-US&gl=EN).
3. Install App Installer, then run this installer again.

Application installation and automatic LGPO installation require internet access.

## Presets and profiles

The workflow has two independent dimensions:

- **Preset** controls whether applications and sync-backed state are included.
- **Profile** controls HOME/WORK differences.

| Preset | Install applications | Use sync-backed files | Configure Windows and remove apps |
| --- | ---: | ---: | ---: |
| `FULL` | Yes | Yes | Yes |
| `SYSTEM_AND_APPS` | Yes | No | Yes |
| `SYSTEM_ONLY` | No | No | Yes |

| Profile behavior | HOME | WORK |
| --- | ---: | ---: |
| Computer rename prompt | Yes | No |
| Placeholder MDM entries | Yes | No |
| Disable NTFS last-access updates | Yes | No |
| Install Node.js LTS when applications are enabled | No | Yes |
| Explicitly remove Teams | Yes | No |

The sync-independent system module contains no OneDrive, Dropbox, `SyncRoot`, or `Apps-data` dependencies. The sync module owns all provider discovery, filesystem links, and private application state.

## Run

Interactive local checkout:

```powershell
.\00-run-install-manual.cmd
```

The entry point also accepts explicit parameters:

```powershell
.\Install.ps1 -Profile HOME -Preset FULL -SyncProvider Dropbox
.\Install.ps1 -Profile WORK -Preset SYSTEM_AND_APPS
.\Install.ps1 -Profile HOME -Preset SYSTEM_ONLY
```

Use `-SyncRoot` to override provider discovery for the FULL preset. `-SkipConfirmation` and `-NoPause` are available for controlled automation, but the workflow is primarily intended for interactive use.

Remote bootstrap:

```powershell
irm https://raw.githubusercontent.com/erikwihlborg76/windows-install-scripts/main/00-install.ps1 | iex
```

For an inspect-first bootstrap:

```powershell
$url = 'https://raw.githubusercontent.com/erikwihlborg76/windows-install-scripts/main/00-install.ps1'
irm $url -OutFile "$env:TEMP\windows-install.ps1"
notepad "$env:TEMP\windows-install.ps1"
& "$env:TEMP\windows-install.ps1"
```

The bootstrap supports `INSTALL_REPOSITORY`, `INSTALL_REF`, and optional `INSTALL_ARCHIVE_SHA256` environment-variable overrides.

## Execution flow

The installer runs in one Windows PowerShell process:

1. Elevate and verify WinGet.
2. Resolve the preset, HOME/WORK profile, and optional sync provider.
3. For FULL, create sync-backed links before applications can create conflicting folders.
4. For FULL or SYSTEM_AND_APPS, install the WinGet manifests and apply repository-provided Windows Terminal settings.
5. For FULL, restore PowerToys and other sync-backed application state.
6. Apply registry settings, service and scheduled-task configuration, LGPO policy, and power settings.
7. Remove configured WinGet, AppX, provisioned AppX, and Windows capability entries.

A single transcript records the workflow under `%TEMP%\windows-install-<timestamp>.log`.

## Sync layout

FULL resolves the selected sync root from:

| Provider | Location source |
| --- | --- |
| OneDrive Business | `OneDriveCommercial` |
| OneDrive | `OneDriveConsumer` |
| Dropbox | `%APPDATA%\Dropbox\info.json` |

Dropbox discovery handles multiple accounts by selecting the only account containing both required folders. The sync root must contain:

```text
<sync-root>\
├── Apps\
└── Apps-data\
```

The installer creates:

```text
C:\Apps      -> <sync-root>\Apps
C:\Apps-data -> <sync-root>\Apps-data
```

Optional sync-backed state can use:

```text
Apps-data\
├── .openhue\
├── GHISLER\
├── Highresolution Enterprises\
├── foobar2000-v2\
├── PowerToys\
│   ├── FancyZones\
│   ├── LightSwitch\
│   └── CommandPalette\settings.json
└── Shortcuts\
```

Everything under `Apps-data\Shortcuts` is copied to the current user's Start menu. Personal and private data should remain under `Apps-data`, not in this repository.

## Repository structure

```text
Install.ps1                         Single-process orchestrator
config\Profiles.psd1                Common and HOME/WORK configuration
config\packages.common.json        Common WinGet package manifest
config\packages.work.json          WORK package additions
modules\SystemSetup\               Sync-independent Windows operations
modules\SyncProfile\               Sync discovery, links, and private state
resources\LGPO\                    Local Group Policy configuration
resources\Windows Terminal\        Repository-provided Terminal settings
tests\                              Pester behavior and boundary tests
tools\validate.ps1                 Syntax, data, structure, and boundary checks
```

`SystemSetup` intentionally uses built-in PowerShell providers and modules for registry values, services, scheduled tasks, DISM capabilities, and AppX packages. Custom logic remains only where the repository needs specific behavior, such as safe reparse-point replacement, Dropbox account resolution, WinGet manifests, and LGPO discovery.

## Customize

- Common and profile-specific behavior: [config/Profiles.psd1](config/Profiles.psd1)
- Common applications: [config/packages.common.json](config/packages.common.json)
- WORK application additions: [config/packages.work.json](config/packages.work.json)
- Windows and app removal behavior: [modules/SystemSetup/SystemSetup.psm1](modules/SystemSetup/SystemSetup.psm1)
- Sync-backed links and state: [modules/SyncProfile/SyncProfile.psm1](modules/SyncProfile/SyncProfile.psm1)
- LGPO values: [resources/LGPO/global_policy_objects.txt](resources/LGPO/global_policy_objects.txt)
- Windows Terminal settings: [resources/Windows Terminal/settings.json](resources/Windows%20Terminal/settings.json)

The `AllowTelemetry` policy is owned by the LGPO resource rather than duplicated in the registry configuration.

## Validate and test

Run the local validator with Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\validate.ps1
```

Run Pester tests when Pester is installed:

```powershell
Invoke-Pester -Path .\tests
```

CI runs the validator, PSScriptAnalyzer, and Pester. The installer is rerunnable but not transactional; restoring removed policies, services, capabilities, or applications is manual.
