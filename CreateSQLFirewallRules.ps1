<#
A simple script to populate the firewall of the SQL Server with sample IP information.
I use this to help stage an object to test the 'correct' version of the script.
#>

$rg = cjh1

$MySQLServers = Get-AzSqlServer -ResourceGroupName $rg
foreach ($SQLServer in $MySQLServers) {
    $SQLServer | New-AzSqlServerFirewallRule -FirewallRuleName 'Test1' -StartIpAddress '8.8.8.8' -EndIpAddress '8.8.8.8'
    $SQLServer | New-AzSqlServerFirewallRule -FirewallRuleName 'Test2' -StartIpAddress '4.4.4.4' -EndIpAddress '4.4.4.4'
    $SQLServer | New-AzSqlServerFirewallRule -FirewallRuleName 'Test3' -StartIpAddress '1.0.1.0' -EndIpAddress '1.0.1.255'
    $SQLServer | New-AzSqlServerFirewallRule -FirewallRuleName 'Test4' -StartIpAddress '2.0.2.0' -EndIpAddress '2.0.2.4'
    $SQLServer | New-AzSqlServerFirewallRule -FirewallRuleName 'Fully Open' -StartIpAddress '0.0.0.0' -EndIpAddress '0.0.0.0'
      
}