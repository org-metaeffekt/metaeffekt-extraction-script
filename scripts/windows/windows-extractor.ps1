param (
    [Parameter(Mandatory = $true)]
    [string]
    $OutDir,

    [Parameter(Mandatory = $false)]
    [string]
    $FsScanBaseDir,

    [Parameter(Mandatory = $false)]
    [string]
    $FsScanExcludeDirs
)

function getDefaultFsScanBaseDir() {
    if ((Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue).SystemDrive) {
        return (Get-WmiObject Win32_OperatingSystem).SystemDrive
    }
    else {
        return "C:\"
    }
}

if (-Not$FsScanBaseDir) {
    $FsScanBaseDir = getDefaultFsScanBaseDir
}

if (-Not$FsScanExcludeDirs) {
    $FsScanExcludeDirs = ""
}

function Write-PaddedMessage([string] $message) {
    # may be adjusted for target length
    $totalLength = 64
    $messageLength = $message.Length

    $numDashesEachSide = ($totalLength - $messageLength - 2) / 2

    $dashString = '-' * [Math]::Floor($numDashesEachSide)

    Write-Host ""
    Write-Host "$dashString $message $dashString"
    Write-Host ""
}

function Create-OutFile([string] $fileName) {
    return ".\$OutDir\$fileName"
}


# ensure output directory exists
if (-Not(Test-Path $OutDir)) {
    New-Item -Path $OutDir -Type Directory -Force
}


$tasks = @(
    {
        # add -ExcludeDirs "dir1;;;dir2;;;dir3" to exclude directories from scan
        Write-PaddedMessage "Collecting files in file system"
        .\FilesystemScan.ps1 -BaseDir $FsScanBaseDir -OutFileFiles (Create-OutFile "FileSystemFilesList.txt") -OutFileDirs (Create-OutFile "FileSystemDirsList.txt") -OutFileSymlinks (Create-OutFile "FileSystemSymlinksList.txt") -ExcludeDirs $FsScanExcludeDirs
    },
    {
        Write-PaddedMessage "Querying WMI classes"
        .\WmixQueryRelevantClasses.ps1 -OutDir $OutDir
    },
    {
        Write-PaddedMessage "Exporting registry subtrees"
        .\ExportRegistrySubtree.ps1 -RegistryPath "Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall" -OutFile (Create-OutFile "RegistrySubtree-windows-uninstall.json")
    },
    {
        Write-PaddedMessage "Getting Windows version"
        Write-Host "[System.Environment]::OSVersion.Version"
        [System.Environment]::OSVersion.Version | Out-File (Create-OutFile "OSVersion.Version.txt")
    },
    {
        Write-PaddedMessage "Getting system information"
        Write-Host "systeminfo /fo csv"
        systeminfo /fo csv | ConvertFrom-Csv | ConvertTo-Json | Out-File (Create-OutFile "systeminfo.json")
        Write-Host "Get-ComputerInfo"
        Get-ComputerInfo | ConvertTo-Json | Out-File (Create-OutFile "Get-ComputerInfo.json")
    },
    {
        Write-PaddedMessage "Getting PnP devices information"
        Write-Host "Get-PnpDevice"
        Get-PnpDevice | ConvertTo-Json | Out-File (Create-OutFile "Get-PnpDevice.json")
    }
)


$taskFailed = $false
$startTime = Get-Date

foreach ($task in $tasks) {
    try {
        $task.Invoke()
    } catch {
        Write-Host "Error: $_"
        Write-PaddedMessage "Previous task failed"
        $script:taskFailed = $true
    }
}

$endTime = Get-Date
$diff = New-TimeSpan -Start $startTime -End $endTime


# check if any task failed and exit with non-zero code if so
if ($taskFailed) {
    Write-Host "At least one task failed. Total time: $( $diff.TotalSeconds ) seconds"
    exit 1
} else {
    Write-PaddedMessage "Successfully terminated running all tasks"
    Write-Host "Finished running all tasks. Total time: $( $diff.TotalSeconds ) seconds"
}

