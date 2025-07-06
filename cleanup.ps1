function Remove-BackupItems {
    param (
        $BackupContainer,
        $vault,
        [String]$Type
    )
    Write-Output "Setting Vault Context for $($vault.name)"
    Set-AzRecoveryServicesVaultContext -Vault $Vault

    foreach ($Container in $BackupContainer) {
        if ($Type = 'VM') {
            $BackupItems = Get-AzRecoveryServicesBackupItem -Container $Container -WorkloadType AzureVM
        }
        else {
            $BackupItems = Get-AzRecoveryServicesBackupItem -Container $Container
        }
        foreach ($Item in $BackupItems) {
            # Stop-AzRecoveryServicesBackupJob -Item $Item -Force
            Write-Output "Attemping to delete $($item.ContainerName)"
            Disable-AzRecoveryServicesBackupProtection -Item $Item -RemoveRecoveryPoints -Force
            Unregister-AzRecoveryServicesBackupContainer -Container $Container -Force #-WorkloadType AzureVM
        }
    }
}

function Remove-RecoveryServicesVault {
    param (
        $VaultName,
        [string]$ResourceGroupName
    )

    # Get the Recovery Services vault
    $Vault = Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroupName -Name $VaultName

    # Disable soft delete
    Write-Output "Disabling soft delete on $($Vault.Name)"
    Set-AzRecoveryServicesVaultProperty -VaultId $Vault.ID -SoftDeleteFeatureState Disable | Out-Null

    # Get all VM container objects in the vault and delete them
    $VM_Container = Get-AzRecoveryServicesBackupContainer -VaultId $vault.ID -ContainerType AzureVM
    Write-Output "Attempting to delete container $($VM_Container.Name)"
    if ($VM_Container) {
        Remove-BackupItems -BackupContainer $VM_Containers -Vault $Vault -Type VM
    }

    $SQL_Container = Get-AzRecoveryServicesBackupContainer -VaultId $vault.ID -ContainerType AzureSQL
    if ($SQL_Container) {
        Remove-BackupItems -BackupContainer $SQL_Container -Vault $Vault
    }

    $Storage_Container = Get-AzRecoveryServicesBackupContainer -VaultId $vault.ID -ContainerType AzureStorage
    if ($Storage_Container) {
        Remove-BackupItems -BackupContainer $Storage_Container -Vault $Vault
    }

    $App_Container = Get-AzRecoveryServicesBackupContainer -VaultId $vault.ID -ContainerType AzureVMAppContainer
    if ($App_Container) {
        Remove-BackupItems -BackupContainer $App_Container -Vault $Vault
    }

    $Windows_Container = Get-AzRecoveryServicesBackupContainer -VaultId $vault.ID -ContainerType Windows -BackupManagementType MAB
    if ($Windows_Container) {
        Remove-BackupItems -BackupContainer $Windows_Container -Vault $Vault
    }
    # Remove the Recovery Services vault
    if ($i -gt 1) {
        Write-Output "Attempting to delete $($Vault.Name)"
        Remove-AzRecoveryServicesVault -Vault $Vault
    }
}

function Remove-OpenAIResource {
 
    param (
        [string]$ResourceGroupName,
        [string]$OpenAIResourceName
    )

    # Get the OpenAI resource
    $OpenAIResource = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceName $OpenAIResourceName -ResourceType 'Microsoft.CognitiveServices/accounts'

    # Get all deployments for the OpenAI resource
    $Deployments = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Resources/deployments' | Where-Object { $_.Properties.targetResource.id -eq $OpenAIResource.Id }

    # Remove each deployment
    foreach ($Deployment in $Deployments) {
        Write-Output "Attempting to delete Open AI deployment $($Deployment.Name)"
        Remove-AzResource -ResourceId $Deployment.Id -Force
    }

    # Remove the OpenAI resource
    Write-Output "Attempting to delete $($OpenAIResource.Name)"
    Remove-AzResource -ResourceId $OpenAIResource.Id -Force
}

function Remove-PublicIPs {
    param (
        $ResourceGroupName
    )

    $networkInterfaces = Get-AzNetworkInterface -ResourceGroupName $resourceGroupName
    foreach ($nic in $networkInterfaces) {
        foreach ($ipConfig in $nic.IpConfigurations) {
            if ($null -ne $ipConfig.PublicIpAddress) {
                # Disassociate the public IP address
                $ipConfig.PublicIpAddress = $null
                Write-Output "Disassociated public IP from NIC: $($nic.Name)"
            }
        }
        # Apply the changes to the network interface
        Set-AzNetworkInterface -NetworkInterface $nic
    }
}

Write-Output 'Connecting to Azure'
# connect to azure as the automation account
Connect-AzAccount -Identity

Write-Output 'Validating Subscription'
# Validate that only the sandbox subscription "sub1" is targeted
$subscription = Get-AzContext | Select-Object -ExpandProperty Subscription
if ($null -eq $subscription -or $subscription.Id -ne 'sub1') {
    throw "ERROR: This script can only be run against the sandbox subscription 'sub1'. Current subscription: $($subscription.Id)"
}
Write-Output "Validated: Running in sandbox subscription 'sub1'"

Write-Output 'Getting List of Resource Groups'
$ResourceGroups = Get-AzResourceGroup -Name 'chris.holliday'

# --- Exemption List Logic ---
# Retrieve exemption list from Key Vault (update vault/secret names as needed)
$ExemptedResourceGroups = @()
try {
    $exemptSecret = Get-AzKeyVaultSecret -VaultName 'myKeyVault' -Name 'ExemptResourceGroups'
    $ExemptedResourceGroups = $exemptSecret.SecretValueText | ConvertFrom-Json
}
catch {
    Write-Warning 'Could not retrieve exemption list from Key Vault. No resource groups will be exempted.'
    Write-Log "Could not retrieve exemption list from Key Vault. No resource groups will be exempted. $_" 'WARN'
}

function Is-ExemptedResourceGroup($rgName, $exemptList) {
    foreach ($pattern in $exemptList) {
        if ($rgName -like $pattern) { return $true }
    }
    return $false
}

# Define deletion order for common Azure resource types (most dependent first)
$deletionOrder = @(
    'Microsoft.Compute/virtualMachines',
    'Microsoft.Network/networkInterfaces',
    'Microsoft.Network/publicIPAddresses',
    'Microsoft.Network/networkSecurityGroups',
    'Microsoft.Network/virtualNetworks',
    'Microsoft.Storage/storageAccounts',
    'Microsoft.Sql/servers',
    'Microsoft.Sql/databases',
    'Microsoft.Web/sites',
    'Microsoft.Web/serverfarms',
    'Microsoft.RecoveryServices/vaults',
    'Microsoft.CognitiveServices/accounts'
)

Write-Output 'Cycle through Resource Groups'
for ($i = 1; $i -le 3; $i++) {
    # Cycle through 3 times
    Write-Output "Pass $i"
    $ResourceGroups | ForEach-Object -Parallel {
        param($ResourceGroup, $i, $ExemptedResourceGroups, $deletionOrder)
        function Is-ExemptedResourceGroup($rgName, $exemptList) {
            foreach ($pattern in $exemptList) {
                if ($rgName -like $pattern) { return $true }
            }
            return $false
        }
        $ResourceGroupName = $ResourceGroup.ResourceGroupName
        if (Is-ExemptedResourceGroup $ResourceGroupName $ExemptedResourceGroups) {
            Write-Output "Skipping exempted resource group: $ResourceGroupName"
            return
        }

        # check for locks
        Write-Output 'Remove Resource Group Lock if exist'
        try {
            Get-AzResourceLock -ResourceGroupName $ResourceGroupName | Remove-AzResourceLock -Force
        }
        catch {
            $msg = "Failed to delete resource lock for RG - $ResourceGroupName: $($_.Exception.Message)"
            Write-Error $msg
            Write-Log $msg 'ERROR'
        }

        # begin attempts to delete objects

        Write-Output 'Check for Recovery Services Vaults and delete them'
        if ($Vaults = Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroupName) {
            foreach ($vault in $Vaults) {
                Remove-RecoveryServicesVault -VaultName $vault.Name -ResourceGroupName $ResourceGroupName
            }
        }

        Write-Output 'Check for OpenAI objects and delete them'
        if ($OpenAIResource = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.CognitiveServices/accounts') {
            Remove-OpenAIResource -ResourceGroupName $ResourceGroupName -OpenAIResourceName $OpenAIResource.Name
        }

        # Delete all App Services and Function Apps before deleting ASPs
        Write-Output 'Deleting all App Services and Function Apps before deleting App Service Plans'
        $webSites = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Web/sites'
        foreach ($site in $webSites) {
            try {
                Write-Output "Deleting App Service or Function App: $($site.Name)"
                Remove-AzResource -ResourceId $site.Id -Force
            }
            catch {
                $msg = "Error deleting App Service/Function App $($site.Name): $($_.Exception.Message)"
                Write-Warning $msg
                Write-Log $msg 'ERROR'
            }
        }

        # Delete all App Service Plans before deleting ASEs
        Write-Output 'Deleting all App Service Plans before deleting App Service Environments'
        $serverFarms = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Web/serverfarms'
        foreach ($plan in $serverFarms) {
            try {
                Write-Output "Deleting App Service Plan: $($plan.Name)"
                Remove-AzResource -ResourceId $plan.Id -Force
            }
            catch {
                $msg = "Error deleting App Service Plan $($plan.Name): $($_.Exception.Message)"
                Write-Warning $msg
                Write-Log $msg 'ERROR'
            }
        }

        # Delete all App Service Environments
        $ases = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Web/hostingEnvironments'
        foreach ($ase in $ases) {
            try {
                Write-Output "Deleting App Service Environment: $($ase.Name)"
                Remove-AzResource -ResourceId $ase.Id -Force
            }
            catch {
                $msg = "Error deleting App Service Environment $($ase.Name): $($_.Exception.Message)"
                Write-Warning $msg
                Write-Log $msg 'ERROR'
            }
        }

        # Remove route table and NSG from subnets before deleting subnets or VNets
        Write-Output 'Removing route tables and NSGs from subnets before deleting subnets or VNets'
        $vnets = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        foreach ($vnet in $vnets) {
            foreach ($subnet in $vnet.Subnets) {
                $subnetChanged = $false
                if ($subnet.NetworkSecurityGroup) {
                    Write-Output "Removing NSG from subnet $($subnet.Name) in VNet $($vnet.Name)"
                    $subnet.NetworkSecurityGroup = $null
                    $subnetChanged = $true
                }
                if ($subnet.RouteTable) {
                    Write-Output "Removing Route Table from subnet $($subnet.Name) in VNet $($vnet.Name)"
                    $subnet.RouteTable = $null
                    $subnetChanged = $true
                }
                if ($subnetChanged) {
                    Set-AzVirtualNetwork -VirtualNetwork $vnet | Out-Null
                }
            }
        }

        Write-Output 'Remove all Public IP Addresses'
        Remove-PublicIPs -ResourceGroupName $ResourceGroup.ResourceGroupName

        Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName | Remove-AzPublicIpAddress -Force

        Write-Output "Get List of Objects in $ResourceGroupName"
        $ResourceGroupObjects = Get-AzResource -ResourceGroupName $ResourceGroupName

        Write-Output 'Delete resources in dependency order'
        foreach ($type in $deletionOrder) {
            $resourcesOfType = $ResourceGroupObjects | Where-Object { $_.ResourceType -eq $type }
            foreach ($resource in $resourcesOfType) {
                try {
                    Write-Output "Trying to Delete $($resource.name) of type $($resource.ResourceType)"
                    Remove-AzResource -ResourceId $resource.Id -Force
                }
                catch {
                    $msg = "Error deleting $($resource.ID): $($_.Exception.Message)"
                    Write-Warning $msg
                    Write-Log $msg 'ERROR'
                }
            }
        }

        # Delete any remaining resources
        $remaining = Get-AzResource -ResourceGroupName $ResourceGroupName
        foreach ($resource in $remaining) {
            try {
                Write-Output "Trying to Delete remaining $($resource.name) of type $($resource.ResourceType)"
                Remove-AzResource -ResourceId $resource.Id -Force
            }
            catch {
                $msg = "Error deleting $($resource.ID): $($_.Exception.Message)"
                Write-Warning $msg
                Write-Log $msg 'ERROR'
            }
        }

        # Purge-SoftDeletedKeyVaults -ResourceGroupName $ResourceGroupName
    } -ThrottleLimit 4 -ArgumentList $i, $ExemptedResourceGroups, $deletionOrder
}

# Set log file path (customize as needed)
$LogFile = Join-Path -Path $env:TEMP -ChildPath "azure_cleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp][$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry
}

Write-Output "Cleanup complete. Log file: $LogFile"
Write-Log 'Cleanup complete for all resource groups.' 'INFO'

# Track end time and calculate duration
$scriptEnd = Get-Date
$duration = $scriptEnd - $scriptStart

# Collect error log entries
$ErrorEntries = Get-Content $LogFile | Where-Object { $_ -match '\[ERROR\]' }
$ErrorSummary = if ($ErrorEntries) { $ErrorEntries -join "`n" } else { 'No errors encountered.' }

# Output summary for Azure Monitor/Log Analytics
$summaryLine = "CLEANUP SUMMARY: Start=$scriptStart End=$scriptEnd Duration=$($duration.ToString()) Failures=$($ErrorEntries.Count)"
Write-Output $summaryLine
Write-Log $summaryLine 'INFO'