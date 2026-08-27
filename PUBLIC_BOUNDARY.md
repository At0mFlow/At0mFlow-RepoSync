# Public repository boundary

At0mFlow RepoSync is a standalone, public Git helper. It is intentionally
separate from the At0mFlow product.

It may contain only the open PowerShell tool, tests, synthetic examples, public
documentation, repository configuration and approved brand assets.

It must not contain At0mFlow product code, prompts, scoring rules, analysis,
cleanup or migration logic, backend code, application configuration,
credentials, customer data, real Git remotes or operational repositories.

RepoSync acts only on an existing working tree and explicit repository-relative
paths. It does not initialise Git, create a remote, store credentials, discover
files outside the supplied paths, upload to At0mFlow or send telemetry. Push is
opt-in and uses the repository's existing upstream and authentication.
