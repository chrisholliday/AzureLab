<#
.SYNOPSIS
    Automates setup of Azure Monitor for Automation Account cleanup notifications.
.DESCRIPTION
    This script creates (if needed) a Log Analytics workspace, enables diagnostic settings on an Automation Account to send logs to Log Analytics, creates an Action Group for email notifications, and creates an Alert Rule that triggers on a custom summary string in job logs.
.PARAMETER ResourceGroupName
    The resource group for the Automation Account and Log Analytics workspace.
.PARAMETER AutomationAccountName
    The name of the Automation Account to monitor.
.PARAMETER WorkspaceName
    The name of the Log Analytics workspace to use or create.
.PARAMETER Location
    The Azure region for the workspace (e.g., 'eastus').
.PARAMETER EmailAddress
    The email address to notify.
.EXAMPLE
    .\Setup-AzureMonitorCleanupAlert.ps1 -ResourceGroupName 'my-rg' -AutomationAccountName 'my-automation' -WorkspaceName 'my-law' -Location 'eastus' -EmailAddress 'me@domain.com'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$ResourceGroupName,
    [Parameter(Mandatory)] [string]$AutomationAccountName,
    [Parameter(Mandatory)] [string]$WorkspaceName,
    [Parameter(Mandatory)] [string]$Location,
    [Parameter(Mandatory)] [string]$EmailAddress
)

# 1. Create Log Analytics workspace if needed
if (-not (Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -ErrorAction SilentlyContinue)) {
    Write-Output "Creating Log Analytics workspace $WorkspaceName in $ResourceGroupName..."
    New-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -Location $Location -Sku Standard
}

# 2. Enable diagnostic settings for Automation Account
$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName
$automation = Get-AzAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName
$diagName = 'SendToLogAnalytics'
if (-not (Get-AzDiagnosticSetting -ResourceId $automation.Id | Where-Object { $_.Name -eq $diagName })) {
    Write-Output 'Enabling diagnostic settings for Automation Account...'
    Set-AzDiagnosticSetting -Name $diagName -ResourceId $automation.Id -WorkspaceId $workspace.ResourceId -Enabled $true -Category 'JobLogs', 'JobStreams'
}

# 3. Create Action Group for email
$actionGroupName = 'CleanupEmailActionGroup'
$actionGroup = Get-AzActionGroup -ResourceGroupName $ResourceGroupName -Name $actionGroupName -ErrorAction SilentlyContinue
if (-not $actionGroup) {
    Write-Output 'Creating Action Group for email notification...'
    $actionGroup = New-AzActionGroup -ResourceGroupName $ResourceGroupName -Name $actionGroupName -ShortName 'cleanup' -Receiver @(New-AzActionGroupReceiver -Name 'EmailReceiver' -EmailReceiver -EmailAddress $EmailAddress)
}

# 4. Create Alert Rule for summary string
$alertRuleName = 'CleanupSummaryAlert'
$kql = @'
AzureDiagnostics
| where ResourceType == 'AUTOMATIONACCOUNTS'
| where LogEntry has 'CLEANUP SUMMARY'
| project TimeGenerated, LogEntry
'@
$condition = New-AzScheduledQueryRuleCondition -Query $kql -TimeAggregationCount 1 -Operator GreaterThan -Threshold 0 -MetricMeasureColumnName 'LogEntry'
if (-not (Get-AzScheduledQueryRule -ResourceGroupName $ResourceGroupName -Name $alertRuleName -ErrorAction SilentlyContinue)) {
    Write-Output 'Creating Alert Rule for cleanup summary...'
    New-AzScheduledQueryRule -ResourceGroupName $ResourceGroupName -Location $Location -Name $alertRuleName -ActionGroup $actionGroup.Id -Enabled $true -Description 'Alert on cleanup summary' -SourceId $workspace.ResourceId -Condition $condition -Severity 2
}
Write-Output 'Azure Monitor alerting setup complete.'
