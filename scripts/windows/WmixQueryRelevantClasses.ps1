param (
    [Parameter(Mandatory = $true)]
    [string] $OutDir
)

$classes = @(
    'Win32_InstalledWin32Program',
    'Win32_InstalledStoreProgram',
    'Win32_InstalledProgramFramework',
    'Win32_Bios',
    'Win32_OperatingSystem',
    'Win32_ComputerSystem',
    'Win32_Processor',
    'Win32_LogicalDisk',
    'Win32_NetworkAdapterConfiguration',
    'Win32_NetworkAdapter',
    'Win32_NetworkLoginProfile',
    'Win32_NetworkProtocol',
    'Win32_Service',
    'Win32_Product',
    'Win32_SoftwareFeature',
    'Win32_SoftwareElement',
    'Win32_SoftwareElementCondition',
    'Win32_SoftwareFeatureCheck',
    'Win32_SoftwareFeatureParent',
    'Win32_SoftwareFeatureSoftwareElements',
    'Win32_ComputerSystemProduct',
    'Win32_BaseBoard',
    'Win32_PhysicalMemory',
    'Win32_DiskDrive',
    'Win32_DiskPartition',
    'Win32_CDROMDrive',
    'Win32_USBController',
    'Win32_VideoController',
    'Win32_SoundDevice',
    'Win32_PrinterDriver',
    'Win32_Printer',
    'Win32_SystemDriver',
    'Win32_OptionalFeature',
    'Win32_DisplayConfiguration',
    'Win32_PnPEntity',
    'Win32_PnpSignedDriver',
    'Win32_MotherboardDevice',
    'CIM_SoftwareElement',
    'CIM_SoftwareFeature',
    'CIM_SoftwareFeatureSoftwareElements'
)

if (!(Test-Path $OutDir)) {
    New-Item -ItemType directory -Path $OutDir | Out-Null
}

$totalClasses = $classes.Length
$counter = 0

Write-Host "Querying $totalClasses WMI classes"

ForEach ($class in $classes) {
    $counter++

    $percentComplete = ($counter / $totalClasses) * 100
    Write-Progress -PercentComplete $percentComplete -Status "In Progress" -CurrentOperation $class -Activity "Querying WMI Classes"

    try {
        powershell -ExecutionPolicy Bypass -File .\WmixQuerySingleClass.ps1 -QueryClass $class -OutFile "$OutDir\$class.json"
    } catch {
        Write-Host "There was a problem querying the $class class: $_"
    }
}

Write-Progress -Completed -Status "Completed" -Activity "Querying WMI Classes"
Write-Host "Done querying WMI classes"
