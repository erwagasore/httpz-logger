# Contributing to httpz-logger

## Commit Message Guidelines

This project uses [Conventional Commits](https://www.conventionalcommits.org/) to automate version bumps and changelog generation.

### Commit Message Format

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types that Trigger Version Bumps

| Type | Version Bump | When to Use | Example |
|------|-------------|-------------|---------|
| `feat` | Minor | New feature | `feat: add CSV output format` |
| `fix` | Patch | Bug fix | `fix: handle null timestamp values` |
| `perf` | Patch | Performance improvement | `perf: cache timestamp formatting` |
| `deps` | Patch | Dependency updates | `deps: update httpz to 0.5.0` |
| `docs` | Patch | Documentation only | `docs: add migration guide` |

### Types that DON'T Trigger Releases

| Type | When to Use | Example |
|------|-------------|---------|
| `chore` | Maintenance tasks | `chore: update .gitignore` |
| `ci` | CI/CD changes | `ci: add caching to workflow` |
| `test` | Adding/updating tests | `test: add fuzz tests for formatters` |
| `refactor` | Code refactoring (no behavior change) | `refactor: extract constants module` |
| `style` | Code style/formatting | `style: apply zig fmt` |
| `build` | Build system changes | `build: update build.zig` |

### Breaking Changes

For breaking changes, add `!` after the type or include `BREAKING CHANGE:` in the footer:

```bash
# Using ! suffix
feat!: change default format to JSON

# Using footer
feat: change default format to JSON

BREAKING CHANGE: Default output format is now JSON instead of logfmt
```

**Note**: Before v1.0.0, breaking changes bump the minor version (0.x.0) instead of major.

### Examples

#### Feature (Minor Bump)
```bash
git commit -m "feat: add support for OpenTelemetry trace context"
```

#### Bug Fix (Patch Bump)
```bash
git commit -m "fix: prevent buffer overflow for large headers"
```

#### Breaking Change (Minor Bump before v1.0.0)
```bash
git commit -m "feat!: rename Config.log_query to Config.include_query

BREAKING CHANGE: Config field 'log_query' renamed to 'include_query' for clarity"
```

#### No Release (Maintenance)
```bash
git commit -m "chore: clean up unused imports"
git commit -m "test: increase test coverage for edge cases"
git commit -m "ci: add formatting check to workflow"
```

## Pull Request Process

1. Create a feature branch from `main`
2. Make your changes following the commit guidelines above
3. Ensure all tests pass: `zig build test`
4. Run formatter: `zig fmt .`
5. Push your branch and create a PR
6. After PR is merged, Release Please will automatically:
   - Create a release PR if there are releasable changes
   - Update version numbers
   - Generate changelog
   - Create GitHub release when the release PR is merged

## Development Setup

```bash
# Clone the repository
git clone https://github.com/erwagasore/httpz_logger
cd httpz_logger

# Install Zig 0.15.2
# See: https://ziglang.org/download/

# Run tests
zig build test

# Format code
zig fmt .

# Build
zig build
```

## Testing

- Write unit tests for new functionality
- Add fuzz tests for input validation
- Ensure all tests pass before submitting PR
- Test coverage should not decrease

## Questions?

Feel free to open an issue for questions or discussions!
