<#
A simple script to populate the firewall of the ServiceBus with sample IP information.
I use this to help stage an object to test the 'correct' version of the script.

This doesn't currently work.
#>

$rg = cjh1

$MyServiceBuses = Get-AzServiceBusNamespace -ResourceGroupName $rg

foreach ($ServiceBus in $MyServiceBuses) {
    $RG = $ServiceBus.ResourceGroupName
    $Name = $ServiceBus.Name

    # Set-AzServiceBusNetworkRuleSet -ResourceGroupName $RG -Name $Name -DefaultAction allow
    Add-AzServiceBusIPRule -ResourceGroupName cjh1 -Name cjh-test -IpMask 8.8.8.8
    <#
    Add-AzServiceBusIPRule -ResourceGroupName $RG -Name $Name -IpMask "12.1.3.1" -
    Add-AzServiceBusIPRule -ResourceGroupName $RG -VaultName $Name -IpMask "12.1.3.2"
    Add-AzServiceBusIPRule -ResourceGroupName $RG -VaultName $Name -IpMask "12.1.3.3"
    Add-AzServiceBusIPRule -ResourceGroupName $RG -VaultName $Name -IpMask "12.1.3.4"
    Add-AzServiceBusIPRule -ResourceGroupName $RG -VaultName $Name -IpMask "12.1.4.0/24"
    Add-AzServiceBusIPRule -ResourceGroupName $RG -VaultName $Name -IpMask "12.1.5.0/24"
    Add-AzServiceBusIPRule -ResourceGroupName $RG -VaultName $Name -IpMask "8.8.8.8"
    Add-AzServiceBusIPRule -ResourceGroupName $RG -VaultName $Name -IpMask "4.4.4.4"
    Add-AzServiceBusIPRule -ResourceGroupName $RG -VaultName $Name -IpMask "1.0.1.0/24"
    Add-AzServiceBusIPRule -ResourceGroupName $RG -VaultName $Name -IpMask "2.0.2.0/24"
    #>
}