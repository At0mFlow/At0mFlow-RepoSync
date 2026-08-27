# Public repository boundary

Use Australian English. Write clearly, naturally and concisely. Never use em
dashes.

This repository is public and contains only the standalone At0mFlow RepoSync
tool, its tests, synthetic examples, documentation and approved brand assets.

## Non-negotiable separation rules

- Never copy At0mFlow product code, prompts, scoring, analysis, cleanup,
  migration, backend, API, authentication, billing or customer data here.
- Never add real repositories, server inventories, collected scripts, remotes,
  credentials, tokens, private keys or identifying machine paths.
- Never initialise a user's repository, create a remote, create credentials or
  broaden a user-supplied path scope.
- Never stage or commit `.git`, absolute paths, parent traversals, reparse points
  or paths outside the validated repository root.
- Never upload data to At0mFlow or another service. A requested Git push may use
  only the existing upstream and the operator's existing non-interactive Git
  configuration.
- Never stage files from outside this repository while developing RepoSync.
- Keep `origin` pointed only to
  `https://github.com/At0mFlow/At0mFlow-RepoSync.git` or its equivalent GitHub
  SSH URL.
- Use synthetic fixtures only.
- Keep the README's `Other public At0mFlow tools` section current. It must link
  every other public At0mFlow tool and must not link this repository to itself.
- Before every commit and push, run `./scripts/Test-PublicBoundary.ps1` and
  `./tests/Run-Tests.ps1`.
- Stop if the boundary check fails.
