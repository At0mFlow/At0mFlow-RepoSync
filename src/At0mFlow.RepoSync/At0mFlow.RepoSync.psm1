Set-StrictMode -Version 2.0

function Invoke-At0mFlowRepoGitCommand {
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter(Mandatory)]
        [string[]] $ArgumentList,

        [int[]] $AcceptedExitCode = @(0)
    )

    $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $gitCommand) {
        throw 'Git was not found on PATH.'
    }

    $previousPromptSetting = $env:GIT_TERMINAL_PROMPT
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $env:GIT_TERMINAL_PROMPT = '0'
        $ErrorActionPreference = 'Continue'
        $commandOutput = @(
            & $gitCommand.Source -C $WorkingDirectory -c core.longpaths=true @ArgumentList 2>&1
        )
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        [Environment]::SetEnvironmentVariable(
            'GIT_TERMINAL_PROMPT',
            $previousPromptSetting,
            [EnvironmentVariableTarget]::Process
        )
    }

    if ($AcceptedExitCode -notcontains $exitCode) {
        $readableOutput = ($commandOutput | ForEach-Object { [string] $_ }) -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($readableOutput)) {
            $readableOutput = 'Git returned no diagnostic output.'
        }
        throw "Git command failed with exit code $exitCode`: git $($ArgumentList -join ' ')`n$readableOutput"
    }

    [pscustomobject] @{
        ExitCode = $exitCode
        Output   = (($commandOutput | ForEach-Object { [string] $_ }) -join [Environment]::NewLine).Trim()
    }
}

function Resolve-At0mFlowRepoSyncPath {
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $Path
    )

    $trimmedPath = $Path.Trim().Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($trimmedPath)) {
        throw 'Included paths cannot be empty.'
    }
    if ([IO.Path]::IsPathRooted($trimmedPath)) {
        throw "Included paths must be repository-relative: $Path"
    }

    $segments = @($trimmedPath -split '/' | Where-Object { $_ -ne '' -and $_ -ne '.' })
    if (($segments.Count -eq 0) -or ($segments -contains '..')) {
        throw "Included paths cannot contain parent traversal: $Path"
    }
    if ($segments[0].Equals('.git', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The .git directory is always outside RepoSync scope.'
    }

    $normalisedPath = $segments -join '/'
    $repositoryFullPath = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
    $candidateFullPath = [IO.Path]::GetFullPath(
        (Join-Path $repositoryFullPath ($normalisedPath.Replace('/', [IO.Path]::DirectorySeparatorChar)))
    ).TrimEnd('\', '/')
    $repositoryPrefix = $repositoryFullPath + [IO.Path]::DirectorySeparatorChar
    if (-not $candidateFullPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Included path resolves outside the repository: $Path"
    }

    $pathToCheck = $candidateFullPath
    while (-not (Test-Path -LiteralPath $pathToCheck)) {
        $parentPath = Split-Path -Parent $pathToCheck
        if ([string]::IsNullOrWhiteSpace($parentPath) -or ($parentPath -eq $pathToCheck)) {
            break
        }
        $pathToCheck = $parentPath
    }
    if (Test-Path -LiteralPath $pathToCheck) {
        $itemToCheck = Get-Item -LiteralPath $pathToCheck -Force -ErrorAction Stop
        while ($null -ne $itemToCheck) {
            if ($itemToCheck.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse points are outside RepoSync scope: $($itemToCheck.FullName)"
            }
            if ($itemToCheck.FullName.TrimEnd('\', '/') -eq $repositoryFullPath) {
                break
            }
            $itemToCheck = $itemToCheck.Parent
        }
    }

    [pscustomobject] @{
        RelativePath = $normalisedPath
        FullPath     = $candidateFullPath
        Exists       = Test-Path -LiteralPath $candidateFullPath
    }
}

function Get-At0mFlowRepoSyncContext {
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryPath,

        [Parameter(Mandatory)]
        [string[]] $IncludePath,

        [switch] $RequireUpstream
    )

    if (-not (Test-Path -LiteralPath $RepositoryPath -PathType Container)) {
        throw "RepositoryPath does not exist or is not a directory: $RepositoryPath"
    }
    $resolvedRepositoryPath = [IO.Path]::GetFullPath($RepositoryPath).TrimEnd('\', '/')
    $repositoryItem = Get-Item -LiteralPath $resolvedRepositoryPath -Force -ErrorAction Stop
    if ($repositoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "RepositoryPath cannot be a reparse point: $RepositoryPath"
    }
    $rootResult = Invoke-At0mFlowRepoGitCommand `
        -WorkingDirectory $resolvedRepositoryPath `
        -ArgumentList @('rev-parse', '--show-toplevel')
    $gitRoot = [IO.Path]::GetFullPath($rootResult.Output).TrimEnd('\', '/')
    $prefixResult = Invoke-At0mFlowRepoGitCommand `
        -WorkingDirectory $resolvedRepositoryPath `
        -ArgumentList @('rev-parse', '--show-prefix')
    if (-not [string]::IsNullOrWhiteSpace($prefixResult.Output)) {
        throw "RepositoryPath must be the Git working-tree root: $gitRoot"
    }

    if (Test-Path -LiteralPath (Join-Path $gitRoot '.git/index.lock')) {
        throw 'Git index.lock exists. Another Git operation may be active.'
    }

    $normalisedIncludes = New-Object 'System.Collections.Generic.List[string]'
    foreach ($requestedValue in $IncludePath) {
        foreach ($requestedPath in @($requestedValue -split ',')) {
            $resolvedPath = Resolve-At0mFlowRepoSyncPath `
                -RepositoryRoot $gitRoot `
                -Path $requestedPath
            if (-not $resolvedPath.Exists) {
                $trackedResult = Invoke-At0mFlowRepoGitCommand `
                    -WorkingDirectory $gitRoot `
                    -ArgumentList @('ls-files', '--', $resolvedPath.RelativePath)
                if ([string]::IsNullOrWhiteSpace($trackedResult.Output)) {
                    throw "Included path does not exist and has no tracked deletion: $($resolvedPath.RelativePath)"
                }
            }
            if (-not $normalisedIncludes.Contains($resolvedPath.RelativePath)) {
                $normalisedIncludes.Add($resolvedPath.RelativePath)
            }
        }
    }
    if ($normalisedIncludes.Count -eq 0) {
        throw 'At least one included path is required.'
    }

    $branchResult = Invoke-At0mFlowRepoGitCommand `
        -WorkingDirectory $gitRoot `
        -ArgumentList @('rev-parse', '--abbrev-ref', 'HEAD')
    if ($branchResult.Output -eq 'HEAD') {
        throw 'RepoSync does not commit from a detached HEAD.'
    }

    $upstreamResult = Invoke-At0mFlowRepoGitCommand `
        -WorkingDirectory $gitRoot `
        -ArgumentList @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}') `
        -AcceptedExitCode @(0, 128)
    if ($RequireUpstream.IsPresent -and ($upstreamResult.ExitCode -ne 0)) {
        throw 'Push requires an existing upstream for the current branch.'
    }

    [pscustomobject] @{
        RepositoryPath = $gitRoot
        IncludedPaths  = $normalisedIncludes.ToArray()
        Branch         = $branchResult.Output
        Upstream       = $(if ($upstreamResult.ExitCode -eq 0) { $upstreamResult.Output } else { '' })
    }
}

function Invoke-At0mFlowRepoSync {
    <#
    .SYNOPSIS
    Creates a path-scoped commit and optional push in an existing Git working tree.
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

        [switch] $Push
    )

    if ($Preview.IsPresent -and $Push.IsPresent) {
        throw '-Preview cannot be combined with -Push.'
    }

    $startedAtUtc = [DateTimeOffset]::UtcNow
    $context = Get-At0mFlowRepoSyncContext `
        -RepositoryPath $RepositoryPath `
        -IncludePath $IncludePath `
        -RequireUpstream:$Push.IsPresent
    $pathspecs = @($context.IncludedPaths)

    if ($Preview.IsPresent) {
        $previewResult = Invoke-At0mFlowRepoGitCommand `
            -WorkingDirectory $context.RepositoryPath `
            -ArgumentList (@('status', '--short', '--untracked-files=all', '--') + $pathspecs)
        $previewChanges = @(
            $previewResult.Output -split '\r?\n' |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        return [pscustomobject] @{
            PSTypeName      = 'At0mFlow.RepoSync.Report'
            StartedAtUtc    = $startedAtUtc
            CompletedAtUtc  = [DateTimeOffset]::UtcNow
            Status          = 'Preview'
            RepositoryPath  = $context.RepositoryPath
            IncludedPaths   = $pathspecs
            ChangeCount     = $previewChanges.Count
            ChangedFiles    = $previewChanges
            Commit          = ''
            Branch          = $context.Branch
            Upstream        = $context.Upstream
            Pushed          = $false
        }
    }

    Invoke-At0mFlowRepoGitCommand `
        -WorkingDirectory $context.RepositoryPath `
        -ArgumentList (@('add', '-A', '--') + $pathspecs) | Out-Null
    $diffResult = Invoke-At0mFlowRepoGitCommand `
        -WorkingDirectory $context.RepositoryPath `
        -ArgumentList (@('diff', '--cached', '--name-status', '--') + $pathspecs)
    $changedFiles = @(
        $diffResult.Output -split '\r?\n' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($changedFiles.Count -eq 0) {
        return [pscustomobject] @{
            PSTypeName      = 'At0mFlow.RepoSync.Report'
            StartedAtUtc    = $startedAtUtc
            CompletedAtUtc  = [DateTimeOffset]::UtcNow
            Status          = 'NoChanges'
            RepositoryPath  = $context.RepositoryPath
            IncludedPaths   = $pathspecs
            ChangeCount     = 0
            ChangedFiles    = @()
            Commit          = ''
            Branch          = $context.Branch
            Upstream        = $context.Upstream
            Pushed          = $false
        }
    }

    $datedMessage = '{0} ({1})' -f $CommitMessage.Trim(), ([DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))
    Invoke-At0mFlowRepoGitCommand `
        -WorkingDirectory $context.RepositoryPath `
        -ArgumentList (@('commit', '--only', '-m', $datedMessage, '--') + $pathspecs) | Out-Null
    $commitResult = Invoke-At0mFlowRepoGitCommand `
        -WorkingDirectory $context.RepositoryPath `
        -ArgumentList @('rev-parse', 'HEAD')

    $status = 'Committed'
    $pushed = $false
    if ($Push.IsPresent) {
        Invoke-At0mFlowRepoGitCommand `
            -WorkingDirectory $context.RepositoryPath `
            -ArgumentList @('push') | Out-Null
        $status = 'Pushed'
        $pushed = $true
    }

    [pscustomobject] @{
        PSTypeName      = 'At0mFlow.RepoSync.Report'
        StartedAtUtc    = $startedAtUtc
        CompletedAtUtc  = [DateTimeOffset]::UtcNow
        Status          = $status
        RepositoryPath  = $context.RepositoryPath
        IncludedPaths   = $pathspecs
        ChangeCount     = $changedFiles.Count
        ChangedFiles    = $changedFiles
        Commit          = $commitResult.Output
        Branch          = $context.Branch
        Upstream        = $context.Upstream
        Pushed          = $pushed
    }
}

function Write-At0mFlowRepoSyncWordmark {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'The wordmark is intended for interactive console output.'
    )]
    [CmdletBinding()]
    param()

    $orbitLines = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Orbit.Console.txt'))
    $logoLines = @(
        '       #####> ########> ######> ###>   ###>#######>##>      ######> ##>    ##>'
        '      ##<--##>[--##<--]##<-####>####> ####|##<----]##|     ##<---##>##|    ##|'
        '      #######|   ##|   ##|##<##|##<####<##|#####>  ##|     ##|   ##|##| #> ##|'
        '      ##<--##|   ##|   ####<]##|##|[##<]##|##<--]  ##|     ##|   ##|##|###>##|'
        '      ##|  ##|   ##|   [######<]##| [-] ##|##|     #######>[######<][###<###<]'
        '      [-]  [-]   [-]    [-----] [-]     [-][-]     [------] [-----]  [--][--]'
    )
    $logoGlyphs = [ordered] @{
        '#' = [char] 0x2588
        '<' = [char] 0x2554
        '>' = [char] 0x2557
        '[' = [char] 0x255A
        ']' = [char] 0x255D
        '-' = [char] 0x2550
        '|' = [char] 0x2551
    }

    Write-Host ('=' * 98) -ForegroundColor DarkGray
    Write-Host ''
    foreach ($orbitLine in $orbitLines) {
        Write-Host $orbitLine -ForegroundColor Green
    }
    Write-Host ''
    foreach ($logoLine in $logoLines) {
        $renderedLogoLine = $logoLine
        foreach ($placeholder in $logoGlyphs.Keys) {
            $renderedLogoLine = $renderedLogoLine.Replace($placeholder, [string] $logoGlyphs[$placeholder])
        }
        Write-Host $renderedLogoLine -ForegroundColor Cyan
    }
    Write-Host ''
    Write-Host '                     PowerShell clarity.' -ForegroundColor White
    Write-Host '                      Orbit-level control.' -ForegroundColor White
    Write-Host ''
    Write-Host '                   ANALYSE | CLEAN | MIGRATE | MONITOR' -ForegroundColor Green
    Write-Host ''
    Write-Host '                         https://at0mflow.com' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host ('=' * 98) -ForegroundColor DarkGray
}

function Write-At0mFlowRepoSyncReport {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'This function renders interactive console output.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject] $Report,

        [switch] $NoBanner
    )

    process {
        if (-not $NoBanner.IsPresent) {
            Write-At0mFlowRepoSyncWordmark
        }
        Write-Host ''
        Write-Host 'At0mFlow RepoSync' -ForegroundColor Cyan
        Write-Host ('Status: {0}' -f $Report.Status)
        Write-Host ('Repository: {0}' -f $Report.RepositoryPath) -ForegroundColor DarkCyan
        Write-Host ('Scope: {0}' -f (@($Report.IncludedPaths) -join ', '))
        Write-Host ('Changes: {0}' -f $Report.ChangeCount)
        Write-Host ('Branch: {0}' -f $Report.Branch)
        if (-not [string]::IsNullOrWhiteSpace([string] $Report.Upstream)) {
            Write-Host ('Upstream: {0}' -f $Report.Upstream)
        }
        if (-not [string]::IsNullOrWhiteSpace([string] $Report.Commit)) {
            Write-Host ('Commit: {0}' -f $Report.Commit)
        }
        Write-Host ''
    }
}

Export-ModuleMember -Function @(
    'Invoke-At0mFlowRepoSync'
    'Write-At0mFlowRepoSyncReport'
)
