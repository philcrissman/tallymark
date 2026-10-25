# Contributing to Tallymark

Thanks for your interest! Tallymark aims to stay small, so it's worth opening an issue to discuss a feature before you build it.

## Getting set up

You'll need Docker, Elm 0.19.1, and (for running locally) the AWS CLI and SAM CLI. See [Local development](README.md#local-development) in the README.

```bash
make local-setup && make local-seed
make local-api                      # backend on :3000
make build-dashboard                # then serve dashboard/build on :8080
```

## Guidelines

- **Privacy first.** Tallymark doesn't collect identifiers, set cookies, or fingerprint visitors. Changes that would weaken that won't be accepted.
- **Keep the tracker tiny.** It should stay plain, dependency-free JavaScript.
- **Match the surrounding style.** Haskell follows the existing module layout under `Analytics.*`. Run Elm code through `elm-format`.
- **Don't commit build output.** `backend/build/`, `dashboard/build/` and `elm-stuff/` are git-ignored.
- CI builds the backend, the dashboard, and lints the SAM template (`cfn-lint infra/template.yaml`). Please make sure it passes.

## Reporting security issues

Please don't open a public issue for security problems. Email the maintainer instead (see the commit history for contact details).

## License

By contributing, you agree that your contributions will be licensed under the [AGPL-3.0](LICENSE).
