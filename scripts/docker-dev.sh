#!/usr/bin/env bash
# Run a command inside the zentinel dev container (docker/dev.Dockerfile).
#
# Usage:
#   scripts/docker-dev.sh <command> [args...]
#   scripts/docker-dev.sh scripts/ci.sh
#   scripts/docker-dev.sh scripts/e2e-zig-matrix.sh
#
# The repository is bind-mounted at /work and the command runs as the invoking
# host uid/gid, so build outputs stay owned by you. The container has no network
# (--network none): the image already carries every toolchain, and CI is
# network-independent by contract (docs/CI_STRATEGY.md). Zig's global cache lives
# in the named volume `zentinel-zig-cache`, and the repository's local
# `.zig-cache` in `zentinel-local-cache`: both survive between runs, and keeping
# the local cache off the host bind mount avoids its slow per-file I/O.
#
# Environment:
#   ZENTINEL_DEV_IMAGE   image tag to build/use (default: zentinel-dev:local)
#   ZENTINEL_DEV_REBUILD set to 1 to force an image rebuild
#   ZENTINEL_DEV_MOUNTS  extra `docker run` args, e.g. a read-only target mount:
#                        "-v $HOME/proj:/target:ro"
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image="${ZENTINEL_DEV_IMAGE:-zentinel-dev:local}"

if [[ $# -eq 0 ]]; then
  echo "usage: scripts/docker-dev.sh <command> [args...]" >&2
  exit 2
fi

if [[ "${ZENTINEL_DEV_REBUILD:-0}" == "1" ]] || ! docker image inspect "$image" >/dev/null 2>&1; then
  docker build -f "$repo_root/docker/dev.Dockerfile" -t "$image" "$repo_root"
fi

extra_mounts=()
if [[ -n "${ZENTINEL_DEV_MOUNTS:-}" ]]; then
  # Word-splitting is intended: the variable holds docker run arguments.
  read -r -a extra_mounts <<<"$ZENTINEL_DEV_MOUNTS"
fi

tty_flags=()
if [[ -t 0 && -t 1 ]]; then
  tty_flags=(-it)
fi

# `${a[@]+"${a[@]}"}` keeps empty arrays safe under `set -u` on macOS bash 3.2.
exec docker run --rm ${tty_flags[@]+"${tty_flags[@]}"} \
  --network none \
  --user "$(id -u):$(id -g)" \
  -v "$repo_root:/work" \
  -v zentinel-zig-cache:/cache \
  -v zentinel-local-cache:/work/.zig-cache \
  ${extra_mounts[@]+"${extra_mounts[@]}"} \
  -w /work \
  "$image" "$@"
