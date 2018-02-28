# Development

The development requires Powershell 5+.

The following scripts are used during development and deployment:

- `setup.ps1`  
Install dependencies for everything.
- `build.ps1`  
Build the module and packages.
- `install.ps1`  
Install the module in the system.
- `publish.ps1`  
Publish module to Powershell Gallery, Chocolatey and Github.


## Build and test

The builded module will be available in the `_build\{version}` directory. Version is by default determined automatically based on the current time.

```
./build.ps1
```
The following example commands can be run from the repository root:

| Description                                             | Command                              |
| :---                                                    | :---                                 |
| Override default version                                | `./build -Version 0.0.1`             |
| Build and install in the system with short version      | `./build.ps1 -Install -ShortVersion` |
| Install latest build in the system                      | `./install.ps1`                      |
| Install using given path in the system                  | `./install.ps1 -module_path AU`      |
| Uninstall from the system                               | `./install.ps1 -Remove`              |
| Run tests (use `Pester` & `Chocolatey` params to limit) | `./test.ps1`                         |
| Clean temporary build files                             | `git clean -Xfd -e vars.ps1`         |


## Publish

The `publish.ps1` script publishes to Github, PSGallery and Chocolatey. There is a switch parameter for each publishing platform and there is also a parameter for creating a git tag.

```powershell
$v = ./build.ps1   #create a new version
./publish.ps1 -Version $v -Tag -Github -PSGallery -Chocolatey  #publish everywhere
```

Before publishing, edit the `NEXT` header in the `CHANGELOG.md` file to set the release notes. The publish script will take content of the second level header named after version as the release notes. The publishing will fail if release notes are not found. If that happens, don't forget to edit the file **and commit/push it to repository** in order for next tag to include it.

Chocolatey package description is automatically taken from the README.md section "## Features".

Publishing procedure depends on number of environment variables. Rename `vars_default.ps1` to `vars.ps1` and set variables there to get them included.
