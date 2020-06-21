$MyKeyVaults = Get-AzKeyVault -ResourceGroupName cjh1

foreach ($KeyVault in $MyKeyVaults) {
    $RG = $KeyVault.ResourceGroupName
    $Name = $KeyVault.VaultName

    Update-AzKeyVaultNetworkRuleSet -ResourceGroupName $RG -VaultName $Name -DefaultAction 'Deny'

    Add-AzKeyVaultNetworkRule -ResourceGroupName $RG -VaultName $Name -IPAddressRange "12.1.3.1"
    Add-AzKeyVaultNetworkRule -ResourceGroupName $RG -VaultName $Name -IPAddressRange "12.1.3.2"
    Add-AzKeyVaultNetworkRule -ResourceGroupName $RG -VaultName $Name -IPAddressRange "12.1.3.3"
    Add-AzKeyVaultNetworkRule -ResourceGroupName $RG -VaultName $Name -IPAddressRange "12.1.3.4"
    Add-AzKeyVaultNetworkRule -ResourceGroupName $RG -VaultName $Name -IPAddressRange "12.1.4.0/24"
    Add-AzKeyVaultNetworkRule -ResourceGroupName $RG -VaultName $Name -IPAddressRange "12.1.5.0/24"
    Add-AzKeyVaultNetworkRule -ResourceGroupName $RG -VaultName $Name -IPAddressRange "8.8.8.8"
    Add-AzKeyVaultNetworkRule -ResourceGroupName $RG -VaultName $Name -IPAddressRange "4.4.4.4"
    Add-AzKeyVaultNetworkRule -ResourceGroupName $RG -VaultName $Name -IPAddressRange "1.0.1.0/24"
    Add-AzKeyVaultNetworkRule -ResourceGroupName $RG -VaultName $Name -IPAddressRange "2.0.2.0/24"
}