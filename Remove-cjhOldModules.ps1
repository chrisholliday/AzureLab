foreach ($module in $installedModules) {
    $latestVersion = $module.Version
    Write-Output "Module: $($module.Name) - Version: $($module.Version)"

    # Get all versions of the current module
    $allVersions = Get-InstalledModule $module.Name -AllVersions

    foreach ($version in $allVersions) {
        if ($version.Version -ne $latestVersion) {
        Write-Output "- Uninstalling version $($version.Version)..." -
        $version | Uninstall-Module -Force
        #Write-Output "done"
        }
    }
}