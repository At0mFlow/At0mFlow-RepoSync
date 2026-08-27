<#
.SYNOPSIS
Creates a path-scoped commit and optional push in an existing Git working tree.

.EXAMPLE
./src/Invoke-At0mFlowRepoSync.ps1 -RepositoryPath D:\PrivateGit\Operations -IncludePath scripts, manifests -Preview

.EXAMPLE
./src/Invoke-At0mFlowRepoSync.ps1 -RepositoryPath D:\PrivateGit\Operations -IncludePath scripts, manifests -Push -Quiet
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $RepositoryPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]] $IncludePath,

    [ValidateNotNullOrEmpty()]
    [string] $CommitMessage = 'At0mFlow RepoSync update',

    [switch] $Preview,

    [switch] $Push,

    [ValidateSet('Console', 'Object', 'Json')]
    [string] $Format = 'Console',

    [switch] $Quiet
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'At0mFlow.RepoSync/At0mFlow.RepoSync.psd1'

try {
    Import-Module $modulePath -Force
    $report = Invoke-At0mFlowRepoSync `
        -RepositoryPath $RepositoryPath `
        -IncludePath $IncludePath `
        -CommitMessage $CommitMessage `
        -Preview:$Preview.IsPresent `
        -Push:$Push.IsPresent

    if (-not $Quiet.IsPresent) {
        switch ($Format) {
            'Console' { Write-At0mFlowRepoSyncReport -Report $report }
            'Object' { $report }
            'Json' {
                $report |
                    Select-Object Status, RepositoryPath, IncludedPaths,
                        ChangeCount, ChangedFiles, Commit, Branch, Upstream,
                        Pushed, StartedAtUtc, CompletedAtUtc |
                    ConvertTo-Json -Depth 5
            }
        }
    }
    exit 0
}
catch {
    [Console]::Error.WriteLine("At0mFlow RepoSync failed: {0}", $_.Exception.Message)
    exit 2
}
