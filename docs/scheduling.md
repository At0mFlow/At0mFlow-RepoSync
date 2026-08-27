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

Do not place passwords, tokens or private keys in the task arguments. RepoSync
does not need them and will not store them.
