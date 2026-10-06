# ADR-0010: Native Zig 0.16.0, target projects on Zig 0.13 through 0.16

**Status:** Accepted
**Date:** 2026-10-06

## Context

ADR-0007 pinned exactly one Zig version, `0.16.0`, for everything: the compiler zentinel is built with, and the compiler that runs the tests of the project being mutation-tested. Projects still on older stable Zig releases were rejected before any work happened, even though zentinel never compiles their code itself — it only parses their sources and runs their own test command.

Those are two different contracts:

- **Native toolchain.** zentinel's own source uses Zig 0.16-only standard-library APIs (`std.Io`, the 0.15 Writer/Reader interfaces, unmanaged `ArrayList`). It builds with exactly one Zig.
- **Target toolchain.** The project under test is compiled and run by *its* Zig through its configured test command. zentinel interacts with that toolchain only through (a) the source grammar it parses, (b) the test-runner and build-summary output it classifies, and (c) command-line flags (`-O<mode>`, `-Doptimize=`, `zig test <file>`) and `ZIG_LOCAL_CACHE_DIR`.

Each of (b) and (c) was verified against the real 0.13.0, 0.14.1, 0.15.2 and 0.16.0 toolchains: the `N passed; M skipped; K failed.` line, the Build Summary `X/Y tests passed` clause, and the default summary-on-failure behavior are present in every one, and the flags are unchanged. (a) differs in one known way: Zig 0.15 removed `usingnamespace` and `async`/`await`, so zentinel's built-in 0.16 parser rejects sources that still use them.

## Decision

1. **Native toolchain stays exactly Zig `0.16.0`.** zentinel builds with it. The version-coupled ZIR backend requires exactly it (`zig_version.isNative`), and widening the target range never widens that gate.
2. **Supported target range is every stable Zig release `0.13.x` through `0.16.x`** (`zig_version.min_target_minor`/`max_target_minor`). Pre-release/dev builds, `0.12` and older, and `0.17+` are rejected. A range by minor is used instead of an allowlist of patches because patch releases do not change the grammar or the classified output; CI exercises the latest patch of each minor.
3. **The target is declared, never inferred.** `[zig] version` must be an exact stable release inside the range (default `"0.16.0"`). `run`, `check` and `doctest` require the discovered `zig version` to equal it exactly; any disagreement is `ZNTL_ZIG_UNSUPPORTED_VERSION`. `zentinel init` may write the discovered in-range version into a *new* config, after which it is explicit.
4. **Discovery matches execution.** `zig version` runs from the effective project root with the same minimal environment as test commands, so the validated compiler is the one that runs the tests (including per-directory toolchain shims). There is no config key for a Zig executable path: the toolchain is selected through `PATH`.
5. **The grammar limitation fails fast.** A 0.13/0.14 source using `usingnamespace` or `async`/`await` aborts with `ZNTL_BACKEND_PARSE_ERROR` plus a hint to add the file to `[project] exclude`; zentinel never guesses at an unparseable file.

ADR-0007 is superseded by this ADR.

## Alternatives Considered

- **Keep a single pinned version (ADR-0007).** Rejected: it blocks every project not on the newest Zig, although zentinel's coupling to the target toolchain is narrow and verified.
- **Backport zentinel itself to build with Zig 0.13.** Rejected: it would fork the whole codebase off the 0.15/0.16 standard library for no target-side benefit.
- **Allowlist exact patch releases.** Rejected: every new patch release would need a code change without any behavioral difference to justify it.
- **A `zig.executable` config key.** Rejected: it adds a config-controlled binary path, a new execution surface, when `PATH` already selects the toolchain.
- **Skip unparseable files instead of failing.** Rejected: silently shrinking the mutation set would misreport coverage; an explicit `exclude` keeps the report honest.

## Consequences

**Positive.** Projects on Zig 0.13 through 0.16 can be mutation-tested by a single zentinel build. Report evidence and cache keys name the exact target compiler that ran, so results never mix across toolchains.

**Negative.** The repository must verify the classified output and flags against each supported minor (`scripts/e2e-zig-matrix.sh`, the `target-zig-matrix` CI job) and extend that matrix when the range moves. Zig 0.13 through 0.15 receive no upstream fixes. 0.13/0.14 sources that use `usingnamespace` or `async`/`await` must be excluded from mutation.
