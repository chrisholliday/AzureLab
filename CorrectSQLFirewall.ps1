<#
Very Simple script to reconfigure all SQL Servers in a given resource group such that only
a preallowed set of Public IP addresses are in the firewall section of the SQL Server.  All
non-approved IP addresses will be removed, and any missing allowed IP addresses will be
added to the firewall. 
#>
$StartIPAddresses = @(
    '8.8.8.8'
    '4.4.4.4'
    '1.0.1.1'
    '2.0.2.1'
)

$EndIPAddresses = @(
    '8.8.8.8'
    '4.4.4.4'
    '1.0.1.255'
    '2.0.2.255'
)

$RG = 'cjh1'

$MySQLServers = Get-AzSqlServer -ResourceGroupName $RG

foreach ($SQLServer in $MySQLServers) {

    Write-Verbose "Checking Starting IP Rules"
    $FirewallRules = $SQLServer | Get-AzSqlServerFirewallRule
    foreach ($FireWallRule in $FirewallRules) {
        if ($FireWallRule.StartIpAddress -notin $StartIPAddresses) {
            $FireWallRule | Remove-AzSqlServerFirewallRule > $null
            $FireWallRuleName = $FireWallRule.FirewallRuleName
            Write-Output "A Firewall Rule was out of policy and removed - $FireWallRuleName"
        }
    }

    Write-Verbose "Checking Ending IP Rules"
    $FirewallRules = $SQLServer | Get-AzSqlServerFirewallRule
    foreach ($FireWallRule in $FirewallRules) {
        if ($FireWallRule.EndIpAddress -notin $EndIPAddresses) {
            $FireWallRule | Remove-AzSqlServerFirewallRule > $null
            $FireWallRuleName = $FireWallRule.FirewallRuleName
            Write-Output "A Firewall Rule was out of policy and removed - $FireWallRuleName"
        }
    } 
    
    Write-Verbose "Add missing Rules"
    $FirewallRules = $SQLServer | Get-AzSqlServerFirewallRule
    $DefinedRules = $FirewallRules.StartIpAddress
    
    $i = 0
    foreach ($StartIPAddress in $StartIPAddresses) {
        If ($StartIPAddress -notin $DefinedRules) {

            $Start = $StartIPAddress
            $End = $EndIPAddresses[$i]

            Write-Output "$StartIPAddress is missing from the firewall and is being added"
            New-AzSqlServerFirewallRule -ResourceGroupName $RG -ServerName $SQLServer.ServerName -FirewallRuleName "$Start - $End" -StartIpAddress $Start -EndIpAddress $End
            
        }
        $i++

    }
}