<#
A simple script to populate the firewall of the Storage Account with sample IP information.
I use this to help stage an object to test the 'correct' version of the script.
#>

$RG = cjh1

$MyStorageAccounts = Get-AzStorageAccount -ResourceGroupName $RG

foreach ($StorageAccount in $MyStorageAccounts) {
    $RG = $StorageAccount.ResourceGroupName
    $Name = $StorageAccount.StorageAccountName

    Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $RG -Name $Name -DefaultAction Deny
    Add-AzStorageAccountNetworkRule -ResourceGroupName $RG -Name $Name -IPAddressOrRange "12.1.3.1"
    Add-AzStorageAccountNetworkRule -ResourceGroupName $RG -Name $Name -IPAddressOrRange "12.1.3.2"
    Add-AzStorageAccountNetworkRule -ResourceGroupName $RG -Name $Name -IPAddressOrRange "12.1.3.3"
    Add-AzStorageAccountNetworkRule -ResourceGroupName $RG -Name $Name -IPAddressOrRange "12.1.3.4"
    Add-AzStorageAccountNetworkRule -ResourceGroupName $RG -Name $Name -IPAddressOrRange "12.1.4.0/24"
    Add-AzStorageAccountNetworkRule -ResourceGroupName $RG -Name $Name -IPAddressOrRange "12.1.5.0/24"
    Add-AzStorageAccountNetworkRule -ResourceGroupName $RG -Name $Name -IPAddressOrRange "8.8.8.8"
    Add-AzStorageAccountNetworkRule -ResourceGroupName $RG -Name $Name -IPAddressOrRange "4.4.4.4"
    Add-AzStorageAccountNetworkRule -ResourceGroupName $RG -Name $Name -IPAddressOrRange "1.0.1.0/24"
    Add-AzStorageAccountNetworkRule -ResourceGroupName $RG -Name $Name -IPAddressOrRange "2.0.2.0/24"
}