# AGENTS — httpz-logger

Operating rules for humans + AI.

## Workflow

- Never commit to `main`/`master`.
- Always start on a new branch.
- Only push after the user approves.
- Merge via PR.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/).

- fix → patch
- feat → minor
- feat! / BREAKING CHANGE → major
- chore, docs, refactor, test, ci, style, perf → no version change

## Releases

- Semantic versioning.
- Versions derived from Conventional Commits.
- Release performed locally via `/create-release` (no CI required).
- Manifest (if present) is source of truth.
- Tags: vX.Y.Z

## Repo map

| Path | Description |
|------|-------------|
| `LICENSE` | MIT licence |
| `.gitignore` | Zig build artefact exclusions (`.zig-cache/`, `zig-out/`) |
| `MIGRATION_PLAN.md` | v2 rewrite plan — architecture, implementation details, and checklist |

## Merge strategy

- Prefer squash merge.
- PR title must be a valid Conventional Commit.

## Definition of done

- Works locally.
- Tests updated if behaviour changed.
- CHANGELOG updated when user-facing.
- No secrets committed.

## Orientation

- **Entry point**: `MIGRATION_PLAN.md` — the repo is pre-implementation; the plan is the primary reference.
- **Domain**: HTTP request logging middleware for the Zig [httpz](https://github.com/karlseguin/http.zig) framework, backed by [logz](https://github.com/karlseguin/log.zig).
- **Stack**: Zig 0.15+, httpz, logz.
