# Configuration

[Back to the README](../README.md).

The installer supports Windows 11 client installations only, with Windows 11 Enterprise as the primary target. It checks the actual OS build and installation type before elevation or setup. Windows 10 and Windows Server are rejected, including Server builds that share a build number with Windows 11. HOME and WORK are setup profiles, not Windows editions.

## What setup changes

Every mode applies the registry settings and Local Group Policy in this repository, configures selected services, scheduled tasks, and power settings, and removes selected WinGet, AppX, provisioned AppX, and Windows capability entries. `CONFIGURE_AND_INSTALL` installs the application bundle and applies its preferences before Windows configuration. `FULL` also prepares private sync links first.

The installer is rerunnable but not transactional. Restoring removed policies, services, capabilities, or applications is manual. Application file backups do not provide rollback for Windows configuration or software removal.

## Edition and management requirements

Regular Windows 11 Enterprise supports the reviewed Enterprise policies; IoT Enterprise or Education is not generally required. The installer still accepts other Windows 11 editions, but unsupported policies may be ignored. No reviewed setting requires IoT Enterprise specifically instead of regular Enterprise.

| Setting or group | Requirements and limits |
| --- | --- |
| `DisableWindowsConsumerFeatures`, broad Spotlight controls, Windows tips, and cloud-content restrictions | [Enterprise, Education, or IoT Enterprise](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowwindowsconsumerfeatures). Pro/Home editions are not supported for these controls. |
| `AllowTelemetry=0` | [Diagnostic data off is supported on Enterprise and Education](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-system#allowtelemetry); qualifying IoT Enterprise variants follow their SKU/build support. Pro/Home treat zero as required diagnostic data rather than off. This controls Windows diagnostic data, not all application telemetry. |
| `RemoveDefaultMicrosoftStorePackages` | The [deployment guide](https://learn.microsoft.com/en-us/windows/configuration/policy-based-inbox-app-removal/policy-based-inbox-app-removal) specifies managed Windows 11 24H2+ Enterprise/Education devices, current ADMX templates, and deployment prerequisites. The [CSP reference](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-applicationmanagement#removedefaultmicrosoftstorepackages) also lists IoT Enterprise but still labels the setting Insider Preview. Verify the target build; the installer's direct AppX/provisioned-package removal remains a separate mechanism. |
| Edge `BingAdsSuppression=1` | Requires an [eligible K–12 EDU tenant identified by Microsoft](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/bingadssuppression). Windows Education or IoT Enterprise alone does not qualify. Affects Bing searches, including enforced Strict SafeSearch; it does not affect the configured Google provider. |
| Edge managed-device and account policies | Follow each policy's device-management and profile requirements. A Windows Enterprise license alone does not make a device AD/Entra-joined or MDM-enrolled, or make a personal Edge profile eligible for every policy. |
| Widget board and lock-screen widget switches | Microsoft still lists [`DisableWidgetsBoard` and `DisableWidgetsOnLockScreen`](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-newsandinterests) for Insider Preview. The general `AllowNewsAndInterests=0` policy is documented for Windows 11 21H2+; the newer switches are supplementary. |

Version limits also matter on Enterprise: `HideRecommendedSection` and `HideTaskViewButton` require Windows 11 22H2+, while Start account-notification suppression and the enforced taskbar Search mode are documented for 24H2+. See the [policy details](policy-options.md) and [audit resolutions](registry-audit.md#resolution-of-the-original-findings).

## Windows and Edge customizations

Both profiles aim to remove distractions from the Windows UI: Start recommendations, feeds, search suggestions, tips, and extra animations and sounds. The [Windows settings](../config/Profiles.psd1) are paired with [Edge policies](../resources/LGPO/global_policy_objects.txt) that target the same goal in the browser. Edge uses Google search and a blank new-tab page, with shopping, Rewards, recommendations, default-browser/Bing campaigns, AutoFill prompts, and sidebar/Copilot entry points suppressed. Windows policies also suppress Search highlights, account prompts, feedback requests, and Spotlight suggestions. Availability depends on the Windows edition, Edge version, and account type.

**Edge policy limits:**

- Some policies, such as [the new-tab URL](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/newtabpagelocation), require Edge to recognize the device as AD-joined, Entra-joined, or MDM-managed. Setup no longer creates placeholder enrollment records in HOME. Those records did not constitute real enrollment or guarantee support; existing enrollment/provisioning records are not deleted automatically.
- Personal Microsoft accounts can use policies, but [some policies exclude personal-account profiles](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies). Microsoft [confirmed an exception in Edge 116](https://techcommunity.microsoft.com/discussions/edgeinsiderenterprise/edge-116-beta-policies-are-blocked-if-mdm-managed--userprofile-sync-personal-acc/3904955/replies/3905898/) for a single personal-account profile with no work profile. Multiple-profile setups fall outside that exception and personal profiles may ignore some policies. This is not a documented guarantee that the first profile receives every policy and only subsequent profiles are restricted.
- [Check applied policies](https://learn.microsoft.com/en-us/deployedge/configure-microsoft-edge#3-test-your-policies) at `edge://policy` in each Edge profile. Inspect the values and status for ignored policies or errors; a listed policy is not necessarily enforced. Restart Edge after setup if needed.

## Virtual desktops

The `WORK` profile configures **Plan**, **Work**, **Meet**, and **Play** in every setup mode, including `CONFIGURE_ONLY`. It reuses the first four desktops and creates any that are missing; extra desktops are preserved, and reruns do not add duplicates. `HOME` skips this step. The first setup run downloads the [VirtualDesktop CLI](https://github.com/MScholtes/VirtualDesktop) version 1.21 for the Windows build and verifies its SHA-256 checksum before use. The tool is cached under `%LOCALAPPDATA%\WindowsInstallScripts\Tools\VirtualDesktop`. The Windows 11 executable is selected for pre-24H2 or 24H2-and-later builds. An unsupported shell API or failed download is reported as a setup warning.

`CONFIGURE_ONLY` creates the WORK desktops but skips application installation, mouse mappings, and FancyZones layout application. In application-install modes, either profile uses the same CLI to apply FancyZones across existing virtual desktops. HOME preserves existing desktops without creating or naming them, and can still apply the layout and mouse controls.

See the [productivity setup](../README.md#productivity-setup) for the layout and controls.

## Desktop and lock-screen images

Every setup mode, for both HOME and WORK, applies [020.jpg](../resources/Wallpapers/020.jpg) as the wallpaper on all monitors and all existing virtual desktops, including any WORK desktops created during that run. [048.jpg](../resources/Wallpapers/048.jpg) becomes the current user's lock-screen image. This runs independently of application installation, PowerToys, and private sync files.

Setup copies both files to `%LOCALAPPDATA%\WindowsInstallScripts\Wallpapers`, so the images remain available after the downloaded installer folder is removed. It uses Windows' [desktop wallpaper API](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-idesktopwallpaper-setwallpaper), the existing pinned VirtualDesktop CLI's `/AllWallpapers` command, and the [lock-screen API](https://learn.microsoft.com/en-us/uwp/api/windows.system.userprofile.lockscreen.setimagefileasync). It does not enforce a lock-screen policy restricted to Enterprise/Education. Windows may reject changes because of an existing organization policy; failures are included in the setup warnings. Use 64-bit Windows PowerShell: the lock-screen API does not support an x86 console on x64 Windows.

## Customize

| File or folder | Controls |
| --- | --- |
| [config/Profiles.psd1](../config/Profiles.psd1) | Common Windows configuration, HOME/WORK differences, and software removals |
| [config/packages.common.json](../config/packages.common.json) | Application bundle shared by both profiles |
| [config/packages.work.json](../config/packages.work.json) | Additional applications for WORK |
| [resources](../resources) | Application preferences and Local Group Policy |
| [modules/SystemSetup](../modules/SystemSetup) | Windows operations and application preference handling |

The `AllowTelemetry` policy is owned by the LGPO resource rather than duplicated in the registry configuration. Review both when changing privacy settings.

See [distraction-control policies](policy-options.md) for the configured Windows 11 and Edge controls, Google search settings, and their support limits.
