[CmdletBinding()]
<#
.SYNOPSIS
    Deletes all objects within a given subscripiton
.DESCRIPTION
    This script will help to clean up a test subscritpion were you need to regulally remove all objects. This might
    be because you need to save money, minimize your threat vectors, or just keep the enviornment clean.
.NOTES
    Developed on Powershell 7.4.5

.EXAMPLE
    #Todo
#>

param (
    [Parameter (Mandatory)]
    $SubscriptionName = 'mysub',

    [paramater (Mandatory)]
    $tenant = 'foo.onmicrosoft.com'
)

function Remove-BackupItems {
    [CmdletBinding()]
    param (
        $BackupContainer,
        $vault,
        [String]$Type
    )
    Write-Output "Setting Vault Context for $($vault.name)"
    Set-AzRecoveryServicesVaultContext -Vault $Vault

    foreach ($Container in $BackupContainer) {
        If ($Type = 'VM') {
            $BackupItems = Get-AzRecoveryServicesBackupItem -Container $Container -WorkloadType AzureVM
        }
        Else {
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
    [CmdletBinding()]
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
    If ($VM_Container) {
        Remove-BackupItems -BackupContainer $VM_Containers -Vault $Vault -Type VM
    }

    $SQL_Container = Get-AzRecoveryServicesBackupContainer -VaultId $vault.ID -ContainerType AzureSQL
    If ($SQL_Container) {
        Remove-BackupItems -BackupContainer $SQL_Container -Vault $Vault
    }

    $Storage_Container = Get-AzRecoveryServicesBackupContainer -VaultId $vault.ID -ContainerType AzureStorage
    If ($Storage_Container) {
        Remove-BackupItems -BackupContainer $Storage_Container -Vault $Vault
    }

    $App_Container = Get-AzRecoveryServicesBackupContainer -VaultId $vault.ID -ContainerType AzureVMAppContainer
    If ($App_Container) {
        Remove-BackupItems -BackupContainer $App_Container -Vault $Vault
    }

    $Windows_Container = Get-AzRecoveryServicesBackupContainer -VaultId $vault.ID -ContainerType Windows -BackupManagementType MAB
    If ($Windows_Container) {
        Remove-BackupItems -BackupContainer $Windows_Container -Vault $Vault
    }
    # Remove the Recovery Services vault
    If ($i -gt 1) {
        Write-Output "Attempting to delete $($Vault.Name)"
        Remove-AzRecoveryServicesVault -Vault $Vault
    }
}




#Defining any Variables

# These resource groups will be excluded from consideration in this script
$exemptrg = @(
    'ResourceGroup1',
    'ResourceGroup2'
)

Write-Output 'Connecting to Azure'
Connect-AzAccount -Identity -Tenant $tenant -Subscription $SubscriptionName

Write-Output 'Validating Subscription'
$Context = Get-AzContext
if ($Context.Subscription.Name -ne $SubscriptionName) {
    Write-Output "Failed to run against $SubscriptionName"
    Exit
}

Write-Output 'Deleting Resource Locks'
Get-AzResourceLock | Where-Object { $_.ResourceGroupName -notin $exemptrg } | Remove-AzResourceLock -Force | Out-Null

Write-Output 'Check for Recovery Services Vaults and delete them'
if ($Vaults = Get-AzRecoveryServicesVault | Where-Object { $_.ResourceGroupName -notin $exemptrg }) {
    foreach ($vault in $Vaults) {
        Set-AzRecoveryServicesVaultProperty -VaultId $Vault.ID -SoftDeleteFeatureState Disable | Out-Null
        # Remove-RecoveryServicesVault -VaultName $vault.Name -ResourceGroupName $vault.ResourceGroupName
    }
}

Write-Output 'Deleting Web Objects'
Get-AzWebApp | Where-Object { $_.ResourceGroupName -notin $exemptrg } | Remove-AzResource -Force
Get-AzAppServicePlan | Where-Object { $_.ResourceGroupName -notin $exemptrg } | Remove-AzResource -Force
Get-AzAppServiceEnvironment | Where-Object { $_.ResourceGroupName -notin $exemptrg } | Remove-AzResource -Force


#doesn't work, problems with networkinterface var
Write-Output 'Deleting Network Components'
$networkInterfaces = Get-AzNetworkInterface | Where-Object { $_.ResourceGroupName -notin $exemptrg }
foreach ($networkInterface in $networkInterfaces.IpConfigurations) {
    if ($null -ne $networkInterface.PublicIpAddress) {
        # Disassociate the public IP address
        $networkInterface.PublicIpAddress = $null
        Set-AzNetworkInterface -NetworkInterface $networkInterface -WhatIf
        # Write-Output "Disassociated public IP from NIC: $($networkInterface.Name)"
    }
}


#doesn't work problems with hashtable
$VirtualNetworks = Get-AzVirtualNetwork | Where-Object { $_.ResourceGroupName -notin $exemptrg }
foreach ($VirtualNetwork in $VirtualNetworks) {
    foreach ($subnet in $VirtualNetwork.Subnets) {
        $params = @{
            Name                 = $subnet.Name
            VirtualNetwork       = $VirtualNetwork.Name
            AddressPrefix        = $subnet.AddressPrefix
            NetworkSecurityGroup = $null
            RouteTable           = $null
        }
       
        Set-AzVirtualNetworkSubnetConfig @params -WhatIf
    }
}

# Get-AzPublicIpAddress | Where-Object { $_.ResourceGroupName -notin $exemptrg } | Remove-AzResource -Force -WhatIf

Write-Output 'Deleting OpenAI components'
$cognitiveServicesResources = Get-AzResource -ResourceType 'Microsoft.CognitiveServices/accounts' |
    Where-Object { $_.ResourceGroupName -notin $exemptrg }

# Loop through each resource
foreach ($resource in $cognitiveServicesResources) {
    # Retrieve the endpoint and API key for the OpenAI resource
    $resourceProperties = Get-AzCognitiveServicesAccount -ResourceGroupName $resource.ResourceGroupName -Name $resource.Name
    $endpoint = $resourceProperties.Endpoint
    $apiKey = (Get-AzCognitiveServicesAccountKey -ResourceGroupName $resource.ResourceGroupName -Name $resource.Name).Key1

    # List the deployed models
    $uri = "$endpoint/openai/models?api-version=2024-06-01"
    $headers = @{
        'api-key' = $apiKey
    }
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

    # Delete each deployed model
    foreach ($model in $response.data) {
        $modelUri = "$endpoint/openai/models/$($model.id)?api-version=2024-06-01"
        Invoke-RestMethod -Uri $modelUri -Headers $headers -Method Delete
    }

    # Delete the Cognitive Services resource
    Remove-AzResource -ResourceId $resource.ResourceId -Force
}

Write-Output 'Deleting everything else'
Get-AzResource | Where-Object { $_.ResourceGroupName -notin $exceptionlist } | Remove-AzResource -Force