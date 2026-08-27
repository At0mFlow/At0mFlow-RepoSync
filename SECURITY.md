# Security

## Reporting a vulnerability

Do not open a public issue for a suspected security vulnerability. Send the
details through [at0mflow.com](https://at0mflow.com/) and include
`At0mFlow-RepoSync security` in the subject or message.

## Safe operation

RepoSync deliberately requires explicit repository-relative paths. It rejects
absolute paths, parent traversal, `.git`, reparse points and paths that neither
exist nor match a tracked deletion.

The tool never accepts or stores Git credentials. Configure non-interactive
authentication under the scheduled identity before using `-Push`. Preview the
scope first, use a private remote for operational data and keep repository
access limited to the people who need it.

RepoSync does not inspect file contents, execute repository files, call an
At0mFlow API or send telemetry.
