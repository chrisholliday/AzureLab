# filepath: /entra-app-permission-lookup/entra-app-permission-lookup/src/Get-AppPermissionDescriptions.ps1

<#
.SYNOPSIS
    Retrieves all existing application permission GUIDs from Microsoft Graph and translates them into their corresponding text descriptions.

.DESCRIPTION
    This script connects to Microsoft Graph, fetches all application permissions, and outputs their GUIDs along with their text descriptions.
    It requires the Microsoft Graph PowerShell SDK to be installed and appropriate permissions to access the permissions data.

.NOTES
    Author: Your Name
    Date: October 2023
    Version: 1.0

.PREREQUISITES
    - PowerShell 5.1 or later (Windows) / PowerShell 7+ (cross-platform)
    - Microsoft Graph PowerShell SDK module installed.
      If not installed, run: Install-Module Microsoft.Graph -Scope CurrentUser

.USAGE
    1. Open PowerShell.
    2. Run the script.
    3. You will be prompted to authenticate to Microsoft Graph. Ensure you have sufficient permissions (e.g., Application.Read.All).
    4. The output will be displayed in the console.

.EXAMPLE
    .\Get-AppPermissionDescriptions.ps1

.INPUTS
    None.

.OUTPUTS
    A list of application permission GUIDs and their corresponding text descriptions.
#>

#region Install and Connect to Microsoft Graph
Write-Host "Checking for Microsoft Graph PowerShell SDK module..."
try {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
        Write-Host "Microsoft.Graph module not found. Attempting to install..."
        Install-Module Microsoft.Graph -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
        Write-Host "Microsoft.Graph module installed successfully."
    } else {
        Write-Host "Microsoft.Graph module found."
    }

    Write-Host "Connecting to Microsoft Graph. You will be prompted to authenticate..."
    Connect-MgGraph -Scopes "Application.Read.All" -ErrorAction Stop
    Write-Host "Successfully connected to Microsoft Graph."

} catch {
    Write-Error "Failed to connect to Microsoft Graph or install module: $($_.Exception.Message)"
    Write-Host "Please ensure you have the necessary permissions and try again."
    exit 1
}
#endregion

#region Main Script Logic

Write-Host "Retrieving application permissions..."
try {
    $permissions = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -Property "Oauth2PermissionScopes" -ErrorAction Stop
if ($permissions.Oauth2PermissionScopes) {
    $permissionList = $permissions.Oauth2PermissionScopes | Select-Object Id, Value, DisplayName
    Write-Host "Found $($permissionList.Count) application permissions."

    $csvPath = "GraphAppPermissions.csv"
    $permissionList | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Exported permission list to $csvPath"
} else {
    Write-Host "No application permissions found."
}
} catch {
    Write-Error "Failed to retrieve application permissions: $($_.Exception.Message)"
} finally {
    Disconnect-MgGraph
}

#endregion