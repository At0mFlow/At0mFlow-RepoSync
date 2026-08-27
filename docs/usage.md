# Usage

## Required scope

`-RepositoryPath` must resolve to the root of an existing working tree.
`-IncludePath` accepts one or more relative files or folders beneath that root.

```powershell
./src/Invoke-At0mFlowRepoSync.ps1 `
    -RepositoryPath D:\PrivateGit\Operations `
    -IncludePath scripts, manifests, README.txt `
    -Preview
```

## Preview

`-Preview` performs no staging, commit or push. Console, object and JSON output
show the exact Git name-status entries in scope.

## Commit

Omit `-Preview` to stage and commit only the approved paths. The default commit
message is `At0mFlow RepoSync update` plus a UTC timestamp.

```powershell
./src/Invoke-At0mFlowRepoSync.ps1 `
    -RepositoryPath D:\PrivateGit\Operations `
    -IncludePath reports `
    -CommitMessage 'Hourly report refresh'
```

## Push

`-Push` commits and then pushes to the current branch's existing upstream. It
fails clearly when the upstream or non-interactive authentication is missing.

## Machine output

Use `-Format Json` for a compact result or `-Quiet` for scheduled execution.

| Exit code | Meaning |
| ---: | --- |
| `0` | Preview, no changes, commit or push completed successfully. |
| `2` | Validation, Git, commit or push failed. |
