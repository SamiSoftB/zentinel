# Changelog

All notable changes to zentinel are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While zentinel is pre-1.0, the public surface (CLI, config, report schemas) may
change between minor versions; breaking changes are called out here.

## [Unreleased]

### Added

- **Projects on Zig 0.13 through 0.16.** zentinel still builds with Zig 0.16.0,
  but now mutation-tests projects on any stable Zig `0.13.x`–`0.16.x`
  (ADR-0010, superseding ADR-0007). Declare the target in `[zig] version`
  (e.g. `"0.13.0"`); `run`, `check` and `doctest` require the discovered
  `zig version` to match it exactly, and `zentinel init` writes the discovered
  in-range version. On 0.13/0.14 projects, files that use `usingnamespace` or
  `async`/`await` (which zentinel's 0.16 parser cannot read) fail fast with a
  hint to add them to `[project] exclude`. The experimental ZIR backend remains
  Zig 0.16.0-only.
- `scripts/e2e-zig-matrix.sh` and a `target-zig-matrix` CI job (actions pinned
  to commit SHAs) run an end-to-end mutation run against Zig 0.13.0, 0.14.1,
  0.15.2 and 0.16.0 using the portable fixture
  `test/fixtures/projects/zig_compat_sample`.
- `docker/dev.Dockerfile` and `scripts/docker-dev.sh`: an offline,
  supply-chain-pinned dev image (digest-pinned base, snapshot-pinned apt
  packages, SHA-256 + minisign-verified Zig toolchains) for building and
  testing where Zig cannot run natively.

- `zentinel init` now writes a **commented** config — each section and key has a
  short inline `#` comment explaining its purpose.
- A real JSON-Schema validation test wires `schemas/report.v1.schema.json` and
  `schemas/doctest.report.v1.schema.json` into the suite: rendered reports are
  validated against the published schemas, with negative cases proving the
  validator rejects malformed reports.

### Changed

- CI now runs on a Linux/macOS/Windows matrix (Windows is advisory and
  non-blocking) instead of Linux only.
- `zig version` discovery now runs from the effective project root with the
  minimal command environment and bounded output, so the compiler zentinel
  validates and records is the one the tests run (previously it used the
  process cwd and the full developer environment).
- `ZNTL_ZIG_UNSUPPORTED_VERSION` now also covers a supported Zig that differs
  from the configured `[zig] version`; its messages name the supported range
  (`0.13.x through 0.16.x`) instead of a single required version.


## [0.1.0] - 2026-06-24

Initial public release. zentinel performs mutation testing for Zig projects:
it applies small, targeted source mutations, runs your test suite against each,
and reports which mutants survived — the gaps your tests don't catch.

### Added

- **Mutation pipeline** with a stable AST backend and an experimental ZIR
  cross-check backend.
- **Mutation operators**: `arithmetic_add_sub`, `arithmetic_mul_div`,
  `equality_swap`, `comparison_boundary`, `logical_and_or`, `boolean_literal`,
  selected per project in `zentinel.toml`. See `docs/MUTATOR_SPEC.md`.
- **CLI commands**: `init`, `check`, `list-mutants`, `run`, `doctest`,
  `version`, and the opt-in advisory AI commands `explain`, `suggest`, and
  `review-tests`. See `docs/CLI_SPEC.md`.
- **Diff-scoped runs**: `--changed-only`, `--diff <ref>`, and
  `--scope-files` narrow which files are mutated without changing any verdict.
- **Reports** in `text`, `json`, `jsonl`, and `junit` formats, with versioned
  JSON schemas under `schemas/`. See `docs/REPORT_FORMAT.md`.
- **Doctest verification** (`zentinel doctest`): compiles and runs the code
  examples in your docs, with an optional `--mutate` mode. See
  `docs/DOCTEST_SPEC.md`.
- **Sandboxing**: per-worker isolated mutant workspaces, a minimal environment
  allowlist, and report/cache writes confined to the project root with
  symlink-escape rejection. See `docs/SANDBOX_SECURITY.md`.
- **Opt-in AI features**, disabled by default, with a redaction layer on
  outbound context and an audit trail. The deterministic core never requires a
  network.
- MIT license and a CI workflow gating formatting, build, tests, and a
  self-dogfood run.

### Notes

- Requires **Zig 0.16.0** exactly; see `docs/ZIG_VERSION_POLICY.md`.
- Result-cache reuse across runs (skipping unchanged mutants) is not yet wired;
  see `docs/PERFORMANCE_STRATEGY.md` and `docs/ROADMAP.md`.

[Unreleased]: https://github.com/oly-wan-kenobi/zentinel/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/oly-wan-kenobi/zentinel/releases/tag/v0.1.0
