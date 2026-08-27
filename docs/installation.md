# Installation

Clone the public repository and verify the requirements:

```powershell
git clone https://github.com/At0mFlow/At0mFlow-RepoSync.git
Set-Location .\At0mFlow-RepoSync
git --version
$PSVersionTable.PSVersion
```

RepoSync has no third-party PowerShell module dependency.

The target working tree must already have its own Git repository. RepoSync does
not initialise it or create its remote.
