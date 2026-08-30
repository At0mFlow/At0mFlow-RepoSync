@{
    RootModule        = 'At0mFlow.RepoSync.psm1'
    ModuleVersion     = '1.0.2'
    GUID              = '0ad58bf3-85f3-40b8-9fcc-5cc6d4678a70'
    Author            = 'At0mFlow'
    CompanyName       = 'At0mFlow'
    Copyright         = 'Copyright (c) 2026 At0mFlow. Licensed under the MIT License.'
    Description       = 'Creates safe, path-scoped commits and optional pushes in an existing Git working tree.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Invoke-At0mFlowRepoSync'
        'Write-At0mFlowRepoSyncReport'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags = @(
                'PowerShell'
                'Git'
                'Automation'
                'DevOps'
                'Repository'
                'ScheduledTasks'
                'PSEdition_Desktop'
                'PSEdition_Core'
            )
            LicenseUri = 'https://github.com/At0mFlow/At0mFlow-RepoSync/blob/main/LICENSE'
            ProjectUri = 'https://github.com/At0mFlow/At0mFlow-RepoSync'
        }
    }
}
