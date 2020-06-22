<#
Very Simple script to reconfigure all Storage Accounts in a given resource group such that only
a preallowed set of Public IP addresses are in the firewall section of the Storage Accounts.  All
non-approved IP addresses will be removed, and any missing allowed IP addresses will be
added to the firewall. 
#>

$AllowedIPAddresses = @(
    '8.8.8.8'
    '4.4.4.4'
    '1.0.1.0/24'
    '2.0.2.0/24'
)

$MyStorageAccounts = Get-AzStorageAccount -ResourceGroupName cjh1
foreach ($StorageAccount in $MyStorageAccounts) {
    $RG = $StorageAccount.ResourceGroupName
    $Name = $StorageAccount.StorageAccountName

    $NetworkRuleSet = Get-AzStorageAccountNetworkRuleSet -ResourceGroupName $RG -Name $Name
    $DefaultAction = $NetworkRuleSet.DefaultAction

    if ($NetworkRuleSet.DefaultAction -ne 'Deny') {
        Write-Output "Storage Account $name is set to Unrestricted."
        Write-Output 'Attempting to automatically correct the problem'
        Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $RG -Name $Name -DefaultAction Deny
        
        $DefaultAction = (Get-AzStorageAccountNetworkRuleSet -ResourceGroupName $RG -Name $Name).DefaultAction
        if ($DefaultAction -eq 'Allow') {
            Write-Output "Failed to update $Name storeage account firewall"
        }

        elseif ($DefaultAction -eq 'Deny') {
            Write-Output "Storage Account $name firewall updated correctly"
        }
        else {
            Write-Output "Unable to determine $name firewall status"
        }
            
    }

    $Rules = $NetworkRuleSet | Select-Object -ExpandProperty IPRules
    foreach ($Rule in $Rules) {
        $IP = $Rule.IPAddressOrRange
        
        if ($IP -notin $AllowedIPAddresses) {
            Write-Output "Invaild firewall rule detected - $IP"
            Write-Output "Deleting rule"
            Remove-AzStorageAccountNetworkRule -ResourceGroupName $RG -Name $Name -IPAddressOrRange $IP > $null
        }
       
    }  
    $DefinedRules = $Rules.IPAddressOrRange
    foreach ($AllowedIP in $AllowedIPAddresses) {
        If ($AllowedIP -notin $DefinedRules) {
            Write-Output "$AllowedIP is missing from the firewall and is being added"
            Add-AzStorageAccountNetworkRule -ResourceGroupName $RG -Name $Name -IPAddressOrRange $AllowedIP > $null
        }
    }
}

