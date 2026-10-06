# AST Backend

The AST backend is zentinel's stable default mutation backend.

## Purpose

The AST backend parses Zig source, identifies syntactic mutation candidates, maps them to source spans, and emits source-text replacements. It is designed to be predictable, debuggable, and suitable for normal CI use.

## Stability Expectation

| Property | Requirement |
| --- | --- |
| Default status | Enabled by default once Phase 1 is complete. |
| Report stability | Stable fields and operator names. |
| Source mapping | Required for every mutant. |
| Zig version coupling | Parses with the native Zig `0.16.0` grammar for every supported target (`0.13.x`-`0.16.x`, ADR-0010). |
| Failure mode | Clear diagnostic; no silent candidate loss. |

## Architecture

```text
source file
  -> lexer/parser
  -> AST traversal
  -> candidate recognizers
  -> mutator-specific validation
  -> source span extraction
  -> replacement rendering
  -> shared Mutant model
```

The backend must keep parsing and mutation generation separate:

- parser builds syntax representation
- recognizers find candidate nodes
- mutators validate contexts and replacements
- renderer emits exact source replacement

## Parser API Surface

The parser layer is built on Zig's standard-library parser (`std.zig.Ast`) for the pinned Zig `0.16.0`, not a hand-rolled parser. Because `std.zig.Ast` node tags and accessors change across Zig releases, the exact API surface is a pinned contract, not an assumption:

- The `std.zig.Ast` API surface is verified against an installed Zig `0.16.0`, recording the exact entry points used: the parse function, the node tag enumeration, token/source-location accessors, and any node-data accessors needed for span extraction.
- The parser adapter wraps these entry points behind zentinel's own interface so a future Zig pin change is isolated to one module.
- If the pinned `std.zig.Ast` API is unavailable or does not provide what a recognizer needs, the work stops and the limitation is recorded explicitly instead of guessing or silently degrading source mapping.

### Older target grammars

The parser is always the native `0.16.0` `std.zig.Ast`, also for projects on an older supported target Zig (ADR-0010). Target grammars `0.13`-`0.16` differ from it in one known way: Zig `0.15` removed `usingnamespace` and `async`/`await`. A `0.13`/`0.14` source that still uses them fails with `ZNTL_BACKEND_PARSE_ERROR` naming the file, plus a hint to add it to `[project] exclude`; the file is never skipped silently. All other differences between those releases are semantic, not grammatical, so the parser accepts them.

## Source Mapping Strategy

Every AST mutant must include:

- project-relative path
- byte start and byte end offsets
- 1-based line and column range
- original source text
- replacement source text

Line and column values are for humans. Byte offsets are authoritative for patching.

## Mutation Generation Strategy

The AST backend generates one mutant per operator replacement. It does not combine multiple changes.

Example:

```zig
return a + b;
```

emits:

```json
{
  "operator": "arithmetic_add_sub",
  "original": "+",
  "replacement": "-"
}
```

## Risks

| Risk | Mitigation |
| --- | --- |
| Zig grammar changes | Native Zig `0.16.0` parser, a verified target range, and a fail-fast exclude hint for removed `0.13`/`0.14` syntax. |
| Precedence changes | Renderer tests for each operator. |
| Same-file tests mutated accidentally | AST traversal excludes `test` bodies by default. |
| Formatting churn | Minimal token replacement only. |
| Context-free invalid mutants | Classify compile errors; add semantic filters only with tests. |

## Testing Requirements

AST backend tests must cover:

- every stable operator in `docs/MUTATOR_SPEC.md`
- source span accuracy
- line/column accuracy
- same-file test exclusion
- deterministic candidate ordering
- compile-error classification for `may_fail` operators
- report serialization from generated mutants

## Future Roadmap

AST backend evolution:

1. Phase 1 syntactic operators.
2. Phase 2 Zig-native semantic operators with conservative validation.
3. Phase 3 performance improvements through parsed-file caching.
4. Phase 5 parity tests against ZIR where semantic mapping overlaps.

The AST backend remains the stable default even after experimental backends exist.
