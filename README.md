# Windows Install Scripts

Opinionated, interactive provisioning for personal and work Windows computers. It installs applications with WinGet, links synchronized data to `C:\Apps` and `C:\Apps-data`, restores selected settings, applies Windows and Edge policies, and removes unwanted packages.

> [!WARNING]
> This installer runs as administrator and has no automatic rollback. It disables automatic Windows Update, Edge SmartScreen, telemetry-related features, services, and scheduled tasks; HOME also creates placeholder MDM enrollment entries. Review [system-tweaks.ps1](lib/system-tweaks.ps1), [LGPO policy](resources/LGPO/global_policy_objects.txt), and [app removal](06-remove-bloatware.ps1) before running. Create a backup or restore point first.

## Requirements

- Windows 10, Windows 11, or Windows Server 2025
- Windows PowerShell 5.1 and WinGet/App Installer
- Internet access and an interactive UAC session
- Administrator credentials
- One supported sync client already installed and synchronized
- NTFS volumes supporting junctions and symbolic links

This workflow is interactive and is not intended for unattended or managed deployment.

## Sync layout

The selected sync root comes from:

| Client | Location source |
| --- | --- |
| OneDrive Business | `OneDriveCommercial` |
| OneDrive | `OneDriveConsumer` |
| Dropbox | `%APPDATA%\Dropbox\info.json` |

Dropbox is discovered from its account metadata; no custom environment variable is required. If Dropbox has multiple accounts, the installer selects the only account containing both required folders and stops if the result is missing or ambiguous. The sync root must contain:

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

Optional private data can be stored as follows:

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
    ├── All\
    ├── Home\
    └── Work\
```

`Shortcuts\All` is copied first, followed by `Home` or `Work`; target-specific shortcuts can therefore override common ones. Keep account data, exported application state, geographic settings, and other private files under `Apps-data`, not in this repository.

## Run

Local checkout:

```powershell
.\00-run-install.cmd
```

Remote bootstrap:

```powershell
irm https://raw.githubusercontent.com/erikwihlborg76/windows-install-scripts/main/install.ps1 | iex
```

For the safer inspect-first approach:

```powershell
$url = 'https://raw.githubusercontent.com/erikwihlborg76/windows-install-scripts/main/install.ps1'
irm $url -OutFile "$env:TEMP\windows-install.ps1"
notepad "$env:TEMP\windows-install.ps1"
& "$env:TEMP\windows-install.ps1"
```

The bootstrap supports `INSTALL_REPOSITORY`, `INSTALL_REF`, and optional `INSTALL_ARCHIVE_SHA256` environment-variable overrides.

## Flow

1. Select HOME or WORK and the sync client.
2. Validate the sync root and required folders.
3. Detect Windows, update the boot-menu label, and create junctions.
4. Restore private settings and Start-menu shortcuts.
5. Install the configured WinGet packages.
6. Apply registry tweaks, LGPO policy, Terminal/PowerToys settings, and power changes.
7. Remove configured applications, AppX packages, and capabilities.

### Target differences

| Behavior | HOME | WORK |
| --- | ---: | ---: |
| Computer rename prompt | Yes | No |
| Placeholder MDM entries | Yes | No |
| Disable NTFS last-access updates | Yes | No |
| Install Node.js LTS | No | Yes |
| Explicitly remove Teams | Yes | No |
| Shortcut overlay | `Home` | `Work` |

Common packages include Visual Studio Code, foobar2000, PowerToys, 1Password, Total Commander, X-Mouse Button Control, Paint.NET, Windows Terminal, PowerShell 7, Notion, Git, and LGPO.

## Customize

- Package installs: [04-install-apps.ps1](04-install-apps.ps1)
- App removal: [06-remove-bloatware.ps1](06-remove-bloatware.ps1)
- Links, private settings, and shortcuts: [03-preconfigure-system.ps1](03-preconfigure-system.ps1)
- Registry, policy, power, and application settings: [lib/system-tweaks.ps1](lib/system-tweaks.ps1)
- Junction/copy helper behavior: [lib/links-and-copy.ps1](lib/links-and-copy.ps1)
- LGPO values: [resources/LGPO/global_policy_objects.txt](resources/LGPO/global_policy_objects.txt)
- Terminal settings: [resources/Windows Terminal/settings.json](resources/Windows%20Terminal/settings.json)

Run `powershell.exe -NoProfile -File .\tools\validate.ps1` after making changes.

Reusable logic belongs in `lib`, public static configuration in `resources`, and personal configuration under `Apps-data`.

## Logs and behavior

Logs are written under `%TEMP%`:

- `04-install-apps_winget.log`
- `05-postconfigure-system.log`
- `06-remove-bloatware.log`
- `LGPO.stdout.log` and `LGPO.stderr.log`

Fatal errors stop the workflow. Post-configuration and removal warnings are logged but do not block later steps. The installer is mostly rerunnable, but it is not transactional; restoring removed policies, services, capabilities, or applications is manual.

The local validator and GitHub Actions check required files, PowerShell 5.1 syntax, and JSON resources. No software license has been selected yet.
