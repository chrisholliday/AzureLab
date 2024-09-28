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

#Defining any Variables

# These resource groups will be excluded from consideration in this script
$exceptionlist = @(
    'Resource Group 1',
    'Resource Group 2',
    'My test Group'
)


function Remove-BackupItems {
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
#Todo Add Connection 

Write-Output 'Validating Subscription'
#Todo Add Validation

Write-Output 'Getting List of Resource Groups'
$ResourceGroups = Get-AzResourceGroup -Name 'chris.holliday'

$rgs = Get-AzResourceGroup | Where-Object $_.ResourceGroupName -NotIn $exceptionlist

Write-Output 'Cycle through Resource Groups'
for ($i = 1; $i -le 3; $i++) {
    # Cycle through 3 times

    Write-Output "Pass $i"
    foreach ($ResourceGroup in $ResourceGroups) {
        #Delete all objects in all resource groups
        $ResourceGroupName = $ResourceGroup.ResourceGroupName

        # check for locks
        Write-Output 'Remove Resource Group Lock if exist'
        Try {

            Get-AzResourceLock -ResourceGroupName $ResourceGroupName | Remove-AzResourceLock -Force
        }
        catch {
            Write-Error "Failed to delete resource lock for RG - $ResourcegroupName"       
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

        Write-Output ''
        #todo  delete all app services and function app objects before deleting ASPs

        #todo delete all ASPs before deleting ASE objects

        #todo remove route table and nsg from subnets


        Write-Output 'Remove all Public IP Addresses'
        Remove-PublicIPs -ResourceGroupName $ResourceGroup.ResourceGroupName

        Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName | Remove-AzPublicIpAddress -Force

        Write-Output "Get List of Objects in $ResourceGroupName"
        $ResourceGroupObjects = Get-AzResource -ResourceGroupName $ResourceGroupName

        Write-Output 'Get Number of Objects'
        $ObjectCount = $ResourceGroupObjects.count
      
        if ($ObjectCount -gt 0) {
            foreach ($resource in $ResourceGroupObjects) {

                try {
                    Write-Output "Trying to Delete $($resource.name)"
                    Remove-AzResource -ResourceId $resource.Id -Force
                }
                catch {
                    throw "Error deleting $($resource.ID) `n $($_.Exception)"
                }
                Finally {
                    if (-not (Get-AzResource -ResourceId $($resource.id) -ErrorAction SilentlyContinue)) {
                        Write-Output "DELETED: Resource $($resource.Name)"
                    }
                    else {
                        Write-Output "Failed to Delete $($resource.name)"
                    }
                } 
                #Purge-SoftDeletedKeyVaults -ResourceGroupName $ResourceGroupName
            }
        }
    }
}