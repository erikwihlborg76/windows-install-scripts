# Windows Terminal preferences

The installer applies [selected preferences](../resources/Windows%20Terminal/settings.json)
through `Set-RepositoryApplicationDefaults` in both `FULL` and `CONFIGURE_AND_INSTALL`.
This resource is a partial settings patch, not a complete Terminal profile. It manages:

- Copy formatting (`none`) and copy on selection (`false`).
- The default profile (Windows PowerShell).
- The profile default color scheme (`One Half Dark`). Explicit per-profile schemes retain precedence.
- `Ctrl+C` for copy, `Ctrl+V` for paste, and `Alt+Shift+D` for duplicating a pane.

Terminal's [JSON fragments](https://learn.microsoft.com/en-us/windows/terminal/json-fragment-extensions)
support profiles and color schemes, but these global preferences and the default
color scheme for all profiles require edits to `settings.json`. The PowerShell
updater changes individual values and merges shortcuts by key chord. It preserves
existing profiles, custom actions, other shortcuts, themes, color schemes, tab
menus, comments, and unrelated settings. Empty arrays and generated profile entries
from the old full-file template are no longer applied.

The three shortcuts use explicit copy, paste, and duplicate-pane commands with
repository-owned `User.WindowsInstall.*` action IDs. Custom definitions of Terminal's
built-in action IDs therefore cannot change what these shortcuts do. Action commands
are updated by ID; other actions and their labels remain intact. The command shapes
follow the [Terminal action reference](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/actions).

Both JSON comments and trailing commas are supported. If an existing shortcut
conflicts with a managed chord, only that chord is reassigned; other chords and
legacy action definitions are retained. Reapplying identical preferences does not
rewrite the file or create another backup.

Close Windows Terminal before applying preferences. When Terminal is running,
setup warns and skips this phase so the app cannot overwrite the changes. To apply
repository application preferences without running the entire installer, use the
following from a Windows PowerShell console after closing the affected applications:

```powershell
Import-Module .\modules\SystemSetup\SystemSetup.psd1 -Force
Set-RepositoryApplicationDefaults -ResourcesRoot (Resolve-Path .\resources).Path
```

The updater detects Stable and Preview package folders and the standard unpackaged
location under `%LOCALAPPDATA%\Microsoft\Windows Terminal`. Custom portable locations
are not discovered. If no location exists, launch Terminal once, close it, and retry.
An existing file is backed up beside itself as `settings.json.backup-<timestamp>-<id>`
before atomic replacement. Restore that backup with Terminal closed if needed.
Changed files use UTF-8; backups preserve the original bytes. Invalid settings,
unsupported container shapes, filesystem-linked settings files, and files changed
during preparation are left untouched and reported as warnings.
