function Get-UniqueStorageAccountName {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Prefix,
        
        [Parameter(Mandatory = $true)]
        [string]$SeedString # Use Resource Group Name or Subscription ID
    )

    # 1. Clean the prefix (lowercase letters and numbers only)
    $cleanPrefix = ($Prefix -replace '[^a-zA-Z0-9]', '').ToLower()
    
    # 2. Create a 10-character hash from the seed
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($SeedString))
    $hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower().Substring(0, 10)

    # 3. Combine and trim to max 24 chars
    $candidateName = ($cleanPrefix + $hashString)
    if ($candidateName.Length -gt 24) {
        $candidateName = $candidateName.Substring(0, 24)
    }

    # 4. Final check against Azure API
    $availability = Get-AzStorageAccountNameAvailability -Name $candidateName
    
    if ($availability.NameAvailable) {
        return $candidateName
    }
    else {
        # Fallback: If hash somehow collides, append a small random string
        $fallback = ($candidateName.Substring(0, [Math]::Min(20, $candidateName.Length)) + -join ((97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_ }))
        return $fallback
    }
}

# Usage:
$myRG = 'Production-Web-App'
$storageName = Get-UniqueStorageAccountName -Prefix 'st' -SeedString $myRG
Write-Host "Assigned Storage Name: $storageName"