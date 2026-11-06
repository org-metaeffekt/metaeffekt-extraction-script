param (
    [Parameter(Mandatory = $true)]
    [string]$RegistryPath,

    [Parameter(Mandatory = $true)]
    [string]$OutFile
)

function ensureParentDirectoryExists([string]$filePath) {
    $parentDir = [System.IO.Path]::GetDirectoryName($filePath)

    if (-Not(Test-Path $parentDir)) {
        New-Item -Path $parentDir -Type Directory -Force
    }
}

ensureParentDirectoryExists $OutFile

Write-Host "Exporting subtree from registry path: $RegistryPath"
Write-Progress -Status "Initializing" -PercentComplete 0 -Activity "Processing key"

# recursively get all child items (keys and values) under the registry path
$items = Get-ChildItem -Path $RegistryPath -Recurse
$totalItems = $items.Count
$currentItem = 0

$registryData = @()

foreach ($item in $items) {
    $currentItem++
    $percentComplete = ($currentItem / $totalItems) * 100

    Write-Progress -Status $item.PSPath -PercentComplete $percentComplete -Activity "Processing key"

    $temp = [pscustomobject]@{
        'Key' = $item.PSPath
        'Properties' = @{ }
    }

    # Get all the property values under this key
    $properties = Get-ItemProperty -Path $item.PSPath

    foreach ($propertyName in $properties.PSObject.Properties.Name) {
        $temp.Properties[$propertyName] = $properties.$propertyName
    }

    $registryData += $temp
}

$registryData | ConvertTo-Json | Out-File $OutFile -Encoding utf8

Write-Progress -Completed -Status "Completed" -Activity "Processing key"
