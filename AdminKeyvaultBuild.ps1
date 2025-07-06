#!/usr/bin/env pwsh
#requires -Version 5.1
#requires -Modules Az.KeyVault
using namespace System.Text

<#
.SYNOPSIS
    Creates or updates an Azure Key Vault secret containing a list of exempted resource groups for sandbox cleanup automation.

.DESCRIPTION
    This script creates a resource group and Key Vault if they do not exist, then stores a list of exempted resource groups as a JSON array in a Key Vault secret. The exemption list can be provided as an array or loaded from a file (plain text or JSON). Optionally, you can grant an Automation Account managed identity access to the Key Vault. Supports -WhatIf and -Confirm.

.PARAMETER ResourceGroup
    The name of the Azure resource group to use or create.

.PARAMETER AzureLocation
    The Azure region for the resource group and Key Vault (e.g., 'eastus').

.PARAMETER KeyVaultName
    The name of the Azure Key Vault to use or create.

.PARAMETER SecretName
    The name of the Key Vault secret to store the exemption list. Defaults to 'ExemptResourceGroups'.

.PARAMETER ExemptList
    An array of resource group names or wildcard patterns to exempt from deletion.

.PARAMETER ExemptListFile
    Path to a file containing the exemption list (one per line or as a JSON array).

.EXAMPLE
    .\AdminKeyvaultBuild.ps1 -ResourceGroup 'my-rg' -AzureLocation 'eastus' -KeyVaultName 'myKeyVault' -ExemptList 'prod-rg','shared-infra'

.EXAMPLE
    .\AdminKeyvaultBuild.ps1 -ResourceGroup 'my-rg' -AzureLocation 'eastus' -KeyVaultName 'myKeyVault' -ExemptListFile './exemptions.json'

.NOTES
    Author: Chris Holliday
    Date: 2025-07-04
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,
    [Parameter(Mandatory = $true)]
    [ValidateSet('eastus', 'eastus2', 'centralus', 'northcentralus', 'southcentralus', 'westus', 'westus2', 'westus3', 'westcentralus')]
    [string]$AzureLocation,
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,
    [Parameter()]
    [string]$SecretName = 'ExemptResourceGroups',
    [string[]]$ExemptList = @(),
    [string]$ExemptListFile = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'

# Verify Azure PowerShell context
Write-Verbose 'Checking Azure PowerShell context...'
$context = Get-AzContext
if (-not $context) {
    throw 'No Azure context found. Please run Connect-AzAccount first.'
}
Write-Verbose "Using subscription: $($context.Subscription.Name)"

# Verify KeyVault module is loaded
Write-Verbose 'Verifying Az.KeyVault module...'
if (-not (Get-Module -Name Az.KeyVault)) {
    Write-Verbose 'Importing Az.KeyVault module...'
    Import-Module Az.KeyVault -Verbose
}

# If ExemptListFile is provided, load exemptions from file (one per line or JSON array)
if ($ExemptListFile -and (Test-Path $ExemptListFile)) {
    try {
        $fileContent = Get-Content $ExemptListFile -Raw
        if ($fileContent.Trim().StartsWith('[')) {
            $ExemptList = $fileContent | ConvertFrom-Json
        }
        else {
            $ExemptList = $fileContent -split "`r?`n" | Where-Object { $_ -ne '' }
        }
    }
    catch {
        Write-Warning 'Could not read exemption list from file. Using provided array or default.'
    }
}

# 1. Create the resource group if it doesn't exist
if (-not (Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess("Resource group $ResourceGroup in $AzureLocation", 'Create resource group')) {
        Write-Output "Creating resource group $ResourceGroup in $AzureLocation"
        New-AzResourceGroup -Name $ResourceGroup -Location $AzureLocation
    }
}

# 2. Validate Key Vault name
if ($KeyVaultName.Length -lt 3 -or $KeyVaultName.Length -gt 24 -or $KeyVaultName -notmatch '^[a-zA-Z0-9-]+$' -or $KeyVaultName.StartsWith('-') -or $KeyVaultName.EndsWith('-')) {
    throw "Key Vault name '$KeyVaultName' is invalid. It must be 3-24 characters, alphanumeric or dashes, and start/end with a letter or number."
}

# 3. Check if Key Vault name is in a soft-deleted state, and if it is globally available
Write-Verbose "Checking for soft-deleted KeyVault with name: $KeyVaultName in location: $AzureLocation"
try {
    Write-Verbose "Parameters for Get-AzKeyVault: VaultName=$KeyVaultName, Location=$AzureLocation, InRemovedState=true"
    $softDeletedKV = Get-AzKeyVault -InRemovedState -VaultName $KeyVaultName -Location $AzureLocation -ErrorAction Stop
    if ($softDeletedKV) {
        Write-Verbose "Found soft-deleted KeyVault: $($softDeletedKV.VaultName) in location: $($softDeletedKV.Location)"
        Write-Output 'Found soft-deleted KeyVault. Attempting to purge it...'
        if ($PSCmdlet.ShouldProcess("Soft-deleted Key Vault $KeyVaultName", 'Purge')) {
            Remove-AzKeyVault -VaultName $KeyVaultName -Location $AzureLocation -InRemovedState -Force
            Write-Output 'Successfully purged soft-deleted Key Vault'
            # Wait a moment for purge to complete
            Start-Sleep -Seconds 30
        }
    }
}
catch {
    if ($_.Exception.Message -notlike "*'$KeyVaultName' was not found*") {
        Write-Verbose "Error checking for soft-deleted KeyVault: $_"
        throw
    }
    Write-Verbose "No soft-deleted KeyVault found with name '$KeyVaultName' in $AzureLocation"
}

Write-Verbose "Checking if KeyVault name '$KeyVaultName' is available globally"
$kvCheck = Test-AzName -Name $KeyVaultName -ResourceType 'Microsoft.KeyVault/vaults'
Write-Verbose "Test-AzName result: $($kvCheck | ConvertTo-Json)"

if ($kvCheck.NameAvailable -eq $false) {
    Write-Verbose "KeyVault name is not available globally, checking if it exists in resource group: $ResourceGroup"
    try {
        Write-Verbose "Parameters for Get-AzKeyVault: VaultName=$KeyVaultName, ResourceGroupName=$ResourceGroup"
        $existingKv = Get-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $ResourceGroup -ErrorAction Stop
        Write-Verbose "Existing KeyVault check result: $(if ($existingKv) { 'Found' } else { 'Not Found' })"
        if ($null -eq $existingKv) {
            throw "Key Vault name '$KeyVaultName' is already in use globally. Please choose a different name."
        }
    }
    catch {
        Write-Verbose "Error checking for existing KeyVault: $_"
        throw
    }
}

# 4. Create the Key Vault if it doesn't exist
Write-Verbose "Checking if KeyVault exists in resource group: $ResourceGroup"
$existingVault = Get-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
if (-not $existingVault) {
    Write-Verbose 'KeyVault not found in resource group, attempting to create'
    if ($PSCmdlet.ShouldProcess("Key Vault $KeyVaultName in $ResourceGroup", 'Create Key Vault')) {
        Write-Output "Creating Key Vault $KeyVaultName in $ResourceGroup"
        
        # Get current user's object ID
        $currentUser = Get-AzADUser -SignedIn
        if (-not $currentUser) {
            # Fallback to get user from context
            $context = Get-AzContext
            $currentUser = Get-AzADUser -UserPrincipalName $context.Account.Id
        }

        if (-not $currentUser) {
            throw "Could not determine current user identity. Please ensure you're properly logged into Azure."
        }

        # Create Key Vault with access policy for current user
        try {
            New-AzKeyVault -Name $KeyVaultName `
                -ResourceGroupName $ResourceGroup `
                -Location $AzureLocation `
                -EnableRbacAuthorization $false `
                -EnablePurgeProtection $true `
                -Sku Standard -ErrorAction Stop
            
            # Set access policy for current user
            Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName `
                -ResourceGroupName $ResourceGroup `
                -UserPrincipalName $currentUser.UserPrincipalName `
                -PermissionsToSecrets get, list, set, delete
        }
        catch {
            throw "Failed to create Key Vault '$KeyVaultName'. Error: $_"
        }
    }
}

# Verify Key Vault exists before proceeding
if (-not (Get-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue)) {
    # If we are in -WhatIf mode, the vault won't exist, so we shouldn't try to set the secret.
    if (-not $PSCmdlet.ShouldProcess("Key Vault $KeyVaultName secret $SecretName", 'Set exemption list secret')) {
        Write-Warning "Key Vault '$KeyVaultName' does not exist. Skipping secret creation because we are likely in -WhatIf mode."
        # Exit the script gracefully
        return
    }
    else {
        throw "Key Vault '$KeyVaultName' was not found or created successfully. Cannot proceed to set secret."
    }
}

# 5. Store the exemption list as a JSON array in the Key Vault
$jsonList = $ExemptList | ConvertTo-Json
if ($PSCmdlet.ShouldProcess("Key Vault $KeyVaultName secret $SecretName", 'Set exemption list secret')) {
    Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -SecretValue (ConvertTo-SecureString $jsonList -AsPlainText -Force)
    Write-Output "Exemption list stored in Key Vault secret '$SecretName'"
}

# 6. (Optional) Grant Automation Account managed identity access to Key Vault
# Uncomment and update the automation account name if you want to set this up automatically
# param([string]$AutomationAccountName)
# if ($PSCmdlet.ShouldProcess("Key Vault $KeyVaultName access policy for Automation Account", "Grant access")) {
#     $identity = (Get-AzAutomationAccount -ResourceGroupName $ResourceGroup -Name $AutomationAccountName).Identity.PrincipalId
#     Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName -ObjectId $identity -PermissionsToSecrets get
#     Write-Output "Granted Automation Account managed identity access to Key Vault secrets"
# }
