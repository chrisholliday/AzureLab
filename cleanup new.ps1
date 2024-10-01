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
    [Parameter (Mandatory = $false)]
    $SubscriptionName = 'launchpad',

    [paramater (Mandatory = $false)]
    $tenant = 'myazuretenant'
)


#Defining any Variables

# These resource groups will be excluded from consideration in this script
$exceptionlist = @(
    'Resource Group 1',
    'Resource Group 2',
    'My test Group'
)

Write-Output 'Connecting to Azure'
Connect-AzAccount -Identity -Tenant $tenant -Subscription $SubscriptionName

Write-Output 'Validating Subscription'
$Context = Get-AzContext
if ($Context.Subscription.Name -ne $SubscriptionName) {
    Write-Output "Failed to run against $SubscriptionName"
    Exit
}

# delete app services
# delete app service plans
# delete ase objects

# unregister public ips
# unregister nsg
# unregister route table

# remove ai deployments
# remove ai objects

# 


$allInScopeObjects = Get-AzResource | Where-Object {$_.ResourceGroupName -notin $exceptionlist}


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


$accounts = Get-AzCognitiveServicesAccount

foreach ($account in $accounts){
    $Deployments = Get-AzCognitiveServicesAccountDeployment -AccountName $account.AccountName -ResourceGroupName $account.ResourceGroupName
    
    foreach ($deployment in $Deployments){
        Remove-AzCognitiveServicesAccountDeployment -AccountName $account.AccountName -ResourceGroupName $account.ResourceGroupName -Name $deployment.Name -Force
    }
    Remove-AzCognitiveServicesAccount -ResourceGroupName $account.ResourceGroupName -Name $account.AccountName
    # Remove-AzCognitiveServicesAccountDeployment -AccountName $account.AccountName -ResourceGroupName $account.ResourceGroupName -Name -Force

}
