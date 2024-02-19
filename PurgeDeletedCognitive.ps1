param (
    [Parameter (Mandatory=$false)]
    [string] $Subscription = "Sub1"
)

Import-Module Az.Resources
Import-Module Az.Accounts

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
    Write-Output "waiting for objects to be deleted"
    Start-Sleep -Seconds 300

    foreach ($DeletedObject in $DeletedObjects){
        if ($DeletedObject) {
            Write-Output "Failed to purge $OpenAIName"
        }
        else {
            if (not $DeletedObject) {
                Write-Output "Deleted object $OpenAIName has been purged"
            }
        }
    }
}

catch {
    Write-ErrorMessage
}