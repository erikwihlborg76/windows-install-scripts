# Personal setup with FULL

`FULL` is the author's personal workflow. It applies the same Windows configuration,
application installation, and repository preferences as `CONFIGURE_AND_INSTALL`,
and also uses private files from OneDrive or Dropbox. The sync links are prepared
before application installation. Choose either general setup mode if you do not
have this private folder layout.

From the repository root:

```powershell
.\Install.ps1 -Profile HOME -SyncProvider OneDrive
.\Install.ps1 -Profile WORK -SyncProvider Dropbox
```

Select `FULL` at the mode prompt each time. Use `-SyncRoot 'D:\My sync folder'` to
override provider discovery. Both `Apps` and `Apps-data` must exist under that root,
even if individual application sources are
missing. Optional sources are skipped; existing normal folders are preserved
rather than replaced with links.

## Sync layout

FULL resolves the selected sync root from:

| Provider | Location source |
| --- | --- |
| OneDrive Business | `OneDriveCommercial` |
| OneDrive | `OneDriveConsumer` |
| Dropbox | `%APPDATA%\Dropbox\info.json`, falling back to `%LOCALAPPDATA%\Dropbox\info.json` |

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
%USERPROFILE%\.ssh\config
```

The SSH config contains `Include c:/Apps-data/SSH/config`, so OpenSSH loads the
configuration stored under the sync-backed `Apps-data\SSH` directory. Existing
SSH settings retain precedence, and the include is placed in an unconditional
`Host *` block when extending an existing config. Rerunning setup does not add
another include.

Optional sync-backed state can use:

```text
Apps-data\
├── .openhue\
├── GHISLER\
├── SSH\config
└── Shortcuts\
```

Everything under `Apps-data\Shortcuts` is copied to the current user's Start menu. Personal and private data should remain under `Apps-data`; reviewed application defaults live in this repository.
Copies use bounded retries and retain diagnostics if a file cannot be copied.
