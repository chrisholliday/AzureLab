<#
.SYNOPSIS
    Audits Entra ID (Azure AD) application registrations for potentially vulnerable permissions.

.DESCRIPTION
    This script connects to Microsoft Graph, retrieves all application registrations,
    and then details their name, GUID (App ID), owners, and required permissions.
    It specifically focuses on Microsoft Graph permissions, indicating whether
    they are delegated or application permissions, if admin consent is required/granted,
    and highlighting any permissions that include "write" access.

.NOTES
    Author: Gemini (Fixed by Claude)
    Date: July 2, 2025
    Version: 1.8 (Added testing limits and progress indicators)

.PREREQUISITES
    - PowerShell 5.1 or later (Windows) / PowerShell 7+ (cross-platform)
    - Microsoft Graph PowerShell SDK module installed.
      If not installed, run: Install-Module Microsoft.Graph -Scope CurrentUser

.USAGE
    1. Open PowerShell.
    2. Run the script.
    3. You will be prompted to authenticate to Microsoft Graph. Ensure you have
       sufficient permissions (e.g., Application.Read.All, Directory.Read.All,
       User.Read.All for owners).
    4. The output will be saved to 'EntraAppPermissionsReport.csv' in the current directory.

.EXAMPLE
    .\EntraAppPermissions.ps1
    
.EXAMPLE
    .\EntraAppPermissions.ps1 -TestLimit 100
    Process only the first 100 applications for testing

.EXAMPLE
    .\EntraAppPermissions.ps1 -TestLimit 50 -ShowProgress
    Process only the first 50 applications with progress indicators

.INPUTS
    None.

.OUTPUTS
    A CSV file named 'EntraAppPermissionsReport.csv' containing application details and permission information.
#>

[CmdletBinding()]
param (
    # Limit the number of applications to process (useful for testing)
    [int]$TestLimit = 0,
    
    # Show progress indicators during processing
    [switch]$ShowProgress
)

#region Install and Connect to Microsoft Graph
Write-Host "Checking for Microsoft Graph PowerShell SDK module..."
try {
    # Check if the module is installed
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
        Write-Host "Microsoft.Graph module not found. Attempting to install..."
        Install-Module Microsoft.Graph -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
        Write-Host "Microsoft.Graph module installed successfully."
    } else {
        Write-Host "Microsoft.Graph module found."
    }

    # Define the required scopes for connecting to Microsoft Graph
    $requiredScopes = @(
        "Application.Read.All",
        "Directory.Read.All",
        "User.Read.All"
    )

    Write-Host "Connecting to Microsoft Graph. You will be prompted to authenticate..."
    Connect-MgGraph -Scopes $requiredScopes -ErrorAction Stop
    Write-Host "Successfully connected to Microsoft Graph."

} catch {
    Write-Error "Failed to connect to Microsoft Graph or install module: $($_.Exception.Message)"
    Write-Host "Please ensure you have the necessary permissions and try again."
    exit 1
}
#endregion

#region Helper Functions and Variables

# Cache variables
$servicePrincipals = @{}
$permissionCache = @{}
$userPrincipalNameCache = @{}

# Static mapping for common Microsoft Graph permissions
$graphPermissionMap = @{
    # AppRole (Application permissions)
    "62a82d76-70ea-41e2-9197-370581804d09" = "User.Read.All"
    "df021288-bdef-4463-88db-98f22de89214" = "Directory.Read.All"
    "19dbc75e-c2e2-444c-a770-ec69d8559fc7" = "Directory.ReadWrite.All"
    "06da0dbc-49e2-44d2-8312-53f166ab848a" = "User.ReadWrite.All"
    "7ab1d382-f21e-4acd-a863-ba3e13f7da61" = "Group.Read.All"
    "5b567255-7703-4780-807c-7be8301ae99b" = "Group.ReadWrite.All"
    "dc50a0fb-09a3-484d-be87-e023b12c6440" = "Application.Read.All"
    "18a4783c-866b-4cc7-a460-3d5e5662c884" = "Application.ReadWrite.All"
    "dfabfca6-ee36-4c39-95a5-2a7b6b82d54b" = "Policy.Read.All"
    "b1aaf6be-5c63-44b2-bae4-9d7c3b6b8baf" = "Policy.ReadWrite.ConditionalAccess"
    "134fd756-38ce-4afd-ba33-e9623dbe66c2" = "AdministrativeUnit.Read.All"
    
    # Oauth2PermissionScopes (Delegated permissions)
    "e1fe6dd8-ba31-4d61-89e7-88639da4683d" = "User.Read"
    "b340eb25-3456-403f-be2f-af7a0d370277" = "Directory.AccessAsUser.All"
    "a154be20-db9c-4678-8ab7-66f6cc099a59" = "Mail.Read"
    "64a6cdd6-aab1-4aaf-94b6-9b34e9620c7a" = "Mail.ReadWrite"
    "10465720-29dd-4523-a11a-6a75c743c9d9" = "Calendars.Read"
    "e2a3a72e-5f79-4c64-b1b1-878b674786c9" = "Files.Read"
    "863451e7-0667-486c-a5d6-d135439485f0" = "Files.ReadWrite"
}

# Function to get service principal details
function Get-ServicePrincipalName {
    param (
        [string]$AppId
    )
    
    if ($servicePrincipals.ContainsKey($AppId)) {
        return $servicePrincipals[$AppId]
    }
    
    try {
        $sp = Get-MgServicePrincipal -Filter "appId eq '$AppId'" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty DisplayName
        if ($sp) {
            $servicePrincipals[$AppId] = $sp
            return $sp
        }
    } catch {
        Write-Warning "Error retrieving service principal for AppId $AppId : $($_.Exception.Message)"
    }
    
    $servicePrincipals[$AppId] = "Unknown Service Principal ($AppId)"
    return "Unknown Service Principal ($AppId)"
}

# Function to get permission name from GUID
function Get-PermissionName {
    param (
        [string]$AppId,
        [string]$PermissionId,
        [string]$PermissionType # "Scope" for delegated, "AppRole" for application
    )

    $cacheKey = "$AppId-$PermissionId-$PermissionType"
    if ($permissionCache.ContainsKey($cacheKey)) {
        return $permissionCache[$cacheKey]
    }

    try {
        $sp = Get-MgServicePrincipal -Filter "appId eq '$AppId'" -Property "Id,DisplayName,AppRoles,Oauth2PermissionScopes" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($sp) {
            $permission = $null
            
            if ($PermissionType -eq "Scope" -and $sp.Oauth2PermissionScopes) {
                $permissionObj = $sp.Oauth2PermissionScopes | Where-Object { $_.Id -eq $PermissionId }
                if ($permissionObj) {
                    $permission = $permissionObj.Value
                    if ($permissionObj.DisplayName -and $permissionObj.DisplayName -ne $permission) {
                        $permission = "$($permissionObj.DisplayName) ($permission)"
                    }
                }
            } elseif ($PermissionType -eq "AppRole" -and $sp.AppRoles) {
                $permissionObj = $sp.AppRoles | Where-Object { $_.Id -eq $PermissionId }
                if ($permissionObj) {
                    $permission = $permissionObj.Value
                    if ($permissionObj.DisplayName -and $permissionObj.DisplayName -ne $permission) {
                        $permission = "$($permissionObj.DisplayName) ($permission)"
                    }
                }
            }

            if ($permission) {
                $permissionCache[$cacheKey] = $permission
                return $permission
            }
        }
    } catch {
        Write-Warning "Error resolving permission for AppId $AppId, PermissionId $PermissionId, Type $PermissionType : $($_.Exception.Message)"
    }

    # Fallback for Microsoft Graph well-known permissions
    if ($AppId -eq "00000003-0000-0000-c000-000000000000" -and $graphPermissionMap.ContainsKey($PermissionId)) {
        $permission = $graphPermissionMap[$PermissionId]
        $permissionCache[$cacheKey] = $permission
        return $permission
    }

    $permissionCache[$cacheKey] = "Unknown Permission ($PermissionId)"
    return "Unknown Permission ($PermissionId)"
}

# Function to get user principal name from GUID (with caching)
function Get-UserPrincipalName {
    param (
        [string]$UserId
    )
    
    if ($userPrincipalNameCache.ContainsKey($UserId)) {
        return $userPrincipalNameCache[$UserId]
    }
    
    try {
        $user = Get-MgUser -UserId $UserId -ErrorAction SilentlyContinue | Select-Object -ExpandProperty UserPrincipalName
        if ($user) {
            $userPrincipalNameCache[$UserId] = $user
            return $user
        }
    } catch {
        Write-Warning "Error retrieving user principal name for UserId $UserId : $($_.Exception.Message)"
    }
    
    $userPrincipalNameCache[$UserId] = "User ID: $UserId"
    return "User ID: $UserId"
}

#endregion

#region Main Script Logic

$report = @()

Write-Host "Retrieving all application registrations..."
try {
    $applications = Get-MgApplication -All -ErrorAction Stop | Select-Object Id, AppId, DisplayName, RequiredResourceAccess
    Write-Host "Found $($applications.Count) application registrations."
    
    # Apply test limit if specified
    if ($TestLimit -gt 0 -and $applications.Count -gt $TestLimit) {
        $applications = $applications | Select-Object -First $TestLimit
        Write-Host "Limited to first $TestLimit applications for testing."
    }
    
} catch {
    Write-Error "Failed to retrieve application registrations: $($_.Exception.Message)"
    Disconnect-MgGraph
    exit 1
}

$appCount = 0
foreach ($app in $applications) {
    $appCount++
    
    if ($ShowProgress) {
        Write-Progress -Activity "Processing Applications" -Status "Processing: $($app.DisplayName)" -PercentComplete (($appCount / $applications.Count) * 100)
    }
    
    Write-Host "Processing application $appCount of $($applications.Count): $($app.DisplayName) ($($app.AppId))"

    # Get Owners
    $owners = @()
    try {
        $appOwners = Get-MgApplicationOwner -ApplicationId $app.Id -ErrorAction SilentlyContinue
        if ($appOwners) {
            foreach ($owner in $appOwners) {
                # Check if owner has DisplayName property
                if ($owner.AdditionalProperties -and $owner.AdditionalProperties.ContainsKey('displayName') -and -not [string]::IsNullOrEmpty($owner.AdditionalProperties['displayName'])) {
                    $owners += $owner.AdditionalProperties['displayName']
                }
                # Check if it's a user object and get UPN
                elseif ($owner.AdditionalProperties -and $owner.AdditionalProperties.ContainsKey('@odata.type') -and $owner.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.user') {
                    $owners += (Get-UserPrincipalName -UserId $owner.Id)
                }
                # Check if it's a service principal
                elseif ($owner.AdditionalProperties -and $owner.AdditionalProperties.ContainsKey('@odata.type') -and $owner.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.servicePrincipal') {
                    if ($owner.AdditionalProperties.ContainsKey('displayName')) {
                        $owners += "Service Principal: $($owner.AdditionalProperties['displayName'])"
                    } else {
                        $owners += "Service Principal ID: $($owner.Id)"
                    }
                }
                # Fallback - try to get as user first, then fallback to ID
                else {
                    try {
                        $userUpn = Get-UserPrincipalName -UserId $owner.Id
                        if ($userUpn -and -not $userUpn.StartsWith("User ID:")) {
                            $owners += $userUpn
                        } else {
                            $owners += "Owner ID: $($owner.Id)"
                        }
                    } catch {
                        $owners += "Owner ID: $($owner.Id)"
                    }
                }
            }
        }
    } catch {
        Write-Warning "Could not retrieve owners for $($app.DisplayName): $($_.Exception.Message)"
    }

    # Process RequiredResourceAccess permissions
    if ($app.RequiredResourceAccess) {
        foreach ($resourceAccess in $app.RequiredResourceAccess) {
            $resourceName = Get-ServicePrincipalName -AppId $resourceAccess.ResourceAppId

            # Check if it's Microsoft Graph
            if ($resourceAccess.ResourceAppId -eq "00000003-0000-0000-c000-000000000000") {
                foreach ($access in $resourceAccess.ResourceAccess) {
                    $permissionName = Get-PermissionName -AppId $resourceAccess.ResourceAppId -PermissionId $access.Id -PermissionType $access.Type

                    $isDelegated = ($access.Type -eq "Scope")
                    $isApplication = ($access.Type -eq "AppRole")
                    $hasWrite = ($permissionName -like "*Write*" -or $permissionName -like "*FullControl*")

                    # Check for admin consent status for application permissions
                    $adminConsentGranted = $false
                    if ($isApplication) {
                        try {
                            $currentAppSp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -ErrorAction SilentlyContinue
                            if ($currentAppSp) {
                                $appRoleAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $currentAppSp.Id -ErrorAction SilentlyContinue
                                if ($appRoleAssignments) {
                                    $adminConsentGranted = $appRoleAssignments | Where-Object { $_.AppRoleId -eq $access.Id } | Select-Object -First 1
                                    $adminConsentGranted = $null -ne $adminConsentGranted
                                }
                            }
                        } catch {
                            Write-Warning "Could not determine admin consent for application permission $($permissionName) on $($app.DisplayName): $($_.Exception.Message)"
                        }
                    } else {
                        # For delegated permissions, check if admin consent is required
                        try {
                            $graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -ErrorAction SilentlyContinue
                            if ($graphSp) {
                                $delegatedPermission = $graphSp.Oauth2PermissionScopes | Where-Object { $_.Id -eq $access.Id }
                                if ($delegatedPermission -and $delegatedPermission.AdminConsentRequired) {
                                    $adminConsentGranted = $true
                                }
                            }
                        } catch {
                            Write-Warning "Could not determine admin consent requirement for delegated permission $($permissionName) on $($app.DisplayName): $($_.Exception.Message)"
                        }
                    }

                    $report += [PSCustomObject]@{
                        ApplicationName       = $app.DisplayName
                        ApplicationGuid       = $app.AppId
                        Owners                = ($owners -join ", ")
                        ResourceName          = $resourceName
                        PermissionName        = $permissionName
                        PermissionId          = $access.Id
                        PermissionType        = if ($isDelegated) {"Delegated"} else {"Application"}
                        AdminConsent          = if ($isApplication -and $adminConsentGranted) {"Granted"} elseif ($isDelegated -and $adminConsentGranted) {"Required/Applicable"} else {"Not Granted/Not Required"}
                        HasWritePermission    = $hasWrite
                        IsMicrosoftGraph      = $true
                    }
                }
            } else {
                # Add non-Microsoft Graph permissions
                foreach ($access in $resourceAccess.ResourceAccess) {
                    $permissionName = Get-PermissionName -AppId $resourceAccess.ResourceAppId -PermissionId $access.Id -PermissionType $access.Type
                    $isDelegated = ($access.Type -eq "Scope")
                    $isApplication = ($access.Type -eq "AppRole")
                    $hasWrite = ($permissionName -like "*Write*" -or $permissionName -like "*FullControl*")

                    $report += [PSCustomObject]@{
                        ApplicationName       = $app.DisplayName
                        ApplicationGuid       = $app.AppId
                        Owners                = ($owners -join ", ")
                        ResourceName          = $resourceName
                        PermissionName        = $permissionName
                        PermissionId          = $access.Id
                        PermissionType        = if ($isDelegated) {"Delegated"} else {"Application"}
                        AdminConsent          = "N/A (Non-Graph)"
                        HasWritePermission    = $hasWrite
                        IsMicrosoftGraph      = $false
                    }
                }
            }
        }
    } else {
        # Applications with no required resource access
        $report += [PSCustomObject]@{
            ApplicationName       = $app.DisplayName
            ApplicationGuid       = $app.AppId
            Owners                = ($owners -join ", ")
            ResourceName          = "N/A"
            PermissionName        = "No Permissions Required"
            PermissionId          = "N/A"
            PermissionType        = "N/A"
            AdminConsent          = "N/A"
            HasWritePermission    = $false
            IsMicrosoftGraph      = $false
        }
    }
}

# Output the report to CSV
$outputPath = Join-Path (Get-Location) "EntraAppPermissionsReport.csv"
Write-Host "`nExporting report to '$outputPath'..."
$report | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8 -Force
Write-Host "Report exported successfully."

if ($ShowProgress) {
    Write-Progress -Activity "Processing Applications" -Completed
}

Write-Host "`nProcessed $($applications.Count) applications with $($report.Count) total permission entries."
Write-Host "Script finished. Disconnecting from Microsoft Graph."
Disconnect-MgGraph

#endregion