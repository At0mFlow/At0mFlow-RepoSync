[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:FailureCount = 0

function Assert-That {
    param(
        [Parameter(Mandatory)]
        [bool] $Condition,

        [Parameter(Mandatory)]
        [string] $Message
    )

    if ($Condition) {
        Write-Host "PASS: $Message" -ForegroundColor Green
    }
    else {
        $script:FailureCount++
        Write-Host "FAIL: $Message" -ForegroundColor Red
    }
}

function Invoke-ExpectedFailure {
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Action,

        [Parameter(Mandatory)]
        [string] $Message
    )

    $failedAsExpected = $false
    try {
        & $Action | Out-Null
    }
    catch {
        $failedAsExpected = $true
    }
    Assert-That $failedAsExpected $Message
}

function Invoke-TestGit {
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter(Mandatory)]
        [string[]] $ArgumentList
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& git -C $WorkingDirectory @ArgumentList 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw "Test Git command failed: git $($ArgumentList -join ' ')`n$($output -join [Environment]::NewLine)"
    }
    $output
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'src/At0mFlow.RepoSync/At0mFlow.RepoSync.psd1'
$entryPoint = Join-Path $repositoryRoot 'src/Invoke-At0mFlowRepoSync.ps1'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('At0mFlow-RepoSync-Tests-' + [guid]::NewGuid())

try {
    $manifest = Test-ModuleManifest -Path $modulePath
    Assert-That ($manifest.Version.ToString() -eq '1.0.1') 'The module manifest is valid.'

    Import-Module $modulePath -Force
    Assert-That ($null -ne (Get-Command Invoke-At0mFlowRepoSync -ErrorAction SilentlyContinue)) 'The sync command is exported.'

    if ($null -eq (Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        throw 'Git is required to run RepoSync integration tests.'
    }

    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    $remotePath = Join-Path $temporaryRoot 'Synthetic Remote.git'
    $workingPath = Join-Path $temporaryRoot 'Synthetic Working'
    $clonePath = Join-Path $temporaryRoot 'Synthetic Clone'
    New-Item -ItemType Directory -Path $workingPath | Out-Null
    & git init --bare $remotePath | Out-Null
    Invoke-TestGit -WorkingDirectory $workingPath -ArgumentList @('init') | Out-Null
    Invoke-TestGit -WorkingDirectory $workingPath -ArgumentList @('config', 'user.name', 'Synthetic Test') | Out-Null
    Invoke-TestGit -WorkingDirectory $workingPath -ArgumentList @('config', 'user.email', 'test@example.com') | Out-Null

    $scriptsPath = Join-Path $workingPath 'approved/scripts'
    $manifestsPath = Join-Path $workingPath 'approved/manifests'
    New-Item -ItemType Directory -Path $scriptsPath, $manifestsPath -Force | Out-Null
    "Write-Output 'Initial synthetic script'" |
        Set-Content -LiteralPath (Join-Path $scriptsPath 'Example.ps1') -Encoding UTF8
    '{"status":"initial"}' |
        Set-Content -LiteralPath (Join-Path $manifestsPath 'summary.json') -Encoding UTF8
    'Synthetic repository fixture.' |
        Set-Content -LiteralPath (Join-Path $workingPath 'NOTICE.txt') -Encoding UTF8
    Invoke-TestGit -WorkingDirectory $workingPath -ArgumentList @('add', '.') | Out-Null
    Invoke-TestGit -WorkingDirectory $workingPath -ArgumentList @('commit', '-m', 'Initial synthetic commit') | Out-Null
    Invoke-TestGit -WorkingDirectory $workingPath -ArgumentList @('remote', 'add', 'origin', $remotePath) | Out-Null
    Invoke-TestGit -WorkingDirectory $workingPath -ArgumentList @('push', '-u', 'origin', 'HEAD') | Out-Null

    $branch = (Invoke-TestGit -WorkingDirectory $workingPath -ArgumentList @('branch', '--show-current') | Select-Object -First 1).Trim()
    Assert-That (-not [string]::IsNullOrWhiteSpace($branch)) 'The test repository has an attached branch.'

    Add-Content -LiteralPath (Join-Path $scriptsPath 'Example.ps1') -Value "Write-Output 'Preview revision'"
    '{"status":"preview"}' |
        Set-Content -LiteralPath (Join-Path $manifestsPath 'summary.json') -Encoding UTF8
    $beforePreviewCommit = (Invoke-TestGit -WorkingDirectory $workingPath -ArgumentList @('rev-parse', 'HEAD') | Select-Object -First 1).Trim()
    $preview = Invoke-At0mFlowRepoSync `
        -RepositoryPath $workingPath `
        -IncludePath @('approved/scripts', 'approved/manifests') `
        -Preview
    Assert-That ($preview.Status -eq 'Preview') 'Preview mode reports its status.'
    $canonicalWorkingPath = (Invoke-TestGit `
        -WorkingDirectory $workingPath `
        -ArgumentList @('rev-parse', '--show-toplevel') |
            Select-Object -First 1).Trim()
    Assert-That `
        ($preview.RepositoryPath -eq [IO.Path]::GetFullPath($canonicalWorkingPath).TrimEnd('\', '/')) `
        'Equivalent Windows short and long root paths are accepted.'
    Assert-That ($preview.ChangeCount -eq 2) 'Preview reports changes only in the approved paths.'
    Assert-That ($preview.Pushed -eq $false) 'Preview never pushes.'
    $afterPreviewCommit = (Invoke-TestGit -WorkingDirectory $workingPath -ArgumentList @('rev-parse', 'HEAD') | Select-Object -First 1).Trim()
    Assert-That ($afterPreviewCommit -eq $beforePreviewCommit) 'Preview does not create a commit.'
    $previewStaged = @(Invoke-TestGit -WorkingDirectory $workingPath -ArgumentList @('diff', '--cached', '--name-only'))
    Assert-That ($previewStaged.Count -eq 0) 'Preview does not stage files.'

    'This staged file must remain outside RepoSync commits.' |
        Set-Content -LiteralPath (Join-Path $workingPath 'UNRELATED.txt') -Encoding UTF8
    Invoke-TestGit -WorkingDirectory $workingPath -ArgumentList @('add', 'UNRELATED.txt') | Out-Null
    $commitReport = Invoke-At0mFlowRepoSync `
        -RepositoryPath $workingPath `
        -IncludePath @('approved/scripts,approved/manifests') `
        -CommitMessage 'Synthetic scoped update'
    Assert-That ($commitReport.Status -eq 'Committed') 'Approved changes can be committed without a push.'
    Assert-That ($commitReport.ChangeCount -eq 2) 'The commit report lists both approved changes.'
    Assert-That ($commitReport.Commit.Length -eq 40) 'The commit identifier is returned.'
    $stagedAfterCommit = @(Invoke-TestGit -WorkingDirectory $workingPath -ArgumentList @('diff', '--cached', '--name-only'))
    Assert-That ($stagedAfterCommit -contains 'UNRELATED.txt') 'Unrelated staged work remains staged.'
    $committedNames = @(Invoke-TestGit -WorkingDirectory $workingPath -ArgumentList @('show', '--pretty=', '--name-only', 'HEAD'))
    Assert-That ($committedNames -contains 'approved/scripts/Example.ps1') 'The scoped script is in the commit.'
    Assert-That ($committedNames -contains 'approved/manifests/summary.json') 'The scoped manifest is in the commit.'
    Assert-That ($committedNames -notcontains 'UNRELATED.txt') 'The unrelated staged file is outside the commit.'
    $remoteCountBeforePush = [int] (& git --git-dir=$remotePath rev-list --count --all)
    Assert-That ($remoteCountBeforePush -eq 1) 'A commit without -Push does not change the remote.'

    Add-Content -LiteralPath (Join-Path $scriptsPath 'Example.ps1') -Value "Write-Output 'Pushed revision'"
    $pushReport = Invoke-At0mFlowRepoSync `
        -RepositoryPath $workingPath `
        -IncludePath @('approved/scripts', 'approved/manifests') `
        -Push
    Assert-That ($pushReport.Status -eq 'Pushed') 'An approved scoped update can be pushed.'
    Assert-That $pushReport.Pushed 'The report confirms the push.'
    Assert-That ($pushReport.Upstream -like 'origin/*') 'The existing upstream is reported.'
    $remoteCountAfterPush = [int] (& git --git-dir=$remotePath rev-list --count --all)
    Assert-That ($remoteCountAfterPush -eq 3) 'The remote receives the earlier local commit and pushed update.'

    $noChangesReport = Invoke-At0mFlowRepoSync `
        -RepositoryPath $workingPath `
        -IncludePath @('approved/scripts', 'approved/manifests')
    Assert-That ($noChangesReport.Status -eq 'NoChanges') 'Unrelated staged work does not create an approved-path commit.'
    Assert-That ($noChangesReport.ChangeCount -eq 0) 'NoChanges reports zero approved changes.'

    Remove-Item -LiteralPath (Join-Path $manifestsPath 'summary.json')
    $deletionReport = Invoke-At0mFlowRepoSync `
        -RepositoryPath $workingPath `
        -IncludePath @('approved/manifests') `
        -Push
    Assert-That ($deletionReport.Status -eq 'Pushed') 'A tracked deletion can be committed and pushed.'
    Assert-That ($deletionReport.ChangedFiles[0] -match '^D\s+approved/manifests/summary\.json$') 'A tracked deletion is explicit in the report.'

    Invoke-ExpectedFailure -Message 'Absolute included paths are rejected.' -Action {
        Invoke-At0mFlowRepoSync -RepositoryPath $workingPath -IncludePath $scriptsPath -Preview
    }
    Invoke-ExpectedFailure -Message 'Parent traversal is rejected.' -Action {
        Invoke-At0mFlowRepoSync -RepositoryPath $workingPath -IncludePath '../outside' -Preview
    }
    Invoke-ExpectedFailure -Message 'The .git directory is rejected.' -Action {
        Invoke-At0mFlowRepoSync -RepositoryPath $workingPath -IncludePath '.git' -Preview
    }
    Invoke-ExpectedFailure -Message 'A missing untracked path is rejected.' -Action {
        Invoke-At0mFlowRepoSync -RepositoryPath $workingPath -IncludePath 'missing-path' -Preview
    }
    Invoke-ExpectedFailure -Message 'A repository subdirectory cannot be used as RepositoryPath.' -Action {
        Invoke-At0mFlowRepoSync -RepositoryPath $scriptsPath -IncludePath 'Example.ps1' -Preview
    }
    Invoke-ExpectedFailure -Message 'Preview cannot be combined with Push.' -Action {
        Invoke-At0mFlowRepoSync -RepositoryPath $workingPath -IncludePath 'approved/scripts' -Preview -Push
    }

    $noUpstreamPath = Join-Path $temporaryRoot 'No Upstream'
    New-Item -ItemType Directory -Path $noUpstreamPath | Out-Null
    Invoke-TestGit -WorkingDirectory $noUpstreamPath -ArgumentList @('init') | Out-Null
    Invoke-TestGit -WorkingDirectory $noUpstreamPath -ArgumentList @('config', 'user.name', 'Synthetic Test') | Out-Null
    Invoke-TestGit -WorkingDirectory $noUpstreamPath -ArgumentList @('config', 'user.email', 'test@example.com') | Out-Null
    'Synthetic.' | Set-Content -LiteralPath (Join-Path $noUpstreamPath 'approved.txt') -Encoding UTF8
    Invoke-TestGit -WorkingDirectory $noUpstreamPath -ArgumentList @('add', 'approved.txt') | Out-Null
    Invoke-TestGit -WorkingDirectory $noUpstreamPath -ArgumentList @('commit', '-m', 'Initial') | Out-Null
    Add-Content -LiteralPath (Join-Path $noUpstreamPath 'approved.txt') -Value 'Revision.'
    Invoke-ExpectedFailure -Message 'Push requires an existing upstream.' -Action {
        Invoke-At0mFlowRepoSync -RepositoryPath $noUpstreamPath -IncludePath 'approved.txt' -Push
    }

    Add-Content -LiteralPath (Join-Path $scriptsPath 'Example.ps1') -Value "Write-Output 'JSON preview'"
    $jsonText = & $entryPoint `
        -RepositoryPath $workingPath `
        -IncludePath approved/scripts `
        -Preview `
        -Format Json 6>&1 | Out-String
    $jsonReport = $jsonText | ConvertFrom-Json
    Assert-That ($LASTEXITCODE -eq 0) 'The JSON entry point exits successfully.'
    Assert-That ($jsonReport.Status -eq 'Preview') 'JSON output contains the report.'
    Assert-That ($jsonText -notmatch 'PowerShell clarity\.') 'JSON output does not include console branding.'

    $consoleText = & $entryPoint `
        -RepositoryPath $workingPath `
        -IncludePath approved/scripts `
        -Preview `
        -Format Console 6>&1 | Out-String
    $block = [string] [char] 0x2588
    $logoFragment = '       ' + (($block * 5) -join '') + [char] 0x2557
    Assert-That ($LASTEXITCODE -eq 0) 'The console entry point exits successfully.'
    Assert-That $consoleText.Contains($logoFragment) 'Interactive output renders the At0mFlow block wordmark.'
    Assert-That ($consoleText -match 'At0mFlow RepoSync') 'Interactive output identifies RepoSync.'

    & $entryPoint `
        -RepositoryPath (Join-Path $temporaryRoot 'Missing Repository') `
        -IncludePath approved/scripts `
        -Quiet 2>$null
    Assert-That ($LASTEXITCODE -eq 2) 'Invalid input returns exit code 2.'

    & git clone $remotePath $clonePath | Out-Null
    $remoteTree = @(Invoke-TestGit -WorkingDirectory $clonePath -ArgumentList @('ls-tree', '-r', '--name-only', 'HEAD'))
    Assert-That ($remoteTree -notcontains 'UNRELATED.txt') 'Unrelated staged work was never pushed.'
    Assert-That ($remoteTree -notcontains 'approved/manifests/summary.json') 'The tracked deletion reached the remote.'
}
finally {
    $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
    $resolvedSystemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemporaryRoot) -like 'At0mFlow-RepoSync-Tests-*' -and
        (Test-Path -LiteralPath $resolvedTemporaryRoot)) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
    }
}

if ($script:FailureCount -gt 0) {
    throw "$script:FailureCount test assertion(s) failed."
}

Write-Host 'All tests passed.' -ForegroundColor Cyan
exit 0
