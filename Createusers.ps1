try {
    $users = Import-Csv  -Path ~/onedrive/documents/newusers.csv
}
catch {
    Write-Output "user file not found"
    exit
}

$PasswordProfile = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordProfile
$PasswordProfile.Password = "ThisIsAVeryLong&SecurePasswordWithMoreThan8Characters!"

foreach ($user in $users) {
    $params = @{
        Department        = $user.Department
        GivenName         = $user.GivenName
        Surname           = $user.Surname
        DisplayName       = $user.DisplayName
        State             = $user.State
        City              = $user.city
        CompanyName       = $user.CompanyName
        JobTitle          = $user.JobTitle
        UserPrincipalName = $user.UserPrincipalName
        MailNickName      = $user.MailNickName
    }

    try {
        $userobject = Get-AzureADUser -SearchString $user.UserPrincipalName
        
        if (-not ($userobject)) {
            New-AzureADUser  -AccountEnabled $false -PasswordProfile $PasswordProfile @params
        }
    }
    catch {
        Write-Output "User object already exists"

    }

}