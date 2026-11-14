# Windows Install Scripts

Opinionated, interactive provisioning for personal and work Windows computers.

Apply Windows configuration and remove selected bundled apps, with the option to
install a curated application set and its preferences. The two general setup modes
work directly from this repository, without OneDrive, Dropbox, or private files.

> [!WARNING]
> This installer runs as administrator and has no automatic rollback. It disables automatic Windows Update, Edge SmartScreen, telemetry-related features, services, and scheduled tasks. The `HOME` profile also creates placeholder MDM enrollment entries. Review the [profile configuration](config/Profiles.psd1), [LGPO policy](resources/LGPO/global_policy_objects.txt), and [Windows operations](modules/SystemSetup/SystemSetup.psm1) before running. Create a backup or restore point first.

## Quick start

Run from **Windows PowerShell 5.1**. The installer requests administrator access,
shows the setup plan, and asks for confirmation before applying it.

Download and start the interactive installer:

```powershell
irm https://raw.githubusercontent.com/erikwihlborg76/windows-install-scripts/main/00-install.ps1 | iex
```

From a local checkout, choose the setup mode when prompted:

```powershell
# Choose the mode and profile interactively.
.\00-run-install-manual.cmd

# Or supply the WORK profile and choose the mode interactively.
.\Install.ps1 -Profile WORK
```

## Choose a setup mode

| Mode | Configure Windows and remove apps | Install applications | Use sync-backed files |
| --- | --- | --- | --- |
| `CONFIGURE_ONLY` | ✅ | ❌ | ❌ |
| `CONFIGURE_AND_INSTALL` | ✅ | ✅ | ❌ |
| `FULL` — author's personal setup | ✅ | ✅ | ✅ |

Do not use the  `FULL` option as it depends on the author's personal sync folder.

The installer always asks you to select a mode, with no default selection.
Setup modes cannot be supplied through command-line parameters.

### Choose a HOME or WORK profile

The profile controls configuration differences independently of the setup mode.
Both profiles use the same common Windows configuration and application bundle.

| Profile behavior | `HOME` | `WORK` |
| --- | --- | --- |
| Prompt to rename the computer | ✅ | ❌ |
| Create placeholder MDM enrollment entries | ✅ | ❌ |
| Add Node.js LTS when installing the application bundle | ❌ | ✅ |
| Explicitly remove Microsoft Teams | ✅ | ❌ |
| Configure Plan, Work, Meet, and Play virtual desktops | ❌ | ✅ |

The `WORK` profile configures these four desktops in every setup mode, including
`CONFIGURE_ONLY`. It reuses the first four desktops and creates any that are missing;
extra desktops are preserved, and reruns do not add duplicates. `HOME` skips this step.
The first WORK run downloads the [VirtualDesktop CLI](https://github.com/MScholtes/VirtualDesktop)
version 1.21 for the Windows build and verifies its SHA-256 checksum before use.
The tool is cached under `%LOCALAPPDATA%\WindowsInstallScripts\Tools\VirtualDesktop`.
This step requires Windows 10 2004 or later, Windows 11, or a compatible desktop
Windows Server installation. An unsupported shell API or failed download is reported
as a setup warning.

The same CLI is used in either profile when applying FancyZones across existing
virtual desktops after application installation. HOME still skips creating or naming
desktops.

## Windows and Edge customizations

Both profiles aim to remove distractions from the Windows UI: Start recommendations,
feeds, search suggestions, tips, and extra animations and sounds. The
[Windows settings](config/Profiles.psd1) are paired with
[Edge policies](resources/LGPO/global_policy_objects.txt) that target the same goal
in the browser, suppressing new-tab content, shopping and Rewards features, and
sidebar/Copilot entry points. Availability depends on the Windows and Edge versions.

**Edge policy limits:**

- Some policies, such as [the new-tab URL](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/newtabpagelocation),
  require Edge to recognize the device as AD-joined, Entra-joined, or MDM-managed.
  `HOME` creates placeholder MDM registry entries as an unofficial workaround;
  this does not actually join a domain or enroll the device, and may not work in
  every Edge version.
- Personal Microsoft accounts can use policies, but
  [some policies exclude personal-account profiles](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies).
  Microsoft [confirmed an exception in Edge 116](https://techcommunity.microsoft.com/discussions/edgeinsiderenterprise/edge-116-beta-policies-are-blocked-if-mdm-managed--userprofile-sync-personal-acc/3904955/replies/3905898/)
  for a single personal-account profile with no work profile. Multiple-profile
  setups fall outside that exception and personal profiles may ignore some
  policies. This is not a documented guarantee that the first profile receives
  every policy and only subsequent profiles are restricted.
- [Check applied policies](https://learn.microsoft.com/en-us/deployedge/configure-microsoft-edge#3-test-your-policies)
  at `edge://policy` in each Edge profile. Inspect the values and status for ignored
  policies or errors; a listed policy is not necessarily enforced. Restart Edge
  after setup if needed.

## Productivity setup

Select the **WORK** profile and **CONFIGURE_AND_INSTALL** for the complete desktop
and window-management setup. WORK creates or reuses four virtual desktops named
**Plan**, **Work**, **Meet**, and **Play**. After PowerToys is installed, setup applies
the custom FancyZones layout to every monitor on every virtual desktop.

![WORK productivity setup: Plan, Work, Meet, and Play desktops share a narrow left zone, a wide right zone, and an overlapping full-screen zone. Mouse side buttons switch desktops; Ctrl+Alt+PgUp/PgDn or Ctrl+Alt+mouse wheel cycles windows within a zone.](docs/assets/productivity-setup.svg)

The layout provides a narrow left zone, a wider right zone, and a full-screen zone
that overlaps both. Place multiple windows in the same zone, then cycle between
them to bring the window you need into focus.

| Action | Control | Requires |
| --- | --- | --- |
| Switch to the previous virtual desktop | Mouse back button | X-Mouse Button Control |
| Switch to the next virtual desktop | Mouse forward button | X-Mouse Button Control |
| Cycle to the previous window in the same FancyZones zone | `Ctrl + Alt + PgUp` | PowerToys FancyZones |
| Cycle to the next window in the same FancyZones zone | `Ctrl + Alt + PgDn` | PowerToys FancyZones |
| Cycle windows in the same zone using the mouse | Hold `Ctrl + Alt` and scroll up/down | PowerToys FancyZones and X-Mouse Button Control |

Keep PowerToys FancyZones and X-Mouse Button Control running, with the repository's
preferences applied. X-Mouse Button Control supplies the mouse mappings; FancyZones
handles cycling among windows in a zone.

WORK also creates the named desktops in **CONFIGURE_ONLY**, but that mode skips
application installation, mouse mappings, and FancyZones layout application. HOME
keeps your existing virtual desktops; application-install modes can still apply
the same layout and controls to them.

## Included applications

The table reflects [the common package manifest](config/packages.common.json) and
[the WORK additions](config/packages.work.json). `CONFIGURE_AND_INSTALL` and `FULL`
install the same applications; `FULL` additionally restores private personal state.

| Application or tool | `CONFIGURE_AND_INSTALL` | `CONFIGURE_ONLY` | `FULL` |
| --- | --- | --- | --- |
| Visual Studio Code | ✅ | ❌ | ✅ |
| foobar2000 | ✅ | ❌ | ✅ |
| Microsoft PowerToys | ✅ | ❌ | ✅ |
| 1Password | ✅ | ❌ | ✅ |
| Total Commander | ✅ | ❌ | ✅ |
| X-Mouse Button Control | ✅ | ❌ | ✅ |
| Paint.NET | ✅ | ❌ | ✅ |
| Windows Terminal | ✅ | ❌ | ✅ |
| PowerShell | ✅ | ❌ | ✅ |
| Notion | ✅ | ❌ | ✅ |
| Git | ✅ | ❌ | ✅ |
| Node.js LTS | `WORK` only | ❌ | `WORK` only |
| LGPO policy tool | ✅ | If missing | ✅ |

LGPO applies the repository's Local Group Policy configuration; it is a setup
requirement even when the application bundle is skipped. WinGet is required in
all modes. The installer also checks Windows activation when installing the bundle.

### Included application preferences

`CONFIGURE_AND_INSTALL` and `FULL` apply these settings from the repository:

| Application | Preferences |
| --- | --- |
| [Windows Terminal](resources/Windows%20Terminal/settings.json) | Copy behavior, default shell, color scheme, and keyboard shortcuts |
| [X-Mouse Button Control](resources/X-Mouse%20Button%20Control/XMBCSettings.xml) | Mouse button mappings and application profiles |
| [FancyZones](resources/PowerToys/FancyZones) | Preferences and custom window layouts |
| [Light Switch](resources/PowerToys/LightSwitch/settings.json) | Theme, schedule, and shortcut preferences |
| [Command Palette](resources/PowerToys/CommandPalette/settings.json) | Preferences and provider selections |
| [foobar2000](resources/foobar2000-v2) | Configuration, theme, keyboard shortcuts, and Radio Paradise playlists |

Close the affected applications before applying preferences. Running apps are
skipped with a warning. Launch Terminal or Command Palette once if its settings
location has not been initialized, then close it and rerun setup.

After application settings and virtual desktops have been configured, setup applies
the saved FancyZones layout to every monitor on every existing virtual desktop.
It runs `PowerToys.FancyZones.CLI.exe set-layout "{EF0B1504-D1C0-4598-9379-ED52A2CA9CDB}" --all`
on each desktop, then restores your starting desktop, including on failure. The UUID
is read from the repository's custom layout file. `--all` targets monitors, so setup
briefly visits each virtual desktop. PowerToys is started in the background if needed;
FancyZones must be enabled. `CONFIGURE_ONLY` skips layout application.

When X-Mouse Button Control is installed, application setup also creates
`X-Mouse Button Control.lnk` in the current user's Startup folder with
`/notportable /delay /NoLog`. It checks both Program Files locations and skips the
shortcut if the executable is absent. This is part of the application preferences
phase; `CONFIGURE_ONLY` does not add an X-Mouse autorun entry.

The VS Code File Explorer context menu is registered after the application bundle
is installed, using `Common.ApplicationRegistry` in `config/Profiles.psd1`.
`CONFIGURE_ONLY` skips these application-specific registry entries.

Existing application settings are backed up before changes; identical settings are
left untouched. Light Switch keeps locally configured coordinates, which are not
stored in this repository. Configure your location on a new computer for sunrise
and sunset scheduling. Application changes made later stay local; they do not
update repository defaults automatically.

To apply just the repository application preferences from a local checkout:

```powershell
Import-Module .\modules\SystemSetup\SystemSetup.psd1 -Force
Set-RepositoryApplicationDefaults -ResourcesRoot (Resolve-Path .\resources).Path
Set-RepositoryFancyZonesLayout -ResourcesRoot (Resolve-Path .\resources).Path
```

This applies preferences for all the listed applications, without installing apps
or changing Windows configuration. See [Terminal preference details](docs/terminal-preferences.md)
for merging behavior and supported installations.

Existing X-Mouse and foobar2000 playlist links are converted to local folders while
preserving their synced sources and unmanaged files. foobar2000 databases with
pending SQLite recovery files are skipped until the app has been opened and closed.

## Requirements

- Windows 10, Windows 11, or Windows Server 2025.
- Windows PowerShell 5.1 and WinGet/App Installer.
- An interactive UAC session and administrator credentials.
- Internet access for application installation and automatic LGPO installation.
- Internet access for the first virtual desktop CLI download (WORK desktop setup or FancyZones layout application).

The installer checks that `winget.exe` can run before presenting a setup plan.
If it is unavailable on Windows 24H2 IoT:

1. Run `wsreset -i` to enable Microsoft Store.
2. Open [App Installer in Microsoft Store](https://apps.microsoft.com/detail/9nblggh4nns1?hl=en-US&gl=EN).
3. Install App Installer, then rerun this installer.

### Inspect the bootstrap before running

```powershell
$url = 'https://raw.githubusercontent.com/erikwihlborg76/windows-install-scripts/main/00-install.ps1'
irm $url -OutFile "$env:TEMP\windows-install.ps1"
notepad "$env:TEMP\windows-install.ps1"
& "$env:TEMP\windows-install.ps1"
```

The bootstrap downloads the repository and starts the interactive installer. Set
`INSTALL_REPOSITORY`, `INSTALL_REF`, or `INSTALL_ARCHIVE_SHA256` to select another
repository, ref, or expected archive hash.

## What setup changes

Every mode applies the registry settings and Local Group Policy in this repository,
configures selected services, scheduled tasks, and power settings, and removes
selected WinGet, AppX, provisioned AppX, and Windows capability entries.
`CONFIGURE_AND_INSTALL` installs the application bundle and applies its preferences
before Windows configuration. `FULL` also prepares private sync links first.

The installer is rerunnable but not transactional. Restoring removed policies,
services, capabilities, or applications is manual. Application file backups do not
provide rollback for Windows configuration or software removal.

A transcript is saved to `%TEMP%\windows-install-<timestamp>.log`. The final summary
lists operations that could not be completed:

| Exit code | Meaning |
| --- | --- |
| `0` | Completed successfully, or cancelled before setup |
| `1` | Stopped on an error |
| `2` | Finished with warnings; review the summary and transcript |

Optional missing private files and already-absent applications are expected skips.
`-SkipConfirmation` skips the setup-plan confirmation; mode selection is still
required. `-NoPause` skips the final pause before exit.

## Customize

| File or folder | Controls |
| --- | --- |
| [config/Profiles.psd1](config/Profiles.psd1) | Common Windows configuration, HOME/WORK differences, and software removals |
| [config/packages.common.json](config/packages.common.json) | Application bundle shared by both profiles |
| [config/packages.work.json](config/packages.work.json) | Additional applications for WORK |
| [resources](resources) | Application preferences and Local Group Policy |
| [modules/SystemSetup](modules/SystemSetup) | Windows operations and application preference handling |

The `AllowTelemetry` policy is owned by the LGPO resource rather than duplicated
in the registry configuration. Review both when changing privacy settings.

## Personal setup: FULL

`FULL` is retained for the author's personal workflow. It installs the same bundle
as `CONFIGURE_AND_INSTALL`, and also uses private OneDrive or Dropbox files for
OpenHue, Total Commander, SSH configuration, and personal Start menu shortcuts.
Those files are not included in this repository.

```powershell
.\Install.ps1 -Profile HOME -SyncProvider OneDrive
```

Select `FULL` at the mode prompt. The selected sync root must contain `Apps` and
`Apps-data`. Use `-SyncRoot` to override provider discovery. See
[the personal setup reference](docs/personal-setup.md)
for the folder layout, links, and provider requirements.

## Development and validation

The repository separates Windows configuration and application preferences in
`modules/SystemSetup` from private sync discovery and links in `modules/SyncProfile`.
`Install.ps1` orchestrates the setup; `00-install.ps1` is the download bootstrap.

Run the local validator with Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\validate.ps1
```

Install the pinned test tools once, then run the same checks as CI:

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser -Force
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\test.ps1
```

The runner also accepts `-PesterModulePath` and `-ScriptAnalyzerModulePath` for
isolated copies of those versions. Tests use temporary files, isolated registry
keys, and mocked setup operations; they do not run the real installer against
Windows settings. CI runs the validator, PSScriptAnalyzer, and Pester.
