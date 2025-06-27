# Connect to Microsoft Graph
# Ensure you have the necessary permissions: Application.Read.All, ServicePrincipal.Read.All, Directory.Read.All, AppRoleAssignment.Read.All
Connect-MgGraph -Scopes "Application.Read.All", "ServicePrincipal.Read.All", "Directory.Read.All", "AppRoleAssignment.Read.All"

# Define an array to store the results
$appReport = @()

Write-Host "Fetching all application registrations and their details. This may take a moment..."

# Get all application registrations
$applications = Get-MgApplication -All

foreach ($app in $applications) {
    $appName = $app.DisplayName
    $appId = $app.AppId # This is the Application (client) ID
    $objectId = $app.Id # This is the Object ID of the application registration

    Write-Host "Processing application: $($appName) (ID: $($appId))"

    # Get owners
    $owners = @()
    try {
        $appOwners = Get-MgApplicationOwner -ApplicationId $objectId -All
        foreach ($owner in $appOwners) {
            # Try to resolve user principal name or display name for owners
            if ($owner.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.user') {
                $user = Get-MgUser -UserId $owner.Id -ErrorAction SilentlyContinue
                if ($user) {
                    $owners += $user.UserPrincipalName
                } else {
                    $owners += $owner.DisplayName
                }
            } elseif ($owner.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.group') {
                $group = Get-MgGroup -GroupId $owner.Id -ErrorAction SilentlyContinue
                if ($group) {
                    $owners += "Group: $($group.DisplayName)"
                } else {
                    $owners += "Group ID: $($owner.Id)"
                }
            } else {
                $owners += $owner.DisplayName # Fallback to display name
            }
        }
    } catch {
        Write-Warning "Could not retrieve owners for application $($appName): $($_.Exception.Message)"
        $owners += "Error retrieving owners"
    }
    $ownersString = ($owners | Select-Object -Unique) -join "; "

    # Get API Permissions
    $delegatedPermissions = @()
    $applicationPermissions = @()

    # Permissions are typically granted to the Service Principal associated with the application
    $servicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$appId'" -ErrorAction SilentlyContinue

    if ($servicePrincipal) {
        # Delegated Permissions (OAuth2PermissionGrants)
        try {
            $oauth2PermissionGrants = Get-MgOauth2PermissionGrant -Filter "clientId eq '$servicePrincipal.Id'" -All -ErrorAction SilentlyContinue
            foreach ($grant in $oauth2PermissionGrants) {
                $resourceServicePrincipal = Get-MgServicePrincipal -ServicePrincipalId $grant.ResourceId -ErrorAction SilentlyContinue
                $resourceName = $resourceServicePrincipal.DisplayName
                $scope = $grant.Scope

                if ($scope) {
                    $delegatedPermissions += "$($resourceName): $($scope.Replace(' ', ', '))"
                }
            }
        } catch {
            Write-Warning "Could not retrieve delegated permissions for application $($appName): $($_.Exception.Message)"
        }

        # Application Permissions (AppRoleAssignments)
        try {
            $appRoleAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $servicePrincipal.Id -All -ErrorAction SilentlyContinue
            foreach ($assignment in $appRoleAssignments) {
                # Determine if it's an application permission (not a user assigned to an app role)
                # AppRoleAssignments can also be used for users assigned to application roles.
                # We're looking for where the PrincipalType is 'ServicePrincipal' or if it's assigned to the app itself.
                if ($assignment.PrincipalType -eq 'ServicePrincipal' -or $assignment.PrincipalId -eq $servicePrincipal.Id) {
                    $resourceServicePrincipal = Get-MgServicePrincipal -ServicePrincipalId $assignment.ResourceId -ErrorAction SilentlyContinue
                    $resourceName = $resourceServicePrincipal.DisplayName

                    # Find the specific app role name
                    $appRole = $resourceServicePrincipal.AppRoles | Where-Object { $_.Id -eq $assignment.AppRoleId }
                    if ($appRole) {
                        $applicationPermissions += "$($resourceName): $($appRole.Value)"
                    } else {
                        $applicationPermissions += "$($resourceName): $($assignment.AppRoleId) (Unknown Role)"
                    }
                }
            }
        } catch {
            Write-Warning "Could not retrieve application permissions for application $($appName): $($_.Exception.Message)"
        }
    } else {
        Write-Warning "No service principal found for application $($appName) (AppId: $($appId)). Permissions may be incomplete."
    }

    # Add to the report
    $appReport += [PSCustomObject]@{
        AppName                = $appName
        AppId                  = $appId
        ObjectId               = $objectId
        Owners                 = $ownersString
        DelegatedPermissions   = ($delegatedPermissions | Select-Object -Unique) -join "; "
        ApplicationPermissions = ($applicationPermissions | Select-Object -Unique) -join "; "
    }
}

# Output the report to a grid view
$appReport | Out-GridView -Title "Entra ID Application Registrations Security Audit"

# Optionally, export to CSV
$outputPath = "C:\Temp\Entra_AppRegistrations_Audit_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$appReport | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8

Write-Host "Report saved to: $outputPath"