function Read-Choice {
    param(
        [Parameter(Mandatory)]
        [string] $Prompt,

        [Parameter(Mandatory)]
        [string[]] $AllowedValues
    )

    while ($true) {
        $value = Read-Host $Prompt

        if ($value -in $AllowedValues) {
            return $value
        }

        Write-Host "Invalid choice. Enter one of: $($AllowedValues -join ', ')"
    }
}
