param (
    [Parameter (Mandatory=$false)]
    [string] $Subscription = "Sub1"
)

#Requires -Version 7.4 #Tested only on Version 7.4


Import-Module Az.Resources
Import-Module Az.Accounts

#Requires -Modules @{ ModuleName="Az.Resources"; ModuleVersion="0.12.0" }
#Requires -Modules Az.Resources

#Connect-AzAccount -Identity -Subscription $Subscription

function Write-ErrorMessage {
    Write-Output 'Failed to get list of deleted objects'
    Write-Output '-------------------------------------'
    Write-Output $Error[0]
    throw
}

try {
    $id = (Get-AzSubscription -SubscriptionName $subscription).SubscriptionId
    $ResourceId = "/subscriptions/$id/providers/Microsoft.CognitiveServices/deletedAccounts"
    $DeletedObjects = Get-AzResource -ResourceId $ResourceId
}
catch {
    Write-ErrorMessage
}

try {
    foreach ($DeletedObject in $DeletedObjects) {
        $OpenAIName = $DeletedObject.Name
        Write-Output "Starting puge of $OpenAIName"
        Remove-AzResource -ResourceId $DeletedObject.ResourceId -ApiVersion 2021-04-30 -Force | Out-Null
    }
}
catch {
    Write-ErrorMessage
}