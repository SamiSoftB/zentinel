#!/usr/bin/env bash
# Download, verify, and unpack one official Zig release into /opt/zig-<version>.
#
# Usage: install-zig.sh <version> <tarball-name> <sha256>
#
# Verification is two independent checks, both mandatory:
#   1. the SHA-256 pinned in docker/dev.Dockerfile (from ziglang.org
#      download/index.json), and
#   2. the release's minisign signature against Zig's published public key
#      ($ZIG_MINISIGN_PUBKEY).
# Any mismatch aborts the image build; nothing unverified is ever extracted.
set -euo pipefail

version="$1"
tarball="$2"
sha256="$3"
: "${ZIG_MINISIGN_PUBKEY:?ZIG_MINISIGN_PUBKEY must be set}"

base="https://ziglang.org/download/${version}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl --proto '=https' --tlsv1.2 -fsSL -o "$work/$tarball" "$base/$tarball"
curl --proto '=https' --tlsv1.2 -fsSL -o "$work/$tarball.minisig" "$base/$tarball.minisig"

printf '%s  %s\n' "$sha256" "$work/$tarball" | sha256sum -c -
minisign -V -P "$ZIG_MINISIGN_PUBKEY" -m "$work/$tarball" -x "$work/$tarball.minisig"

mkdir -p "/opt/zig-${version}"
tar -xJf "$work/$tarball" -C "/opt/zig-${version}" --strip-components=1 --no-same-owner
"/opt/zig-${version}/zig" version | grep -qx "$version"
