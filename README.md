# Windows Install Scripts

Opinionated, interactive provisioning for personal and work Windows computers. The full workflow installs applications with WinGet, links synchronized data to `C:\Apps` and `C:\Apps-data`, restores selected settings, applies Windows and Edge policies, and removes unwanted packages. A separate tweaks-and-removal workflow skips sync-root setup and application installation.

> [!WARNING]
> This installer runs as administrator and has no automatic rollback. It disables automatic Windows Update, Edge SmartScreen, telemetry-related features, services, and scheduled tasks; HOME also creates placeholder MDM enrollment entries. Review [system tweaks](06-apply-system-tweaks.ps1), [Windows settings](settings/windows.ps1), [LGPO policy](resources/LGPO/global_policy_objects.txt), and [app removal](07-remove-apps.ps1) before running. Create a backup or restore point first.

## Requirements

- Windows 10, Windows 11, or Windows Server 2025
- Windows PowerShell 5.1 and WinGet/App Installer
- An interactive UAC session
- Administrator credentials

The full workflow additionally requires:

- Internet access
- One supported sync client already installed and synchronized
- NTFS volumes supporting junctions and symbolic links

The tweaks-and-removal workflow does not require a sync client and does not install applications. LGPO policy and Windows Terminal settings are applied only when LGPO and Windows Terminal are already installed; otherwise those operations log a warning and continue.

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
```

Everything under `C:\Apps-data\Shortcuts` is copied to the user's Start menu. Keep account data, exported application state, geographic settings, and other private files under `Apps-data`, not in this repository.

## Run

Local checkout:

```powershell
.\00-run-install-manual.cmd
```

The launcher prompts for either the full workflow or **Tweaks and app removal only**. The latter never selects a sync root and runs only `06-apply-system-tweaks.ps1` followed by `07-remove-apps.ps1`.

Remote bootstrap:

```powershell
irm https://raw.githubusercontent.com/erikwihlborg76/windows-install-scripts/main/00-install.ps1 | iex
```

For the safer inspect-first approach:

```powershell
$url = 'https://raw.githubusercontent.com/erikwihlborg76/windows-install-scripts/main/00-install.ps1'
irm $url -OutFile "$env:TEMP\windows-install.ps1"
notepad "$env:TEMP\windows-install.ps1"
& "$env:TEMP\windows-install.ps1"
```

The bootstrap supports `INSTALL_REPOSITORY`, `INSTALL_REF`, and optional `INSTALL_ARCHIVE_SHA256` environment-variable overrides.

## Flow

The full workflow:

1. Select HOME or WORK and the sync client.
2. Validate the sync root and required folders.
3. Create junctions and restore private settings and Start-menu shortcuts.
4. Install the configured WinGet packages.
5. Restore sync-backed PowerToys settings.
6. Apply sync-root-independent computer naming, registry and system settings, LGPO policy, Terminal settings, and power changes.
7. Remove configured applications, AppX packages, and capabilities.

The tweaks-and-removal workflow:

1. Select HOME or WORK without selecting or validating a sync root.
2. Apply the sync-root-independent tweaks from step 6 above.
3. Run the same configured app, AppX, and capability removals.

### Target differences

| Behavior | HOME | WORK |
| --- | ---: | ---: |
| Computer rename prompt | Yes | No |
| Placeholder MDM entries | Yes | No |
| Disable NTFS last-access updates | Yes | No |
| Install Node.js LTS (full workflow only) | No | Yes |
| Explicitly remove Teams | Yes | No |

Full-workflow common packages include Visual Studio Code, foobar2000, PowerToys, 1Password, Total Commander, X-Mouse Button Control, Paint.NET, Windows Terminal, PowerShell 7, Notion, Git, and LGPO.

## Customize

- Package installs: [04-install-apps.ps1](04-install-apps.ps1)
- App removal: [07-remove-apps.ps1](07-remove-apps.ps1)
- Sync-independent system tweaks: [06-apply-system-tweaks.ps1](06-apply-system-tweaks.ps1)
- Links, private settings, and shortcuts: [03-preconfigure-system.ps1](03-preconfigure-system.ps1) and [05-postconfigure-system.ps1](05-postconfigure-system.ps1)
- Registry and Windows behavior: [settings/windows.ps1](settings/windows.ps1)
- Reusable setting operations: [lib/apply-settings.ps1](lib/apply-settings.ps1)
- Junction/copy helper behavior: [lib/links-and-copy.ps1](lib/links-and-copy.ps1)
- LGPO values: [resources/LGPO/global_policy_objects.txt](resources/LGPO/global_policy_objects.txt)
- Terminal settings: [resources/Windows Terminal/settings.json](resources/Windows%20Terminal/settings.json)

Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\validate.ps1` after making changes.

Reusable logic belongs in `lib`, public static configuration in `resources`, and personal configuration under `Apps-data`.

## Logs and behavior

Logs are written under `%TEMP%`:

- `04-install-apps_winget.log`
- `06-apply-system-tweaks.log`
- `05-postconfigure-system.log`
- `07-remove-apps.log`
- `LGPO.stdout.log` and `LGPO.stderr.log`

Fatal errors stop the workflow. System-tweak, synced-setting, and removal warnings are logged but do not block later steps. The installer is mostly rerunnable, but it is not transactional; restoring removed policies, services, capabilities, or applications is manual.

The local validator and GitHub Actions check required files, PowerShell 5.1 syntax, and JSON resources. No software license has been selected yet.
