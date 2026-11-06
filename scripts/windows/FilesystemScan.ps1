param (
    [Parameter(Mandatory = $true)]
    [string] $BaseDir,
    [Parameter(Mandatory = $true)]
    [string] $OutFileFiles,
    [Parameter(Mandatory = $true)]
    [string] $OutFileDirs,
    [Parameter(Mandatory = $true)]
    [string] $OutFileSymlinks,
    [string] $ExcludeDirs
)

function ensureParentDirectoryExists([string]$filePath) {
    $parentDir = [System.IO.Path]::GetDirectoryName($filePath)
    if (-Not(Test-Path $parentDir)) {
        New-Item -Path $parentDir -Type Directory -Force
    }
}

ensureParentDirectoryExists $OutFileFiles
ensureParentDirectoryExists $OutFileDirs
ensureParentDirectoryExists $OutFileSymlinks

$ExcludeDirsSplit = @()
if ($ExcludeDirs -is [string] -and $ExcludeDirs -ne '') {
    $ExcludeDirsSplit = $ExcludeDirs -split ';;;'
}

Write-Host "BaseDir: $BaseDir"
Write-Host "ExcludeDirs: $ExcludeDirsSplit"

$allFiles = New-Object 'System.Collections.ArrayList'
$allDirs = New-Object 'System.Collections.ArrayList'
$allSymlinks = New-Object 'System.Collections.ArrayList'

$stack = New-Object 'System.Collections.Stack'
$stack.Push($BaseDir)

$counter = 0
$startTime = Get-Date

while ($stack.Count -gt 0) {
    $currentDir = $stack.Pop()

    if ($ExcludeDirsSplit -contains $currentDir) {
        continue
    }

    $counter++
    if ($counter % 500 -eq 0) {
        Write-Progress -PercentComplete (($counter / ($stack.Count + $counter)) * 100) -Status "Processing" -CurrentOperation $currentDir -Activity "Processing filesystem"
    }

    $items = Get-ChildItem -Path $currentDir -Force -ErrorAction SilentlyContinue

    foreach ($item in $items) {
        if ($item.PSIsContainer) {
            if ($item.Attributes -match "ReparsePoint") {
                $null = $allSymlinks.Add($item.FullName)
            } else {
                $null = $allDirs.Add($item.FullName)
            }
            $stack.Push($item.FullName)
        } else {
            if ($item.Attributes -match "ReparsePoint") {
                $null = $allSymlinks.Add($item.FullName)
            } else {
                $null = $allFiles.Add($item.FullName)
            }
        }
    }
}

Write-Progress -Completed -Status "Done" -Activity "Processing filesystem"

$endTime = Get-Date
$diff = New-TimeSpan -Start $startTime -End $endTime

# output statistics
Write-Host "Finished processing filesystem. Results:"
Write-Host "      files: $( $allFiles.Count )"
Write-Host "   symlinks: $( $allSymlinks.Count )"
Write-Host "directories: $( $allDirs.Count )"
Write-Host "      total: $( ($allFiles.Count + $allSymlinks.Count + $allDirs.Count) )"
Write-Host " total time: $( $diff.TotalSeconds ) seconds"
Write-Host ""
Write-Host "Writing results to files:"

# output to files
Write-Host "  - $OutFileFiles"
$allFiles -join "`r`n" | Out-File $OutFileFiles
Write-Host "  - $OutFileDirs"
$allDirs -join "`r`n" | Out-File $OutFileDirs
Write-Host "  - $OutFileSymlinks"
$allSymlinks -join "`r`n" | Out-File $OutFileSymlinks
Write-Host "Done"
