# Hourly scheduling

RepoSync does not create scheduled tasks. Configure the schedule through your
existing Windows, SCCM or job-runner controls after an interactive preview and
push have succeeded.

## Checklist

1. Use a private repository for operational data.
2. Run under an approved service or managed execution identity.
3. Configure repository-local Git author details for that identity.
4. Configure non-interactive authentication to the existing upstream.
5. Grant access only to the repository and included paths.
6. Run with `-Preview` and inspect every name-status entry.
7. Perform and inspect the first push interactively.
8. Schedule the exact tested command hourly.
9. Set the scheduler to skip overlapping runs.
10. Monitor exit code `2` and standard error.

Example scheduled command:

```text
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File D:\Tools\At0mFlow-RepoSync\src\Invoke-At0mFlowRepoSync.ps1 -RepositoryPath D:\PrivateGit\Operations -IncludePath scripts,manifests -Push -Quiet
```

## Several collector folders

If separate servers produce their own audit bundles, keep each unchanged under
a distinct repository-relative folder:

```text
PowerShell-Estate/
  collectors/
    SERVER-01/
      README.txt
      scripts/
      manifests/
    SERVER-02/
      README.txt
      scripts/
      manifests/
```

Run one RepoSync job from the repository root after the collector folders have
been refreshed. Preview the complete scope first:

```powershell
./src/Invoke-At0mFlowRepoSync.ps1 `
    -RepositoryPath D:\PrivateGit\PowerShell-Estate `
    -IncludePath collectors `
    -Preview
```

Once reviewed, use the same command with `-Push -Quiet`. Do not run concurrent
RepoSync jobs against one working tree or have several machines push the same
branch at the same time.

Do not place passwords, tokens or private keys in the task arguments. RepoSync
does not need them and will not store them.
