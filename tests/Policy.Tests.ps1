BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $policyPath = Join-Path $repositoryRoot "resources\LGPO\global_policy_objects.txt"
    $lines = @(Get-Content -LiteralPath $policyPath | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith(";")
    })
    if ($lines.Count % 4 -ne 0) {
        throw "LGPO text must contain complete four-line policy records."
    }
    $records = @(for ($index = 0; $index -lt $lines.Count; $index += 4) {
        [pscustomobject] @{
            Scope = $lines[$index]
            Key = $lines[$index + 1]
            Name = $lines[$index + 2]
            Value = $lines[$index + 3]
        }
    })
    $edge = @{}
    foreach ($record in $records) {
        if ($record.Scope -eq "Computer" -and $record.Key -eq 'SOFTWARE\Policies\Microsoft\Edge') {
            $edge[$record.Name] = $record.Value
        }
    }
}

Describe "Shared Local Group Policy configuration" {
    It "uses complete records, supported LGPO types, and no conflicting assignments" {
        $records.Count | Should -BeGreaterThan 0
        foreach ($record in $records) {
            $record.Scope | Should -BeIn @("Computer", "User")
            $record.Key | Should -Match '^SOFTWARE\\'
            $record.Value | Should -Match '^(DWORD:\d+|SZ:.*|DELETE|DELETEALLVALUES|CREATEKEY)$'
        }
        @($records | Group-Object Scope, Key, Name | Where-Object Count -gt 1) | Should -HaveCount 0
    }

    It "configures a complete Google search provider and redirects new-tab searches to it" {
        $edge.DefaultSearchProviderEnabled | Should -Be "DWORD:1"
        $edge.DefaultSearchProviderName | Should -Be "SZ:Google"
        $edge.DefaultSearchProviderKeyword | Should -Be "SZ:google.com"
        $edge.DefaultSearchProviderSearchURL | Should -Be 'SZ:https://www.google.com/search?q={searchTerms}'
        $edge.DefaultSearchProviderSuggestURL | Should -Be 'SZ:https://www.google.com/complete/search?output=chrome&q={searchTerms}'
        $edge.NewTabPageSearchBox | Should -Be "SZ:redirect"
        $edge.NewTabPageLocation | Should -Be "SZ:about:blank"
        $edge.DefaultBrowserSettingsCampaignEnabled | Should -Be "DWORD:0"
    }

    It "blocks all AutoFill categories on all sites while keeping older-browser fallbacks" {
        $rules = @($edge.AutofillSettings.Substring(3) | ConvertFrom-Json)
        $rules | Should -HaveCount 1
        $rules[0].url_pattern | Should -Be "*"
        @($rules[0].blocked_types) | Should -Be @("all")
        $edge.AutofillAddressEnabled | Should -Be "DWORD:0"
        $edge.AutofillCreditCardEnabled | Should -Be "DWORD:0"
    }

    It "places account and Spotlight user policies in HKCU through User records" {
        foreach ($name in @(
            "DisableAccountNotifications", "DisableTailoredExperiencesWithDiagnosticData",
            "DisableThirdPartySuggestions", "DisableWindowsSpotlightFeatures",
            "DisableWindowsSpotlightOnSettings", "DisableWindowsSpotlightWindowsWelcomeExperience"
        )) {
            $matching = @($records | Where-Object Name -eq $name)
            $matching | Should -HaveCount 1
            $matching[0].Scope | Should -Be "User"
            $matching[0].Value | Should -Be "DWORD:1"
        }
    }

    It "cleans up obsolete Edge assignments rather than leaving ineffective policies enabled" {
        $edge.AddressBarMicrosoftSearchInBingProviderEnabled | Should -Be "DELETE"
        $edge.EdgeFollowEnabled | Should -Be "DELETE"
    }
}
