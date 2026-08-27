# Safety model

RepoSync is deliberately narrower than a general Git automation shell script.

## Repository boundary

The supplied repository path must equal Git's own working-tree root. Included
paths are normalised relative to that root and rejected when they are absolute,
contain a parent traversal, target `.git`, cross a reparse point or have no
existing or tracked match.

## Index boundary

RepoSync stages only the included pathspecs and commits them with
`git commit --only`. Existing staged work outside the scope remains staged and
is not included.

## Remote boundary

Commit is local by default. `-Push` uses only the current branch's existing
upstream. RepoSync does not add remotes, change branches or configure
credentials.

## Content boundary

RepoSync does not inspect or execute file contents. Operators remain
responsible for secret scanning, repository classification, retention and
access control before any operational data is committed.
