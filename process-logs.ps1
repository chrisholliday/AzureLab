$ErrorActionPreference = 'Stop'

# ---------------- CONFIG ----------------

$InputDir = 'input'
$ReadyDir = 'ready'
$BadDir = 'incomplete'
$StateFile = 'file_state.json'
$Extensions = @('*.log', '*.json', '*.jsonl')
$StabilityRuns = 1   # increase to 2 for extra safety

# ----------------------------------------

New-Item -ItemType Directory -Force -Path $ReadyDir, $BadDir | Out-Null

# Load previous state
$state = @{}
if (Test-Path $StateFile) {
    $state = Get-Content $StateFile | ConvertFrom-Json
}

function Get-LastNonEmptyLine {
    param ($Path)
    Get-Content $Path -Tail 50 |
        Where-Object { $_.Trim().Length -gt 0 } |
        Select-Object -Last 1
}

function Test-JsonLine {
    param ($Line)
    try {
        $null = $Line | ConvertFrom-Json -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

foreach ($pattern in $Extensions) {
    foreach ($file in Get-ChildItem -Path $InputDir -Filter $pattern -File) {

        $key = $file.FullName
        $now = @{
            Size        = $file.Length
            Write       = $file.LastWriteTimeUtc
            StableCount = 0
        }

        if ($state.ContainsKey($key)) {
            $prev = $state[$key]

            if ($prev.Size -eq $now.Size -and $prev.Write -eq $now.Write) {
                $now.StableCount = ($prev.StableCount + 1)
            }
        }

        # Update state early
        $state[$key] = $now

        if ($now.StableCount -lt $StabilityRuns) {
            Write-Host "STREAMING: $($file.Name)"
            continue
        }

        $lastLine = Get-LastNonEmptyLine $file.FullName
        if (-not $lastLine) {
            Write-Host "EMPTY OR INVALID: $($file.Name)"
            Move-Item $file.FullName $BadDir -Force
            $state.Remove($key)
            continue
        }

        if (Test-JsonLine $lastLine) {
            Write-Host "READY: $($file.Name)"
            Copy-Item $file.FullName $ReadyDir -Force
            $state.Remove($key)
        }
        else {
            Write-Host "INCOMPLETE: $($file.Name)"
            Move-Item $file.FullName $BadDir -Force
            $state.Remove($key)
        }
    }
}

# Persist state
$state | ConvertTo-Json -Depth 3 | Set-Content $StateFile

<#

How Azure Batch will behave
First run
Files are seen for the first time
Marked as STREAMING
State recorded
Subsequent runs
If file still growing → STREAMING
If stable + valid → READY → copied
If stable + invalid → INCOMPLETE → moved aside
If a node restarts
State file persists in task working directory
Logic resumes safely
#>