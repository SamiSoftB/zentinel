#!/usr/bin/env bash
# End-to-end target-toolchain matrix (docs/ZIG_VERSION_POLICY.md, ADR-0010).
#
# Builds zentinel once with the native Zig (0.16.0, first `zig` on PATH), then
# mutation-tests the portable fixture project test/fixtures/projects/zig_compat_sample
# under each requested TARGET toolchain and asserts the report proves that
# toolchain actually ran.
#
# Usage:
#   scripts/e2e-zig-matrix.sh                      # 0.13.0 0.14.1 0.15.2 0.16.0
#   scripts/e2e-zig-matrix.sh 0.13.0 0.15.2        # a subset
#
# Toolchain lookup, per version <v> (first match wins):
#   1. $ZIG_TOOLCHAINS_DIR/zig-<v>/zig   (the dev image sets ZIG_TOOLCHAINS_DIR=/opt)
#   2. the `zig` already on PATH, if `zig version` prints exactly <v> (CI's setup-zig)
# A version with no matching toolchain is a hard failure, never a silent skip.
#
# Requires: jq. Runs offline. Locally: scripts/docker-dev.sh scripts/e2e-zig-matrix.sh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

fixture="test/fixtures/projects/zig_compat_sample"
versions=("$@")
if [[ ${#versions[@]} -eq 0 ]]; then
  versions=(0.13.0 0.14.1 0.15.2 0.16.0)
fi

fail() {
  printf 'e2e-zig-matrix: FAIL: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null || fail "jq is required"

# Build zentinel with the native toolchain. Skipped when ZENTINEL_BIN points at an
# already-built binary (CI builds before switching the active toolchain).
zentinel_bin="${ZENTINEL_BIN:-}"
if [[ -z "$zentinel_bin" ]]; then
  zig build
  zentinel_bin="$repo_root/zig-out/bin/zentinel"
fi
[[ -x "$zentinel_bin" ]] || fail "zentinel binary not found at $zentinel_bin"

toolchain_dir() {
  local v="$1"
  if [[ -n "${ZIG_TOOLCHAINS_DIR:-}" && -x "$ZIG_TOOLCHAINS_DIR/zig-$v/zig" ]]; then
    printf '%s\n' "$ZIG_TOOLCHAINS_DIR/zig-$v"
    return 0
  fi
  if command -v zig >/dev/null && [[ "$(zig version)" == "$v" ]]; then
    dirname "$(command -v zig)"
    return 0
  fi
  return 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

write_config() {
  # $1 = project dir, $2 = [zig] version
  cat >"$1/zentinel.toml" <<EOF
[project]
name = "zig_compat_sample"

[zig]
version = "$2"

[test]
commands = ["zig build test"]
timeout_ms = 120000
EOF
}

for v in "${versions[@]}"; do
  tc="$(toolchain_dir "$v")" || fail "no Zig $v toolchain (set ZIG_TOOLCHAINS_DIR or put Zig $v on PATH)"
  printf '== e2e-zig-matrix: target Zig %s (%s) ==\n' "$v" "$tc"

  proj="$work/$v"
  cp -R "$fixture" "$proj"
  write_config "$proj" "$v"

  # 1. Positive: the run completes under the target toolchain and the report
  #    names it. --no-cache keeps verdicts honest across repeated runs.
  report="$work/$v.report.json"
  (cd "$proj" && PATH="$tc:$PATH" "$zentinel_bin" run --report json --no-cache --quiet >"$report") ||
    fail "Zig $v: zentinel run exited non-zero"
  status="$(jq -r '.run.status' "$report")"
  zig_label="$(jq -r '.run.zig_version' "$report")"
  killed="$(jq -r '.summary.killed' "$report")"
  survived="$(jq -r '.summary.survived' "$report")"
  [[ "$status" == "completed" ]] || fail "Zig $v: run.status=$status"
  [[ "$zig_label" == "$v" ]] || fail "Zig $v: run.zig_version=$zig_label"
  [[ "$killed" -ge 1 ]] || fail "Zig $v: expected >= 1 killed mutant, got $killed"
  [[ "$survived" -ge 1 ]] || fail "Zig $v: expected >= 1 surviving mutant, got $survived"
  printf 'ok: completed, zig_version=%s, killed=%s, survived=%s\n' "$zig_label" "$killed" "$survived"

  # 2. Negative: a config declaring a different supported version is a
  #    mismatch (exit 2, ZNTL_ZIG_UNSUPPORTED_VERSION), never a silent run.
  other="0.16.0"
  [[ "$v" == "0.16.0" ]] && other="0.13.0"
  write_config "$proj" "$other"
  set +e
  err="$(cd "$proj" && PATH="$tc:$PATH" "$zentinel_bin" run --no-cache --quiet 2>&1 >/dev/null)"
  code=$?
  set -e
  [[ $code -eq 2 ]] || fail "Zig $v: mismatched [zig] version should exit 2, got $code"
  grep -q 'ZNTL_ZIG_UNSUPPORTED_VERSION' <<<"$err" || fail "Zig $v: mismatch diagnostic missing: $err"
  printf 'ok: declared %s vs discovered %s rejected\n' "$other" "$v"
  write_config "$proj" "$v"

  # 3. Negative: the version-coupled ZIR backend stays native-only.
  if [[ "$v" != "0.16.0" ]]; then
    printf '\n[backend]\nexperimental = ["zir"]\n' >>"$proj/zentinel.toml"
    set +e
    err="$(cd "$proj" && PATH="$tc:$PATH" "$zentinel_bin" list-mutants --backend zir 2>&1 >/dev/null)"
    code=$?
    set -e
    [[ $code -eq 2 ]] || fail "Zig $v: --backend zir should be refused, got exit $code"
    grep -q 'requires Zig 0.16.0' <<<"$err" || fail "Zig $v: ZIR refusal diagnostic missing: $err"
    printf 'ok: --backend zir refused\n'
    write_config "$proj" "$v"
  fi

  # 4. Grammar limitation (0.13/0.14 only): a `usingnamespace` file is legal for
  #    the target compiler but not for zentinel's 0.16 parser; the run must fail
  #    fast with an actionable exclude hint rather than mis-parse.
  case "$v" in
    0.13.* | 0.14.*)
      printf 'pub usingnamespace @import("std");\n' >"$proj/src/legacy.zig"
      set +e
      err="$(cd "$proj" && PATH="$tc:$PATH" "$zentinel_bin" list-mutants 2>&1 >/dev/null)"
      code=$?
      set -e
      rm -f "$proj/src/legacy.zig"
      [[ $code -eq 2 ]] || fail "Zig $v: usingnamespace file should exit 2, got $code"
      grep -q 'ZNTL_BACKEND_PARSE_ERROR' <<<"$err" || fail "Zig $v: parse error missing: $err"
      grep -q '\[project\] exclude' <<<"$err" || fail "Zig $v: exclude hint missing: $err"
      printf 'ok: usingnamespace file rejected with exclude hint\n'
      ;;
  esac
done

printf 'e2e-zig-matrix: all %d target toolchain(s) passed\n' "${#versions[@]}"
