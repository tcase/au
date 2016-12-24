class AUPackage {
    [string]   $Path
    [string]   $Name
    [bool]     $Updated
    [bool]     $Pushed
    [bool]     $Forced
    [string]   $RemoteVersion
    [string]   $NuspecVersion
    [string[]] $Result
    [string]   $Error
    [string]   $NuspecPath
    [xml]      $NuspecXml

    AUPackage([string] $Path ){
        if ([String]::IsNullOrWhiteSpace( $Path )) { throw 'Package path can not be empty' }

        $this.Path = $Path
        $this.Name = Split-Path -Leaf $Path

        $this.NuspecPath = '{0}\{1}.nuspec' -f $this.Path, $this.Name
        if (!(gi $this.NuspecPath -ea ignore)) { throw 'No nuspec file found in the package directory' }

        $this.NuspecXml     = $this.LoadNuspecFile()
        $this.NuspecVersion = $this.NuspecXml.package.metadata.version
    }

    static [bool] IsVersion( [string] $Version ) {
        $re = '^(\d{1,16})\.(\d{1,16})\.*(\d{1,16})*\.*(\d{1,16})*(-[^.-]+)*$'
        if ($Version -notmatch $re) { return $false }

        $v = $Version -replace '-.+'
        return [version]::TryParse($v, [ref]($_))
    }

    SaveNuspecFile(){
        $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($False)
        [System.IO.File]::WriteAllText($this.NuspecPath, $this.NuspecXml.InnerXml, $Utf8NoBomEncoding)
    }

    [bool] UpdateAvailable() {
        if ($this.Forced) { return $true }

        $remote_l = $this.RemoteVersion -replace '-.+'
        $nuspec_l = $this.NuspecVersion -replace '-.+'
        $remote_r = $this.RemoteVersion.Replace($remote_l,'')
        $nuspec_r = $this.NuspecVersion.Replace($nuspec_l,'')

        if ([version]$remote_l -eq [version] $nuspec_l) {
            if (!$remote_r -and $nuspec_r) { return $true }
            if ($remote_r -and !$nuspec_r) { return $false }
            return ($remote_r -gt $nuspec_r)
        }
        return ([version]$remote_l -gt [version] $nuspec_l)
    }

    SetForced() {
        if ($this.UpdateAvailable()) {
            Write-Host 'Ignoring force as new remote version is available'
            return
        }

        $this.Forced = $true

        $date_format = 'yyyyMMdd'
        $d = (get-date).ToString($date_format)
        $v = [version]($this.NuspecVersion -replace '-.+')
        $rev = $v.Revision.ToString()

        $revdate = $null
        try { $revdate = [DateTime]::ParseExact($rev, $date_format, [CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None) } catch {}
        if (($rev -ne -1) -and !$revdate) { return }

        $build = if ($v.Build -eq -1) {0} else {$v.Build}
        $this.RemoteVersion = '{0}.{1}.{2}.{3}' -f $v.Major, $v.Minor, $build, $d
    }

    GetLatest() {
        $global:Latest = @{PackageName = $this.Name; NuspecVersion = $this.NuspecVersion }

        if (![AUPackage]::IsVersion( $this.NuspecVersion )) {
            Write-Warning "Invalid nuspec file Version '$($this.NuspecVersion)' - using 0.0"
            $global:Latest.NuspecVersion = $this.NuspecVersion = '0.0'
        }

        try {
            $res = au_GetLatest | select -Last 1
            if ($res -eq $null) { throw 'au_GetLatest returned nothing' }

            $res_type = $res.GetType()
            if ($res_type -ne [HashTable]) { throw "au_GetLatest doesn't return a HashTable result but $res_type" }

            $res.Keys | % { $global:Latest.Remove($_) }
            $global:Latest += $res
        } catch {
            throw "au_GetLatest failed`n$_"
        }

        if (![AUPackage]::IsVersion($global:Latest.Version)) { throw "Invalid version: $($global:Latest.Version)" }
        $this.RemoteVersion = $global:Latest.Version
        $this.Name          = $global:Latest.PackageName
    }

    [bool]ExistsInGallery( [string] $Version ) {
        $gallery_url = "https://chocolatey.org/packages/{0}/{1}" -f $this.Name, $Version
        try {
            request $gallery_url | out-null
            return $true
        } catch {}

        return $false
    }

    Update() {
        $this.SetLatestFileType()
        $this.ShowLatestData()

        Write-Host 'Updating files'
        if (Test-Path Function:\au_BeforeUpdate) { Write-Host 'Running au_BeforeUpdate'; au_BeforeUpdate }
        $this.UpdateFiles( $true )
        if (Test-Path Function:\au_AfterUpdate)  { Write-Host 'Running au_AfterUpdate';  au_AfterUpdate  }

        $this.Updated = $true
    }


    # ======================================  HIDDEN  =========================================

    hidden UpdateFiles([bool]$DoMandatoryUpdates) {
        function update_mandatory() {
            if (!$DoMandatoryUpdates) { return }

            Write-Host "  $(Split-Path $this.NuspecPath -Leaf)"

            Write-Host "    setting id:  $($this.PackageName)"
            $this.NuspecXml.package.metadata.id = $this.Name

            $msg ="updating version: {0} -> {1}" -f $this.NuspecVersion, $this.RemoteVersion
            if ($this.Forced) {
                if ($this.RemoteVersion -eq $this.NuspecVersion) {
                    $msg = "    version not changed as it already uses 'revision': {0}" -f $this.NuspecVersion
                } else {
                    $msg = "    using Chocolatey fix notation: {0} -> {1}" -f $this.NuspecVersion, $this.RemoteVersion
                }
            }
            Write-Host $msg

            $this.NuspecXml.package.metadata.version = $this.RemoteVersion
            $this.SaveNuspecFile()
        }

        function update_files() {
            $sr = au_SearchReplace
            $sr.Keys | % {
                $fileName = $_
                Write-Host "  $fileName"

                $fileContent = gc $fileName
                $sr[ $fileName ].GetEnumerator() | % {
                    '    {0} = {1} ' -f $_.name, $_.value
                    if (!($fileContent -match $_.name)) { throw "Search pattern not found: '$($_.name)'" }
                    $fileContent = $fileContent -replace $_.name, $_.value
                }

                $fileContent | Out-File -Encoding UTF8 $fileName
            }
        }

        update_mandatory
        update_files
    }

    hidden ShowLatestData() {
        Write-Host '  $Latest data:'
        $global:Latest.keys | sort | % {
           $line = "    {0,-15} ({1})    {2}" -f $_, $global:Latest[$_].GetType().Name, $global:Latest[$_]
           Write-Host $line
        }
    }

    hidden SetLatestFileType() {
        $match_url = ($global:Latest.Keys | ? { $_ -match '^URL*' } | select -First 1 | % { $global:Latest[$_] } | split-Path -Leaf) -match '(?<=\.)[^.]+$'
        if ($match_url -and !$global:Latest.FileType) { $global:Latest.FileType = $Matches[0] }
    }

    hidden [xml] LoadNuspecFile() {
        $nu = New-Object xml
        $nu.PSBase.PreserveWhitespace = $true
        $nu.Load($this.NuspecPath)
        return $nu
    }

    hidden CheckLatestUrls() {
        Write-Host "URL check"
        $global:Latest.Keys | ? {$_ -like 'url*' } | % {
            $url = $global:Latest[ $_ ]
            if ($res = check_url $url) { throw "${res}:$url" } else { Write-Host "  $url" }
        }
    }

}
