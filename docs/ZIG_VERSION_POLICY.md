# Zig Version Policy

zentinel distinguishes two Zig toolchains (ADR-0010):

- the **native** toolchain zentinel itself is built with: exactly Zig `0.16.0`;
- the **target** toolchain that compiles and runs the tests of the project being mutation-tested: any stable Zig `0.13.x` through `0.16.x`.

## Policy

| Rule | Requirement |
| --- | --- |
| Native version (build zentinel) | `0.16.0` exactly. |
| Supported target versions | Every stable release `0.13.x`, `0.14.x`, `0.15.x`, `0.16.x` (any patch). |
| Older or newer releases | `0.12` and earlier, and `0.17` and later, are not supported targets. |
| Nightly / dev builds | Never supported, even inside the range (`0.16.0-dev.*`). |
| Declared target | `[zig] version` names the exact target release; discovery must match it. |
| ZIR experimental backend | Native `0.16.0` only, regardless of the target range. |
| CI | Builds natively with `0.16.0`; exercises the latest patch of every supported target minor. |

## Rationale

zentinel never compiles the target project's code itself. It parses the sources, rewrites them, and runs the project's own test command with the project's own Zig. Its coupling to the target toolchain is therefore narrow and explicitly verified for every supported minor:

- **Classified output.** The test-runner line `N passed; M skipped; K failed.`, the `zig build` Build Summary `X/Y tests passed` clause, and summary-on-failure by default are present in Zig 0.13.0, 0.14.1, 0.15.2, and 0.16.0. The exact shapes are pinned in `test/runner_baseline_test.zig` from real captures.
- **Command-line surface.** `-O<mode>` (for `zig test`), `-Doptimize=<mode>` (for `zig build`), `zig test <file>` selection, and `ZIG_LOCAL_CACHE_DIR` are unchanged across the range.
- **Source grammar.** zentinel parses target sources with its built-in Zig `0.16.0` `std.zig.Ast`. Zig `0.15` removed `usingnamespace` and `async`/`await`; a `0.13`/`0.14` source that still uses them cannot be parsed (see below).

zentinel's own source depends on Zig `0.16.0`-only standard-library APIs, so the native toolchain stays a single pin. The target range is a product contract, not a lookup result: it moves only through a new ADR, and a supported version is never inferred from examples, installed toolchains, or unrelated documentation.

## Version Detection

Commands that run Zig (`run`, `check`, `doctest`) run:

```bash
zig version
```

Discovery runs Zig exactly the way test commands do: with the working directory set to the effective project root and the minimal command environment (`docs/SANDBOX_SECURITY.md`). The compiler that is validated and recorded in reports and cache keys is therefore the one that runs the tests, including when a per-directory toolchain shim selects the compiler from the project's `build.zig.zon`.

The version check must:

- parse the Zig version;
- classify it against the supported target range;
- require it to equal the configured `[zig] version` exactly;
- fail fast (exit 2, `ZNTL_ZIG_UNSUPPORTED_VERSION` or `ZNTL_ZIG_NOT_FOUND`) otherwise;
- use a bounded discovery timeout and bounded output, and classify a timeout, execution failure, or oversized output as Zig not found;
- include remediation text.

Example diagnostics:

```text
error[ZNTL_ZIG_UNSUPPORTED_VERSION]: unsupported Zig version 0.12.1; zentinel supports Zig 0.13.x through 0.16.x
error[ZNTL_ZIG_UNSUPPORTED_VERSION]: detected Zig 0.13.0 but [zig] version is "0.16.0"; put Zig 0.16.0 first on PATH or set [zig] version = "0.13.0"
```

The native version and the target range live in one version-policy module (`src/zig_version.zig`). Select the target toolchain with `PATH`; zentinel has no config key for a Zig executable path.

## Config Contract

`[zig] version` declares the target release the project's tests run on:

```toml
[zig]
version = "0.13.0"
```

The value must be an exact stable release inside the supported range and defaults to the native `"0.16.0"`. Aliases such as `latest` or `latest-stable` are rejected because they obscure which compiler version produced reports and cache keys. `zentinel init` writes the discovered Zig version when it is an older supported target, so `init` followed by `run` works without a hand edit; after that the value is explicit.

## Projects on Zig 0.13 and 0.14: grammar limitation

Zig `0.13` and `0.14` still accept `usingnamespace` and `async`/`await`, which zentinel's `0.16.0` parser rejects. A run or listing that includes such a file fails fast with `ZNTL_BACKEND_PARSE_ERROR`, naming the file, plus a hint to add it to `[project] exclude`. zentinel never guesses at or silently skips an unparseable file, so the mutation report stays honest about what was covered.

## CI Contract

CI must:

- build zentinel with Zig `0.16.0` and print `zig version`;
- run the full deterministic suite natively (`scripts/ci.sh`);
- for each supported target minor (latest patch: `0.13.0`, `0.14.1`, `0.15.2`, `0.16.0`), switch the active toolchain and run `scripts/e2e-zig-matrix.sh`, which asserts the report names that target and that mutants are killed and survive as expected;
- extend that matrix whenever the target range moves.

Locally, `scripts/docker-dev.sh scripts/e2e-zig-matrix.sh` runs the same matrix in the dev image, which carries all four toolchains.

## Experimental Backends

ZIR is more tightly coupled to compiler internals than the AST backend. It must include:

- adapter version checks keyed to the **native** version (`zig_version.isNative`), never the target range;
- clear diagnostics for unsupported compiler internals;
- no fallback to approximate source mapping.

Experimental backend breakage must not affect AST backend stability.

## Upstream Support

Zig `0.13` through `0.15` no longer receive upstream fixes. Supporting them as mutation-testing targets does not change that; prefer the newest supported release where possible.
