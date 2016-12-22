function automatic_checksum([AUPackage]$Package, [string]$ChecksumFor)
{
    function invoke_installer() {
        if (!(Test-Path tools\chocolateyInstall.ps1)) { "  aborted, chocolateyInstall not found for this package"; return }

        Import-Module "$choco_tmp_path\helpers\chocolateyInstaller.psm1" -Force -Scope Global

        if ($ChecksumFor -eq 'all') { $arch = '32','64' } else { $arch = $ChecksumFor }

        $pkg_path = [System.IO.Path]::GetFullPath("$Env:TEMP\chocolatey\$($Package.Name)\" + $package.RemoteVersion) #https://github.com/majkinetor/au/issues/32
        mkdir -Force $pkg_path | Out-Null

        $Env:ChocolateyPackageName         = "chocolatey\$($Package.Name)"
        $Env:ChocolateyPackageVersion      = $Package.RemoteVersion
        $Env:ChocolateyAllowEmptyChecksums = 'true'
        foreach ($a in $arch) {
            $Env:chocolateyForceX86 = if ($a -eq '32') { 'true' } else { '' }
            try {
                #rm -force -recurse -ea ignore $pkg_path
                .\tools\chocolateyInstall.ps1 | result
            } catch {
                if ( "$_" -notlike 'au_break: *') { throw $_ } else {
                    $filePath = "$_" -replace 'au_break: '
                    if (!(Test-Path $filePath)) { throw "Can't find file path to checksum" }

                    $item = gi $filePath
                    $type = if ($global:Latest.ContainsKey('ChecksumType' + $a)) { $global:Latest.Item('ChecksumType' + $a) } else { 'sha256' }
                    $hash = (Get-FileHash $item -Algorithm $type | % Hash).ToLowerInvariant()

                    if (!$global:Latest.ContainsKey('ChecksumType' + $a)) { $global:Latest.Add('ChecksumType' + $a, $type) }
                    if (!$global:Latest.ContainsKey('Checksum' + $a)) {
                        $global:Latest.Add('Checksum' + $a, $hash)
                        "Package downloaded and hash calculated for $a bit version"
                    } else {
                        $expected = $global:Latest.Item('Checksum' + $a)
                        if ($hash -ne $expected) { throw "Hash for $a bit version mismatch: actual = '$hash', expected = '$expected'" }
                        "Package downloaded and hash checked for $a bit version"
                    }
                }
            }
        }
    }

    function patch_choco_helpers
    {
        Sleep -Milliseconds (Get-Random 500) #reduce probability multiple updateall threads entering here at the same time (#29)

        # Copy choco modules once a day
        if (Test-Path $choco_tmp_path) {
            $ct = gi $choco_tmp_path | % creationtime
            if (((get-date) - $ct).Days -gt 1) { rm -recurse -force $choco_tmp_path } else { Write-Verbose 'Chocolatey copy is recent, aborting monkey patching'; return }
        }

        Write-Verbose "Monkey patching chocolatey in: '$choco_tmp_path'"
        cp -recurse -force $Env:ChocolateyInstall\helpers $choco_tmp_path\helpers
        if (Test-Path $Env:ChocolateyInstall\extensions) { cp -recurse -force $Env:ChocolateyInstall\extensions $choco_tmp_path\extensions }

        $fun_path = "$choco_tmp_path\helpers\functions\Get-ChocolateyWebFile.ps1"
        (gc $fun_path) -replace '^\s+return \$fileFullPath\s*$', '  throw "au_break: $fileFullPath"' | sc $fun_path -ea ignore
    }


    if ($ChecksumFor -eq 'none') { "Automatic checksum calculation is disabled"; return }
    "Automatic checksum started"

    # Copy choco powershell functions to TEMP dir and monkey patch the Get-ChocolateyWebFile function
    $choco_tmp_path = "$Env:TEMP\chocolatey\au\chocolatey"
    patch_choco_helpers

    # This will set the new URLs before the files are downloaded but will replace checksums to empty ones so download will not fail
    #  because checksums are at that moment set for the previous version.
    # $false is passed to $Package.UpdateFiles() so that if things fail here, nuspec file isn't updated; otherwise, on next run
    #  AU will think that package is the most recent.
    #
    # TODO: If fails, it will also leave other then nuspec files updated which is undesired side effect (not very important)

    $c32 = $global:Latest.Checksum32; $c64 = $global:Latest.Checksum64          #https://github.com/majkinetor/au/issues/36
    $global:Latest.Remove('Checksum32'); $global:Latest.Remove('Checksum64')    #  -||-
    $Package.UpdateFiles( $false )
    if ($c32) {$global:Latest.Checksum32 = $c32}
    if ($c64) {$global:Latest.Checksum64 = $c64}                                #  -||-

    # Invoke installer for each architecture to download files
    invoke_installer
}


