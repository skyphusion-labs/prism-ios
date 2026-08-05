# CLAUDE.md -- prism-ios

Guidance for agents working in this repository.

## What this is

**AGPL iOS client kit for Prism.** Chat, multimodal modalities, and (later) subscription / quota UX
against the commercial control plane. Goal is easier access to a curated model set with
cost-recovery hosting, not a closed app.

**Status: skeleton only.** Honest status matches `README.md`. Aviation-grade `main` (PR + CI +
coverage). Shared Swift package only for now; Xcode app target comes when UI work starts. Next:
Bearer auth client, chat + stream against the public or self-hosted Prism API.

## Related

| Repo | Role |
| --- | --- |
| [prism](https://github.com/skyphusion-labs/prism) | Inference playground Worker (`play.skyphusion.org`) |
| [prism-control-plane](https://github.com/skyphusion-labs/prism-control-plane) | Commercial multi-tenant control plane (skeleton) |
| [prism-android](https://github.com/skyphusion-labs/prism-android) | Sibling Android kit (skeleton) |

## Layout

- `Sources/PrismKit` -- shared Swift package (API client, models)
- `Tests/` -- package tests
- `Package.swift` -- SPM manifest

## Commands

```bash
swift test   # library tests (Ubuntu CI with setup-swift; full UI later on macOS)
```

## CI

- `.github/workflows/ci.yml` -- push/PR to `main`: `swift test` on `ubuntu-latest`
- Coverage / CodeQL workflows present; public repo uses GitHub-hosted runners only (fork-safe)

## Conventions

- No em-dashes (U+2014) or en-dashes (U+2013) in source or docs; use commas, semicolons, or `--`.
- Handle / username default: `skyphusion`.
- Conventional Commits. License: AGPL-3.0-only.
- Do not invent production deploy docs for a skeleton; keep status honest.

## Crew + identity

Crew work as their own identity (`sudo -u <member> bash -lc '...'`). Conrad laptop commits:
`Conrad Rockenhaus <conrad@skyphusion.org>`.
