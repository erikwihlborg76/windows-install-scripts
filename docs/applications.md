# Included applications

[Back to the README](../README.md).

The table reflects [the common package manifest](../config/packages.common.json) and
[the WORK additions](../config/packages.work.json). `CONFIGURE_AND_INSTALL` and `FULL`
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

## Included application preferences

`CONFIGURE_AND_INSTALL` and `FULL` apply these settings from the repository:

| Application | Preferences |
| --- | --- |
| [Windows Terminal](../resources/Windows%20Terminal/settings.json) | Copy behavior, default shell, color scheme, and keyboard shortcuts |
| [X-Mouse Button Control](../resources/X-Mouse%20Button%20Control/XMBCSettings.xml) | Mouse button mappings and application profiles |
| [FancyZones](../resources/PowerToys/FancyZones) | Preferences and custom window layouts |
| [Light Switch](../resources/PowerToys/LightSwitch/settings.json) | Theme, schedule, and shortcut preferences |
| [Command Palette](../resources/PowerToys/CommandPalette/settings.json) | Preferences and provider selections |
| [foobar2000](../resources/foobar2000-v2) | Configuration, theme, keyboard shortcuts, and Radio Paradise playlists |

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

To apply just the repository application preferences, run from the repository root:

```powershell
Import-Module .\modules\SystemSetup\SystemSetup.psd1 -Force
Set-RepositoryApplicationDefaults -ResourcesRoot (Resolve-Path .\resources).Path
Set-RepositoryFancyZonesLayout -ResourcesRoot (Resolve-Path .\resources).Path
```

This applies preferences for all the listed applications, without installing apps
or changing Windows configuration. See [Terminal preference details](terminal-preferences.md)
for merging behavior and supported installations.

Existing X-Mouse and foobar2000 playlist links are converted to local folders while
preserving their synced sources and unmanaged files. foobar2000 databases with
pending SQLite recovery files are skipped until the app has been opened and closed.
