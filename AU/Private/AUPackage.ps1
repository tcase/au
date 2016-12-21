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

        $this.NuspecXml     = [AUPackage]::LoadNuspecFile( $this.NuspecPath )
        $this.NuspecVersion = $this.NuspecXml.package.metadata.version
    }

    static [xml] LoadNuspecFile( $NuspecPath ) {
        $nu = New-Object xml
        $nu.PSBase.PreserveWhitespace = $true
        $nu.Load($NuspecPath)
        return $nu
    }

    static [bool] IsVersion( [string] $Version ) {
        $re = '^(\d{1,16})\.(\d{1,16})\.*(\d{1,16})*\.*(\d{1,16})*(-[^.-]+)*$'
        if ($Version -notmatch $re) { return $false }

        $v = $Version -replace '-.+'
        return [version]::TryParse($v, [ref]($_))
    }

    [bool] IsUpdated() {
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

    SaveNuspec(){
        $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($False)
        [System.IO.File]::WriteAllText($this.NuspecPath, $this.NuspecXml.InnerXml, $Utf8NoBomEncoding)
    }
}
