$AllowedIPAddresses = @(
    '8.8.8.8'
    '4.4.4.4'
    '1.0.1.0/24'
    '2.0.2.0/24'
)

$rg = 'cjh1'

$MyKeyVaults = Get-AzKeyVault -ResourceGroupName $rg
foreach ($KeyVault in $MyKeyVaults) {
    $RG = $KeyVault.ResourceGroupName
    $Name = $KeyVault.VaultName

    $keyvaultdata = Get-AzKeyVault -ResourceGroupName $rg -VaultName $Name
    $NetworkRuleSet = $keyvaultdata.NetworkAcls
    
    if ($NetworkRuleSet.DefaultAction -ne 'Deny') {
        Write-Output "Key Vault $name is set to Unrestricted."
        Write-Output 'Attempting to automatically correct the problem'
        Update-AzKeyVaultNetworkRuleSet -ResourceGroupName $RG -VaultName $Name -DefaultAction Deny
        
        $DefaultAction = ((Get-AzKeyVault -ResourceGroupName $RG -Name $Name).NetworkACLS).DefaultAction
        if ($DefaultAction -eq 'Allow') {
            Write-Output "Failed to update $Name Key Vault firewall"
        }

        elseif ($DefaultAction -eq 'Deny') {
            Write-Output "Key Vault $name firewall updated correctly"
        }
        else {
            Write-Output "Unable to determine $name firewall status"
        }
            
    }
    
    $Rules = $NetworkRuleSet.IpAddressRanges
    
    Write-Output "hey"
    foreach ($IP in $Rules) {
     
        if ($IP -notin $AllowedIPAddresses) {
            Write-Output "Invaild firewall rule detected - $IP"
            Write-Output "Deleting rule"
            Remove-AzKeyVaultNetworkRule -ResourceGroupName $RG -VaultName $Name -IpAddressRange $IP > $null
            
        }
       
    }  
    foreach ($AllowedIP in $AllowedIPAddresses) {
        If ($AllowedIP -notin $Rules) {
            Write-Output "$AllowedIP is missing from the firewall and is being added"
            Add-AzKeyVaultNetworkRule -ResourceGroupName $RG -VaultName $Name -IpAddressRange $AllowedIP > $null
        }
    }

}

