# Contributing

1. Fork the repository and create a focused branch.
2. Keep every fixture synthetic.
3. Do not add credentials, real remotes, customer paths or At0mFlow product
   code.
4. Run `./scripts/Test-PublicBoundary.ps1`.
5. Run `./tests/Run-Tests.ps1`.
6. Analyse `src` with PSScriptAnalyzer 1.25.0.
7. Open a pull request describing the safety impact and tests.
