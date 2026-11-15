# Policies for a quieter Windows 11 and Edge setup

Reviewed against Microsoft documentation on 2026-11-15. All distraction controls
listed below are configured in the shared [LGPO resource](../resources/LGPO/global_policy_objects.txt)
and imported in every setup mode for both HOME and WORK. Windows and Edge ignore
policies they do not support; importing a policy does not guarantee enforcement.

This suppresses Edge recommendations and default-browser/Bing campaigns, Windows
Search highlights, Start account notifications, and other promotional content.
It also disables all covered Edge AutoFill categories and Windows Spotlight
experiences, including some useful reminders and background images. App and site
notifications are not blocked globally.

## Google search

Edge's mandatory [default search provider](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/defaultsearchprovidersearchurl)
is Google, with the name `Google`, keyword `google.com`, search URL
`https://www.google.com/search?q={searchTerms}`, and Google search suggestions.
The new-tab page remains blank; if the standard new-tab page is shown instead,
[NewTabPageSearchBox=redirect](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/newtabpagesearchbox)
routes its search box through the address bar and the configured search engine.
These search policies exclude personal Microsoft-account profiles in Microsoft's
support metadata, so check the effective provider in each profile at `edge://policy`.

## Windows policies

All entries below are DWORD values. Microsoft lists Pro, Enterprise, Education,
and IoT editions for these policies; Windows Home edition is not listed. The
installer's HOME profile is unrelated to the installed Windows edition.

| Policy and value | Registry location | Effect and limits |
| --- | --- | --- |
| [AllowSearchHighlights](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-search#allowsearchhighlights): `EnableDynamicContentInWSB=0` | `HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search` | Removes highlighted/trending content in Search home and Start search. Documented for Windows 11 22H2+, and 21H2 with KB5023774. Useful even when the taskbar Search box is hidden. |
| [DisableAccountNotifications](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-notifications#disableaccountnotifications): `DisableAccountNotifications=1` | `HKCU\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\AccountNotifications` | Windows 11 24H2+: suppresses Start user-tile account prompts, including subscription/cloud-storage promotion. Also suppresses useful account reauthentication and backup reminders. |
| [DisableAdvertisingId](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-privacy#disableadvertisingid): `DisabledByGroupPolicy=1` | `HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo` | Enforces the advertising-ID restriction rather than only setting the existing per-user preference. Does not block all ads. |
| [AllowTailoredExperiencesWithDiagnosticData](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowtailoredexperienceswithdiagnosticdata): `DisableTailoredExperiencesWithDiagnosticData=1` | `HKCU\SOFTWARE\Policies\Microsoft\Windows\CloudContent` | Enforces the existing privacy intention. Prevents diagnostic-data-based personalization, but does not remove every tip or offer. |
| [AllowThirdPartySuggestionsInWindowsSpotlight](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowthirdpartysuggestionsinwindowsspotlight): `DisableThirdPartySuggestions=1` | `HKCU\SOFTWARE\Policies\Microsoft\Windows\CloudContent` | Suppresses third-party Spotlight suggestions while retaining the rest of Spotlight. |
| [DoNotShowFeedbackNotifications](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#donotshowfeedbacknotifications): `DoNotShowFeedbackNotifications=1` | `HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection` | A documented policy alternative to relying on the partially configured per-user feedback-frequency preference. |

### Policies with narrower edition support

These are documented for Enterprise/Education/IoT, not general Pro/Home deployments.
They are included in the policy file, but other editions may ignore them. The
WORK profile does not imply that a supported Windows edition is installed.

| Value | Hive and key | Effect |
| --- | --- | --- |
| [DisableWindowsSpotlightFeatures=1](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowwindowsspotlight) | `HKCU\SOFTWARE\Policies\Microsoft\Windows\CloudContent` | Broad Spotlight shutdown; also changes desirable background-image experiences. |
| [DisableWindowsSpotlightOnSettings=1](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowwindowsspotlightonsettings) | Same user key | Suppresses suggestions in Settings. |
| [DisableWindowsSpotlightWindowsWelcomeExperience=1](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowwindowsspotlightwindowswelcomeexperience) | Same user key | Suppresses the welcome/what's-new experience after updates. |
| [DisableSoftLanding=1](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowwindowstips) | `HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent` | Turns off Windows tips. |
| [DisableConsumerAccountStateContent=1](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#disableconsumeraccountstatecontent) | Same machine key | Uses fallback content instead of cloud consumer account-state content. |
| [DisableCloudOptimizedContent=1](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#disablecloudoptimizedcontent) | Same machine key | Uses fallback content instead of cloud-optimized content. Consider provisioning timing; this is not a universal late-install cleanup switch. |

## Edge policies

Except for the JSON policy noted below, these are DWORD values under
`HKLM\SOFTWARE\Policies\Microsoft\Edge`. Personal-account eligibility is taken
from each policy's support metadata; actual status should be checked in each
profile at `edge://policy` after restarting Edge.

| Policy and configured value | Minimum Edge on Windows | Personal Microsoft account | Effect and limits |
| --- | --- | --- | --- |
| [SpotlightExperiencesAndRecommendationsEnabled=0](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/spotlightexperiencesandrecommendationsenabled) | 86 | ✅ | Suppresses Microsoft-service Spotlight suggestions, notifications, and tips alongside `ShowRecommendationsEnabled=0`. Requires browser restart. |
| [DefaultBrowserSettingsCampaignEnabled=0](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/defaultbrowsersettingscampaignenabled) | 113 | ✅ | Suppresses campaigns asking to switch the default browser to Edge or the default search engine to Bing. Does not prevent normal manual default-app changes. |
| [PinningWizardAllowed=0](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/pinningwizardallowed) | 80 | ✅ | Disables the suggested-site taskbar pinning wizard, including its manual menu entry. |
| [PersonalizationReportingEnabled=0](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/personalizationreportingenabled) | 80 | ✅ | Prevents using browsing data for Microsoft advertising/service personalization. Intended for eligible personal accounts; unavailable for enterprise and child accounts. Does not block all ads. |
| [ShowPDFDefaultRecommendationsEnabled=0](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/showpdfdefaultrecommendationsenabled) | 93 | ❌ | Suppresses prompts to make Edge the default PDF reader. Personal-account support is not documented. Requires browser restart. |
| [MicrosoftEdgeInsiderPromotionEnabled=0](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/microsoftedgeinsiderpromotionenabled) | 98 | ❌ | Hides Insider-channel promotion on About Edge. |

The new-tab app launcher is disabled as well. Existing policies keep new tabs
blank and suppress feeds, quick links, shopping, Rewards, sidebar, and Copilot
entry points.

### Newer AutoFill replacement

[AutofillSettings](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/autofillsettings)
is available from Edge 154. It uses a REG_SZ JSON list instead of individual DWORD
switches and supersedes the now-deprecated address/card AutoFill policies. The
configured value is:

```json
[{"url_pattern":"*","blocked_types":["all"]}]
```

This blocks filling and saving all covered AutoFill categories, including useful
contact/travel data. The older address/card switches remain disabled for browsers
that do not support the newer policy. Microsoft's metadata excludes personal
Microsoft-account profiles from `AutofillSettings`.

The repo already contains recent Copilot controls: `CopilotNewTabPageEnabled`
and `M365LinksAutoOpenCopilotEnabled` require Edge 148, while
`CopilotAddressBarSuggestionsEnabled` requires 149. Older Edge versions cannot
apply policies introduced in those versions.

## Avoid redundant or obsolete additions

- Do not add `PromotionalTabsEnabled`: it is deprecated in favor of the already
  configured [ShowRecommendationsEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/promotionaltabsenabled).
- Do not use [NewTabPageSetFeedType](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/newtabpagesetfeedtype): it stopped working after Edge 92. The existing new-tab content and blank-page policies are the relevant controls.
- `AddressBarMicrosoftSearchInBingProviderEnabled` and `EdgeFollowEnabled` are
  obsolete. The LGPO resource deletes their previous assignments on reruns.
  The [registry audit](registry-audit.md) preserves the earlier review and other
  settings needing cleanup.

[Back to configuration](configuration.md).
