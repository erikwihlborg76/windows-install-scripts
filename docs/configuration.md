# Configuration

[Back to the README](../README.md).

## What setup changes

Every mode applies the registry settings and Local Group Policy in this repository,
configures selected services, scheduled tasks, and power settings, and removes
selected WinGet, AppX, provisioned AppX, and Windows capability entries.
`CONFIGURE_AND_INSTALL` installs the application bundle and applies its preferences
before Windows configuration. `FULL` also prepares private sync links first.

The installer is rerunnable but not transactional. Restoring removed policies,
services, capabilities, or applications is manual. Application file backups do not
provide rollback for Windows configuration or software removal.

## Windows and Edge customizations

Both profiles aim to remove distractions from the Windows UI: Start recommendations,
feeds, search suggestions, tips, and extra animations and sounds. The
[Windows settings](../config/Profiles.psd1) are paired with
[Edge policies](../resources/LGPO/global_policy_objects.txt) that target the same goal
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

## Virtual desktops

The `WORK` profile configures **Plan**, **Work**, **Meet**, and **Play** in every setup mode, including
`CONFIGURE_ONLY`. It reuses the first four desktops and creates any that are missing;
extra desktops are preserved, and reruns do not add duplicates. `HOME` skips this step.
The first WORK run downloads the [VirtualDesktop CLI](https://github.com/MScholtes/VirtualDesktop)
version 1.21 for the Windows build and verifies its SHA-256 checksum before use.
The tool is cached under `%LOCALAPPDATA%\WindowsInstallScripts\Tools\VirtualDesktop`.
This step requires Windows 10 2004 or later, Windows 11, or a compatible desktop
Windows Server installation. An unsupported shell API or failed download is reported
as a setup warning.

`CONFIGURE_ONLY` creates the WORK desktops but skips application installation,
mouse mappings, and FancyZones layout application. In application-install modes,
either profile uses the same CLI to apply FancyZones across existing virtual
desktops. HOME preserves existing desktops without creating or naming them, and
can still apply the layout and mouse controls.

See the [productivity setup](../README.md#productivity-setup) for the layout and controls.

## Customize

| File or folder | Controls |
| --- | --- |
| [config/Profiles.psd1](../config/Profiles.psd1) | Common Windows configuration, HOME/WORK differences, and software removals |
| [config/packages.common.json](../config/packages.common.json) | Application bundle shared by both profiles |
| [config/packages.work.json](../config/packages.work.json) | Additional applications for WORK |
| [resources](../resources) | Application preferences and Local Group Policy |
| [modules/SystemSetup](../modules/SystemSetup) | Windows operations and application preference handling |

The `AllowTelemetry` policy is owned by the LGPO resource rather than duplicated
in the registry configuration. Review both when changing privacy settings.
