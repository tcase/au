# Author: Miodrag Milic <miodrag.milic@gmail.com>
# Last Change: 22-Dec-2016.

<#
.SYNOPSIS
    Update automatic package

.DESCRIPTION
    This function is used to perform necessary updates to the specified files in the package.
    It shouldn't be used on its own but must be part of the script which defines two functions:

    - au_SearchReplace
      The function should return HashTable where keys are file paths and value is another HashTable
      where keys and values are standard search and replace strings
    - au_GetLatest
      Returns the HashTable where the script specifies information about new Version, new URLs and
      any other data. You can refer to this variable as the $Latest in the script.
      While Version is used to determine if updates to the package are needed, other arguments can
      be used in search and replace patterns or for whatever purpose.

    With those 2 functions defined, calling Update-Package will:

    - Call your au_GetLatest function to get the remote version and other information.
    - If remote version is higher then the nuspec version, function will:
        - Check the returned URLs, Versions and Checksums (if defined) for validity (unless NoCheckXXX variables are specified)
        - Download files and calculate checksum(s), (unless already defined or ChecksumFor is set to 'none')
        - Update the nuspec with the latest version
        - Do the necessary file replacements
        - Pack the files into the nuget package

    You can also define au_BeforeUpdate and au_AfterUpdate functions to integrate your code into the update pipeline.
.EXAMPLE
    PS> notepad update.ps1
    # The following script is used to update the package from the github releases page.
    # After it defines the 2 functions, it calls the Update-Package.
    # Checksums are automatically calculated for 32 bit version (the only one in this case)
    import-module au

    function global:au_SearchReplace {
        ".\tools\chocolateyInstall.ps1" = @{
            "(^[$]url32\s*=\s*)('.*')"          = "`$1'$($Latest.URL32)'"
            "(^[$]checksum32\s*=\s*)('.*')"     = "`$1'$($Latest.Checksum32)'"
            "(^[$]checksumType32\s*=\s*)('.*')" = "`$1'$($Latest.ChecksumType32)'"
        }
    }

    function global:au_GetLatest {
        $download_page = Invoke-WebRequest -Uri https://github.com/hluk/CopyQ/releases

        $re  = "copyq-.*-setup.exe"
        $url = $download_page.links | ? href -match $re | select -First 1 -expand href
        $version = $url -split '-|.exe' | select -Last 1 -Skip 2

        return @{ URL32 = $url; Version = $version }
    }

    Update-Package -ChecksumFor 32

.NOTES
    All function parameters accept defaults via global variables with prefix `au_` (example: $global:au_Force = $true).

.OUTPUTS
    PSCustomObject with type AUPackage.

.LINK
    Update-AUPackages
#>
function Update-Package {
    [CmdletBinding()]
    param(
        #Do not check URL and version for validity.
        [switch] $NoCheckUrl,

        #Do not check if latest returned version already exists in the Chocolatey community feed.
        #Ignored when Force is specified.
        [switch] $NoCheckChocoVersion,

        #Specify for which architectures to calculate checksum - all, 32 bit, 64 bit or none.
        [ValidateSet('all', '32', '64', 'none')]
        [string] $ChecksumFor='all',

        #Timeout for all web operations, by default 100 seconds.
        [int]    $Timeout,

        #Force package update even if no new version is found.
        [switch] $Force,

        #Do not show any Write-Host output.
        [switch] $NoHostOutput,

        #Array, of options:
        # - First element is path to the package which provides metadata that can end with !
        # - All other fields represent metadata to include (no !) or exclude (with !).
        [string[]] $UseMetadataFrom,

        #Output variable.
        [string] $Result
    )

    function result() {
        $input | % {
            $package.Result += $_
            if (!$NoHostOutput) { Write-Host $_ }
        }
    }

    [System.Net.ServicePointManager]::SecurityProtocol = 'Ssl3,Tls,Tls11,Tls12' #https://github.com/chocolatey/chocolatey-coreteampackages/issues/366
    $module = $MyInvocation.MyCommand.ScriptBlock.Module

    if ($PSCmdlet.MyInvocation.ScriptName -eq '') {
        Write-Verbose 'Running outside of the script'
        if (!(Test-Path update.ps1)) { return "Current directory doesn't contain ./update.ps1 script" } else { return ./update.ps1 }
    } else { Write-Verbose 'Running inside the script' }

    # Assign parameters from global variables with the prefix `au_` if they are bound
    (gcm $PSCmdlet.MyInvocation.InvocationName).Parameters.Keys | % {
        if ($PSBoundParameters.Keys -contains $_) { return }
        $value = gv "au_$_" -Scope Global -ea Ignore | % Value
        if ($value -ne $null) {
            sv $_ $value
            Write-Verbose "Parameter $_ set from global variable au_${_}: $value"
        }
    }

    $package = New-AuPackage
    "{0} - checking updates using {1} version {2}" -f $package.Name, $module.Name, $module.Version | result

    if ($Result) { sv -Scope Global -Name $Result -Value $package }

    $package.GetLatest()
    if ($global:au_Force) { $Force = $true }  #au_GetLatest can also force update

    if (!$NoCheckUrl) { $package.CheckLatestUrls() }

    "nuspec version: " + $package.NuspecVersion | result
    "remote version: " + $package.RemoteVersion | result
    if ($Force) { $package.SetForced() | result }

    if (!$package.UpdateAvailable()) {
        'No new version found' | result
        return $package
    }

    if (!$NoCheckChocoVersion -and $package.ExistsInGallery( $global:Latest.Version )) {
        "New version is available but it already exists in the Chocolatey community feed (disable using `$NoCheckChocoVersion`)" | result
        return $package
    }

    # Update happens from this point
    if ($package.Forced)  {
        'No new version found, but update is forced' | result
        if ($global:au_Version) {
            "Overriding version to: $global:au_Version" | result
            $global:Latest.Version = $package.RemoteVersion = $global:au_Version
            if (![AUPackage]::IsVersion($Latest.Version)) { throw "Invalid version: $($Latest.Version)" }
            $global:au_Version = $null
        }
    }

    . {
        'New version is available'
        automatic_checksum $package $ChecksumFor
        $package.Update()
        choco pack --limit-output
        if ($LastExitCode -ne 0) { throw "Choco pack failed with exit code $LastExitCode" }
        'Package updated'
      } | result

    $package
}

Set-Alias update Update-Package
