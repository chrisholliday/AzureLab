$subscription = 'sub1'

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
        Remove-AzResource -ResourceId $DeletedObject.ResourceId -ApiVersion 2021-04-30 -Force
    }
}
catch {
Write-ErrorMessage
}