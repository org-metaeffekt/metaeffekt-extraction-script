#Requires -Version 4
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    A versatile WMI Script for querying installed programs.

    WHAT IT DOES: This script can be run against the local machine, or a single or list of remote machines.
    It queries instances of installed Win32 programs or installed Store programs and optionally
    converts property names and values to more human-friendly formats.

.EXAMPLE
	PS> .\WmixQuerySingleClass.ps1 -QueryClass 'Win32_InstalledWin32Program'
		Run this script on the local machine to query installed Win32 programs.
		Output property names and values are converted to friendly values.

.EXAMPLE
	PS> .\WmixQuerySingleClass.ps1 -QueryClass 'Win32_InstalledWin32Program' -ComputerName 'computer1'
		Run this script on computer1 to query installed Win32 programs.
		Output property names and values are converted to friendly values.

.EXAMPLE
	PS> .\WmixQuerySingleClass.ps1 -QueryClass 'Win32_InstalledStoreProgram' -ComputerName 'computer1','computer2'
		Run this script on computer1 and computer2 to query installed Store programs.
		Output property names and values are converted to friendly values.

.EXAMPLE
	PS> $MyCredentials = Get-Credential
	PS> .\WmixQuerySingleClass.ps1 -QueryClass 'Win32_InstalledWin32Program' -ComputerName 'computer1' -Credential $MyCredentials
		Run this script on computer1 using the specified credentials to query installed Win32 programs.

.EXAMPLE
	PS> .\WmixQuerySingleClass.ps1 -QueryClass 'Win32_InstalledWin32Program' -ComputerName 'computer1' -NoFriendlyNames
		Run this script on computer1 to query installed Win32 programs.
		Output property names and values are NOT converted to friendly values.

.PARAMETER ComputerName
	The name of the computer you'd like to run this function against. This defaults to 'localhost'.  You can also
	specify either a single or multiple comma-separated remote hosts as well.

.PARAMETER Credential
	The credentials to use to execute the WMI calls. This defaults to the local user's credentials.

.PARAMETER NoFriendlyNames
	WMI can return some obsure property names and values. This script automatically converts property names and values to
	human friendly values. Use this switch parameter to turn of this option.

.PARAMETER Impersonation
	Specifies the impersonation level to use. Valid values are:
		0: Default. Reads the local registry for the default impersonation level , which is usually set to '3: Impersonate'
		1: Anonymous. Hides the credentials of the caller.
		2: Identify. Allows objects to query the credentials of the caller.
		3: Impersonate. Allows objects to use the credentials of the caller.
		4: Delegate. Allows objects to permit other objects to use the credentials of the caller.

.PARAMETER Authentication
	Specifies the authentication level to be used with the WMI connection. Valid values are:
		-1: Unchanged
		0: Default
		1: None (No authentication in performed.)
		2: Connect (Authentication is performed only when the client establishes a relationship with the application.)
		3: Call (Authentication is performed only at the beginning of each call when the application receives the request.)
		4: Packet (Authentication is performed on all the data that is received from the client.)
		5: PacketIntegrity (All the data that is transferred between the client and the application is authenticated and verified.)
		6: PacketPrivacy (The properties of the other authentication levels are used, and all the data is encrypted.)

.PARAMETER QueryClass
  Mandatory parameter that specifies the WMI class to query. Valid classes are 'Win32_InstalledWin32Program' and 'Win32_InstalledStoreProgram'

.INPUTS
	None. You cannot pipe objects to wmix_QueryInstances_InstalledWin32Program.ps1.

.OUTPUTS
	Selected.System.Management.ManagementObject,System.Management.Automation.PSCustomObject.
#>

    [CmdletBinding()]
    [OutputType()]
param
(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $ComputerName = $env:COMPUTERNAME,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [pscredential]
    $Credential,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [switch]
    $NoFriendlyNames = $False,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ValidateRange(0, 4)]
    [int]
    $Impersonation,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ValidateRange(0, 6)]
    [int]
    $Authentication,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $QueryClass,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]
    $OutFile
)



process {
    try {
        Write-Verbose -Message "WMIX (R) Scriptor v3 - wmix.goverlan.com"
        Write-Verbose -Message " starting execution..."

        foreach ($computer in $ComputerName) {
            try {
                if (-not(Test-Connection -ComputerName $computer -Quiet -Count 1)) {
                    Write-Warning "[$computer] is offline and will not be processed"
                }
                else {
                    Write-Verbose -Message "The computer [$( $computer )] is online. Proceeding..."

                    # find friendly property names from the QueryClass
                    $friendly_PropName
                    switch ($QueryClass) {
                        'Win32_InstalledWin32Program' {
                            $friendly_PropName = $friendly_InstalledWin32Program_PropName
                        }
                        'Win32_InstalledStoreProgram' {
                            $friendly_PropName = $friendly_InstalledStoreProgram_PropName
                        }
                        'Win32_InstalledProgramFramework' {
                            $friendly_PropName = $friendly_InstalledProgramFramework_PropName
                        }
                        default {
                            $friendly_PropName = @{ }
                        }
                    }

                    # >>>>>>>>>>>>>>>>>>
                    $result = (queryInstalledWin32ProgramInstances $computer $QueryClass $friendly_PropName) | ConvertTo-Json -Depth 4
                    if ($OutFile) {
                        ensureParentDirectoryExists $OutFile
                        $result | Out-File -FilePath $OutFile -Encoding utf8
                    }
                    else {
                        $result
                    }
                    # <<<<<<<<<<<<<<<<<<
                }
            } catch {
                Write-Error "Unable to perform WMI action on [$computer] - $( $_.Exception.Message )"
            }
        }
    } catch {
        Write-Error $_.Exception.Message
    } finally {
        Write-Verbose -Message 'WMIX script by GoverLAN complete'
    }
}


begin
{
    function ensureParentDirectoryExists([string]$filePath) {
        $parentDir = [System.IO.Path]::GetDirectoryName($filePath)

        if (-Not(Test-Path $parentDir)) {
            New-Item -Path $parentDir -Type Directory -Force
        }
    }

    Function queryInstalledWin32ProgramInstances([string]$computer, [string]$queryClass, [hashtable]$friendly_PropName) {
        $wmiParams = @{
            'ComputerName' = $computer
            'Namespace' = 'ROOT\CIMV2'
            'Class' = $queryClass
            'Filter' = ''
            'Property' = '*'
        }

        if ( $script:PSBoundParameters.ContainsKey('Credential')) {
            $wmiParams.Credential = $Credential
            Write-Verbose -Message "Using specified credentials."
        }

        if ( $script:PSBoundParameters.ContainsKey('Authentication')) {
            $wmiParams.Authentication = $Authentication
        }

        if ( $script:PSBoundParameters.ContainsKey('Impersonation')) {
            $wmiParams.Impersonation = $Impersonation
        }

        Write-Verbose -Message "Querying [$( $queryClass )] Instances on computer [$( $computer )]..."

        $instanceSet = (Get-WmiObject @wmiParams)
        $output = @()
        foreach ($instance in $instanceSet) {
            $temp = [pscustomobject]@{
                'Computer' = $computer
            }
            $instance.psbase.psobject.baseobject.properties | foreach {
                $temp | Add-Member -NotePropertyName (convertVal $_.Name $null $friendly_PropName) -NotePropertyValue $_.Value
            }
            $output += $temp
        }
        return $output
    }

    ###############################################################

    # decodeVal converts a WMI raw value to a friendly format based on the optional specified array and optional unit (unless NoFriendlyValue is turned ON)
    function convertVal([array]$unfriendlyValue, [string]$valueUnit, [hashtable]$hashValues = $null) {
        # check for empty array (no value) or if NoFriendlyNames is enabled
        if ($unfriendlyValue.Count -eq 0 -or $NoFriendlyNames -eq $True) {
            return $unfriendlyValue
        }

        # either a single value or an array of values
        if ($unfriendlyValue.Count -eq 1) {
            $friendlyValue = $unfriendlyValue[0] -as [string]

            if ($hashValues -ne $null -and $hashValues.Contains($friendlyValue)) {
                # check if a friendly version exists in the provided hashtable
                $friendlyValue = $hashValues[$friendlyValue]
            }

            if ($valueUnit) {
                # append any unit that may exist (like 'bytes' or 'GHz') to the value
                $friendlyValue += " " + $valueUnit
            }

            return $friendlyValue
        }
        else {
            $friendlyValue = "{"

            foreach ($arrayVal in $unfriendlyValue) {
                # recursive call to handle each of the array's values individually
                $friendlyValue += (convertVal $arrayVal $valueUnit) + ", "
            }

            # trim any trailing commas/spaces and close the braces
            $friendlyValue = $friendlyValue.Trim().TrimEnd(",") + "}"

            return $friendlyValue;
        }
    }

    ###############################################################

    # Array of friendly values for the property names of the Installed Win32 Program WMI Class
    $friendly_InstalledWin32Program_PropName = @{
        'MsiPackageCode' = 'Msi Package Code'
        'MsiProductCode' = 'Msi Product Code'
        'ProgramId' = 'Program Id'
    }

    # Array of friendly values for the property names of the Installed Store Program WMI Class
    $friendly_InstalledStoreProgram_PropName = @{
        'ProgramId' = 'Program Id'
    }

    # Array of friendly values for the property names of the Installed Program Framework WMI Class
    $friendly_InstalledProgramFramework_PropName = @{
        'FrameworkName' = 'Framework Name'
        'FrameworkPublisher' = 'Framework Publisher'
        'FrameworkVersion' = 'Framework Version'
        'FrameworkVersionActual' = 'Framework Version Actual'
        'IsPrivate' = 'Is Private'
        'ProgramId' = 'Program Id'
    }
}
