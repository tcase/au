# Author: Miodrag Milic <miodrag.milic@gmail.com>
# Last Change: 09-Nov-2016.

# https://www.appveyor.com/docs/how-to/git-push/

param(
    $Info,

    # Git username
    [string] $User,

    # Git password. You can use Github Token here if you omit username.
    [string] $Password,

    # Force git commit when package is updated but not pushed.
    [switch] $Force,

    # Commit strategy: 
    #  single    - 1 commit with all packages
    #  atomic    - 1 commit per package    
    #  atomictag - 1 commit and tag per package
    [ValidateSet('single', 'atomic', 'atomictag')]
    [string]$commitStrategy = 'single',

    # Branch name
    [string]$Branch = 'master',
	
	# Remote Repo Host
	[ValidateSet('github', 'gitlab')]
	[string]$RemoteRepoHost = 'github'
)

[array]$packages = if ($Force) { $Info.result.updated } else { $Info.result.pushed }
if ($packages.Length -eq 0) { Write-Host "No package updated, skipping"; return }

$root = Split-Path $packages[0].Path
pushd $root
$origin  = git config --get remote.origin.url
$origin -match '(?<=:/+)[^/]+' | Out-Null
$machine = $Matches[0]
# Adding regex to remove http headers from the machine name
if ($machine -match '@(.+)') { $machine = $Matches[1] }

if ($User -and $Password) {
    Write-Host "Setting credentials for: $machine"

    if ( "machine $machine" -notmatch (gc ~/_netrc -erroraction 'silentlycontinue') ) {
        Write-Host "Credentials already found for machine: $machine"
    }
    "machine $machine", "login $User", "password $Password" | Out-File -Append ~/_netrc -Encoding ascii
} elseif ($Password) {
    Write-Host "Setting oauth token for: $machine"
    git config --global credential.helper store
	if ($RemoteRepoHost.ToLower() -eq 'github') {
		Add-Content "$env:USERPROFILE\.git-credentials" "https://${Password}:x-oauth-basic@$machine`n"
	}
	elseif ($RemoteRepoHost.ToLower() -eq 'gitlab') {
		$newOrigin = $origin -replace "(https?://).*@(.*)","`$1Private-Token:$test@`$2"
		git config remote.origin.url $newOrigin
	}
	
}

Write-Host "Executing git pull"
git checkout -q $Branch
git pull -q origin $Branch


if  ($commitStrategy -like 'atomic*') {
    $packages | % {
        Write-Host "Adding update package to git repository: $($_.Name)"
        git add -u $_.Path
        git status

        Write-Host "Commiting $($_.Name)"
        $message = "AU: $($_.Name) upgraded from $($_.NuspecVersion) to $($_.RemoteVersion)"
        $gist_url = $Info.plugin_results.Gist -split '\n' | select -Last 1
        $snippet_url = $Info.plugin_results.Snippet -split '\n' | select -Last 1
        git commit -m "$message`n[skip ci] $gist_url $snippet_url" --allow-empty

        if ($commitStrategy -eq 'atomictag') {
          $tagcmd = "git tag -a $($_.Name)-$($_.RemoteVersion) -m '$($_.Name)-$($_.RemoteVersion)'"
          Invoke-Expression $tagcmd
        }
    }
}
else {
    Write-Host "Adding updated packages to git repository: $( $packages | % Name)"
    $packages | % { git add -u $_.Path }
    git status

    Write-Host "Commiting"
    $message = "AU: $($packages.Length) updated - $($packages | % Name)"
    $gist_url = $Info.plugin_results.Gist -split '\n' | select -Last 1
    $snippet_url = $Info.plugin_results.Snippet -split '\n' | select -Last 1
    git commit -m "$message`n[skip ci] $gist_url $snippet_url" --allow-empty

}
Write-Host "Pushing changes"
git push -q 
if ($commitStrategy -eq 'atomictag') {
    write-host 'Atomic Tag Push'
    git push -q --tags
}
popd
