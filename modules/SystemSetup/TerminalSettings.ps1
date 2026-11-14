# Terminal accepts JSON with comments and trailing commas. Keep source spans so
# changing a preference does not reserialize profiles, comments, or unknown keys.
function Read-TerminalJsonNode {
    param($Tokens, [ref] $Cursor, [int] $Depth = 0)

    if ($Depth -gt 100 -or $Cursor.Value -ge $Tokens.Count) {
        throw "Incomplete or excessively nested Terminal settings."
    }
    $token = $Tokens[$Cursor.Value]
    $Cursor.Value++
    $node = [pscustomobject] @{
        Start = $token.Start; End = $token.End; Kind = "Value"
        Value = $null; Properties = [ordered] @{}; Children = @()
        CloseStart = $null; SeparatorStart = $null; TrailingComma = $false
    }
    if ($token.Text -notin @("{", "[")) {
        if ($token.Text -notmatch '^(?:"|true$|false$|null$|-?\d)') {
            throw "Unexpected token in Terminal settings: $($token.Text)"
        }
        $node.Value = ConvertFrom-Json -InputObject $token.Text -ErrorAction Stop
        return $node
    }

    $node.Kind = if ($token.Text -eq "{") { "Object" } else { "Array" }
    $closing = if ($node.Kind -eq "Object") { "}" } else { "]" }
    $children = [Collections.Generic.List[object]]::new()
    $values = [ordered] @{}
    while ($Cursor.Value -lt $Tokens.Count -and $Tokens[$Cursor.Value].Text -ne $closing) {
        $key = $null
        if ($node.Kind -eq "Object") {
            $keyToken = $Tokens[$Cursor.Value]
            if (-not $keyToken.Text.StartsWith('"')) { throw "Expected a JSON property name." }
            $key = ConvertFrom-Json -InputObject $keyToken.Text -ErrorAction Stop
            if ($node.Properties.Contains($key)) { throw "Duplicate Terminal setting: '$key'." }
            $Cursor.Value++
            if ($Cursor.Value -ge $Tokens.Count -or $Tokens[$Cursor.Value].Text -ne ":") {
                throw "Expected ':' after Terminal setting '$key'."
            }
            $Cursor.Value++
        }
        $child = Read-TerminalJsonNode -Tokens $Tokens -Cursor $Cursor -Depth ($Depth + 1)
        $children.Add($child)
        if ($node.Kind -eq "Object") {
            $node.Properties[$key] = $child
            $values[$key] = $child.Value
        }
        if ($Cursor.Value -ge $Tokens.Count) { throw "Unclosed Terminal settings container." }
        if ($Tokens[$Cursor.Value].Text -eq ",") {
            $child.SeparatorStart = $Tokens[$Cursor.Value].Start
            $Cursor.Value++
            if ($Cursor.Value -lt $Tokens.Count -and $Tokens[$Cursor.Value].Text -eq $closing) {
                $node.TrailingComma = $true
            }
        }
        elseif ($Tokens[$Cursor.Value].Text -ne $closing) {
            throw "Expected ',' or '$closing' in Terminal settings."
        }
    }
    if ($Cursor.Value -ge $Tokens.Count) { throw "Unclosed Terminal settings container." }
    $node.CloseStart = $Tokens[$Cursor.Value].Start
    $node.End = $Tokens[$Cursor.Value].End
    $Cursor.Value++
    $node.Children = $children.ToArray()
    if ($node.Kind -eq "Object") {
        $node.Value = [pscustomobject] $values
    }
    else {
        $arrayValues = [Collections.Generic.List[object]]::new()
        foreach ($child in $children) { $arrayValues.Add($child.Value) }
        $node.Value = $arrayValues.ToArray()
    }
    return $node
}

function Read-TerminalJson {
    param([string] $Text)

    # Strings are matched before comments, so URLs and escaped quotes stay intact.
    $pattern = '\G(?:\s+|//[^\r\n]*|/\*[\s\S]*?\*/|"(?:[^"\\\x00-\x1f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null|[{}\[\]:,])'
    $tokens = [Collections.Generic.List[object]]::new()
    $offset = 0
    foreach ($match in [regex]::Matches($Text, $pattern)) {
        if ($match.Index -ne $offset) { throw "Invalid Terminal settings at character $offset." }
        $offset = $match.Index + $match.Length
        if ($match.Value -match '^(?:\s|//|/\*)') { continue }
        $tokens.Add([pscustomobject] @{ Text = $match.Value; Start = $match.Index; End = $offset })
    }
    if ($offset -ne $Text.Length -or $tokens.Count -eq 0) { throw "Invalid or empty Terminal settings." }
    $cursor = 0
    $node = Read-TerminalJsonNode -Tokens $tokens -Cursor ([ref] $cursor)
    if ($cursor -ne $tokens.Count -or $node.Kind -ne "Object") {
        throw "Terminal settings must contain exactly one JSON object."
    }
    return $node
}

function Add-TerminalJsonEntry {
    param([string] $Text, $Container, [string] $Entry, [int] $Depth = 0)

    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $addition = $newline + (" " * (4 * ($Depth + 1))) + $Entry + $newline + (" " * (4 * $Depth))
    $result = $Text.Insert($Container.CloseStart, $addition)
    if ($Container.Children.Count -gt 0 -and -not $Container.TrailingComma) {
        $result = $result.Insert($Container.Children[-1].End, ",")
    }
    return $result
}

function Set-TerminalJsonProperty {
    param([string] $Text, [string[]] $Path, [AllowNull()] [AllowEmptyCollection()] $Value)

    $node = Read-TerminalJson -Text $Text
    for ($index = 0; $index -lt $Path.Count; $index++) {
        if ($node.Kind -ne "Object") { throw "Terminal setting '$($Path -join '.')' requires an object." }
        $key = $Path[$index]
        if (-not $node.Properties.Contains($key)) {
            $nestedValue = $Value
            for ($remaining = $Path.Count - 1; $remaining -gt $index; $remaining--) {
                $nestedValue = [ordered] @{ $Path[$remaining] = $nestedValue }
            }
            $entry = (ConvertTo-Json -InputObject $key -Compress) + ": " +
                (ConvertTo-Json -InputObject $nestedValue -Depth 100 -Compress)
            return Add-TerminalJsonEntry -Text $Text -Container $node -Entry $entry -Depth $index
        }
        $node = $node.Properties[$key]
    }
    $json = ConvertTo-Json -InputObject $Value -Depth 100 -Compress
    if ((ConvertTo-Json -InputObject $node.Value -Depth 100 -Compress) -ceq $json) { return $Text }
    return $Text.Remove($node.Start, $node.End - $node.Start).Insert($node.Start, $json)
}

function Remove-TerminalJsonArrayItem {
    param([string] $Text, [string] $Name, [int] $Index)

    $array = (Read-TerminalJson -Text $Text).Properties[$Name]
    $item = $array.Children[$Index]
    if ($null -ne $item.SeparatorStart) {
        return $Text.Remove($item.Start, $item.SeparatorStart + 1 - $item.Start)
    }
    $result = $Text.Remove($item.Start, $item.End - $item.Start)
    if ($Index -gt 0) { $result = $result.Remove($array.Children[$Index - 1].SeparatorStart, 1) }
    return $result
}

function ConvertTo-TerminalKeyChord {
    param([string] $Keys)
    return (($Keys.ToLowerInvariant().Split('+') | ForEach-Object { $_.Trim() } | Sort-Object) -join '+')
}

function Set-TerminalKeybinding {
    param([string] $Text, $Binding)

    if ($Binding.id -isnot [string] -or [string]::IsNullOrWhiteSpace($Binding.id) -or
        $Binding.keys -isnot [string] -or [string]::IsNullOrWhiteSpace($Binding.keys)) {
        throw "Repository Terminal keybindings require a nonempty id and a single key chord."
    }
    $chord = ConvertTo-TerminalKeyChord -Keys $Binding.keys
    $retained = $false
    foreach ($name in @("actions", "keybindings")) {
        $root = Read-TerminalJson -Text $Text
        if (-not $root.Properties.Contains($name)) { continue }
        $array = $root.Properties[$name]
        if ($array.Kind -ne "Array") { throw "Terminal '$name' must be an array." }
        for ($index = $array.Children.Count - 1; $index -ge 0; $index--) {
            $item = $array.Children[$index]
            if ($item.Kind -ne "Object" -or -not $item.Properties.Contains("keys")) { continue }
            $keys = @($item.Properties["keys"].Value)
            if (@($keys | Where-Object { $_ -isnot [string] }).Count -gt 0) {
                throw "Terminal key chords must be strings."
            }
            $remaining = @($keys | Where-Object { (ConvertTo-TerminalKeyChord -Keys $_) -ne $chord })
            if ($remaining.Count -eq $keys.Count) { continue }
            if ($name -eq "keybindings" -and -not $retained -and $item.Value.id -ceq $Binding.id) {
                $retained = $true
                continue
            }
            if ($name -eq "keybindings" -and $remaining.Count -eq 0) {
                $Text = Remove-TerminalJsonArrayItem -Text $Text -Name $name -Index $index
            }
            else {
                # Keep legacy action definitions and any shortcuts we do not own.
                $keysNode = $item.Properties["keys"]
                $json = ConvertTo-Json -InputObject $remaining -Compress
                $Text = $Text.Remove($keysNode.Start, $keysNode.End - $keysNode.Start).Insert($keysNode.Start, $json)
            }
        }
    }
    if (-not $retained) {
        $root = Read-TerminalJson -Text $Text
        if (-not $root.Properties.Contains("keybindings")) {
            $Text = Set-TerminalJsonProperty -Text $Text -Path @("keybindings") -Value @()
        }
        $array = (Read-TerminalJson -Text $Text).Properties["keybindings"]
        $entry = ConvertTo-Json -InputObject $Binding -Compress
        $Text = Add-TerminalJsonEntry -Text $Text -Container $array -Entry $entry
    }
    return $Text
}

function Set-TerminalAction {
    param([string] $Text, $Action)

    if ($Action.id -isnot [string] -or [string]::IsNullOrWhiteSpace($Action.id) -or
        ($Action.command -isnot [string] -and $Action.command -isnot [pscustomobject])) {
        throw "Repository Terminal actions require a nonempty id and a command."
    }
    $root = Read-TerminalJson -Text $Text
    if (-not $root.Properties.Contains("actions")) {
        $Text = Set-TerminalJsonProperty -Text $Text -Path @("actions") -Value @()
        $root = Read-TerminalJson -Text $Text
    }
    $array = $root.Properties["actions"]
    if ($array.Kind -ne "Array") { throw "Terminal 'actions' must be an array." }

    $retained = $false
    for ($index = $array.Children.Count - 1; $index -ge 0; $index--) {
        $item = $array.Children[$index]
        if ($item.Kind -ne "Object" -or $item.Value.id -cne $Action.id) { continue }
        if ($retained) {
            $Text = Remove-TerminalJsonArrayItem -Text $Text -Name "actions" -Index $index
            continue
        }
        $retained = $true
        # Manage the command under our own ID, preserving labels, comments, and
        # unrelated definitions. A custom built-in ID cannot change our shortcut.
        $json = ConvertTo-Json -InputObject $Action.command -Depth 100 -Compress
        if ($item.Properties.Contains("command")) {
            $commandNode = $item.Properties["command"]
            if ((ConvertTo-Json -InputObject $commandNode.Value -Depth 100 -Compress) -cne $json) {
                $Text = $Text.Remove($commandNode.Start, $commandNode.End - $commandNode.Start).Insert($commandNode.Start, $json)
            }
        }
        else {
            $Text = Add-TerminalJsonEntry -Text $Text -Container $item -Entry ('"command": ' + $json) -Depth 2
        }
    }
    if (-not $retained) {
        $array = (Read-TerminalJson -Text $Text).Properties["actions"]
        $Text = Add-TerminalJsonEntry -Text $Text -Container $array -Entry (ConvertTo-Json -InputObject $Action -Depth 100 -Compress)
    }
    return $Text
}

function Merge-TerminalDefaults {
    param([string] $Text, $Defaults, [string[]] $Path = @())

    foreach ($property in $Defaults.PSObject.Properties) {
        $propertyPath = @($Path) + @($property.Name)
        if ($Path.Count -eq 0 -and $property.Name -in @("actions", "keybindings")) {
            if ($property.Value -isnot [array]) { throw "Repository Terminal '$($property.Name)' must be an array." }
            foreach ($entry in $property.Value) {
                if ($property.Name -eq "actions") {
                    $Text = Set-TerminalAction -Text $Text -Action $entry
                }
                else {
                    $Text = Set-TerminalKeybinding -Text $Text -Binding $entry
                }
            }
        }
        elseif ($property.Value -is [pscustomobject]) {
            $Text = Merge-TerminalDefaults -Text $Text -Defaults $property.Value -Path $propertyPath
        }
        else {
            $Text = Set-TerminalJsonProperty -Text $Text -Path $propertyPath -Value $property.Value
        }
    }
    return $Text
}

function Set-TerminalSettingsFile {
    param([string] $SettingsPath, $Defaults)

    $exists = Test-Path -LiteralPath $SettingsPath -PathType Leaf
    if ($exists -and ((Get-Item -LiteralPath $SettingsPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Terminal settings is a filesystem link; configure its target manually: $SettingsPath"
    }
    $originalBytes = if ($exists) { [IO.File]::ReadAllBytes($SettingsPath) } else { $null }
    $originalText = if ($exists) {
        [IO.File]::ReadAllText($SettingsPath, [Text.UTF8Encoding]::new($false, $true))
    }
    else { "{}" }
    $updatedText = Merge-TerminalDefaults -Text $originalText -Defaults $Defaults
    Read-TerminalJson -Text $updatedText | Out-Null
    if ($exists -and $updatedText -ceq $originalText) {
        Write-Host "[OK] Windows Terminal preferences already match: $SettingsPath"
        return
    }

    $directory = Split-Path -Parent $SettingsPath
    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
    $suffix = [guid]::NewGuid().ToString("N")
    $temporaryPath = "$SettingsPath.$suffix.tmp"
    try {
        [IO.File]::WriteAllText($temporaryPath, $updatedText, [Text.UTF8Encoding]::new($false))
        if ($exists) {
            if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($SettingsPath)) -cne
                [Convert]::ToBase64String($originalBytes)) {
                throw "Terminal settings changed during setup; rerun after closing Terminal."
            }
            $backupPath = "$SettingsPath.backup-$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))-$suffix"
            [IO.File]::Replace($temporaryPath, $SettingsPath, $backupPath)
            Write-Host "[OK] Updated Windows Terminal preferences. Backup: $backupPath"
        }
        else {
            [IO.File]::Move($temporaryPath, $SettingsPath)
            Write-Host "[OK] Created Windows Terminal preferences: $SettingsPath"
        }
    }
    finally {
        if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) }
    }
}
