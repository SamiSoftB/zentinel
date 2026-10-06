# syntax=docker/dockerfile:1
#
# Local development/test image for zentinel (see CONTRIBUTING.md).
#
# zentinel itself builds with its native Zig (0.16.0); the other toolchains are
# the supported *target* range it can mutation-test (docs/ZIG_VERSION_POLICY.md):
#   /opt/zig-0.16.0  (default on PATH)   /opt/zig-0.15.2   /opt/zig-0.14.1   /opt/zig-0.13.0
#
# Supply-chain policy:
#   - base image pinned by digest (a dated tag >= 60 days old at pin time)
#   - apt resolves against the matching snapshot.debian.org date and every
#     package is pinned to an exact version
#   - every Zig tarball is checked against a pinned SHA-256 AND its minisign
#     signature (docker/install-zig.sh); download tools stay in the fetch stage
#
# Build/run through scripts/docker-dev.sh.

ARG DEBIAN_IMAGE=debian:bookworm-20260803-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241
ARG DEBIAN_SNAPSHOT=20260803T000000Z

# --- fetch: download and verify the Zig toolchains ---------------------------
FROM ${DEBIAN_IMAGE} AS fetch
ARG DEBIAN_SNAPSHOT
ARG TARGETARCH
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

RUN sed -i \
      -e "s|^URIs: http://deb.debian.org/debian-security$|URIs: http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}|" \
      -e "s|^URIs: http://deb.debian.org/debian$|URIs: http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}|" \
      /etc/apt/sources.list.d/debian.sources \
 && apt-get -o Acquire::Check-Valid-Until=false update \
 && apt-get install -y --no-install-recommends \
      ca-certificates=20230311+deb12u1 \
      curl=7.88.1-10+deb12u15 \
      xz-utils=5.4.1-1+deb12u1 \
      minisign=0.11-1 \
 && rm -rf /var/lib/apt/lists/*

# Zig's release-signing key, as published on https://ziglang.org/download/.
ENV ZIG_MINISIGN_PUBKEY=RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U
COPY docker/install-zig.sh /usr/local/bin/install-zig

# version | x86_64-linux tarball + sha256 | aarch64-linux tarball + sha256
# (ziglang.org download/index.json; note the arch/os order flipped in 0.14.1).
RUN case "${TARGETARCH:-amd64}" in \
      amd64) \
        install-zig 0.13.0 zig-linux-x86_64-0.13.0.tar.xz d45312e61ebcc48032b77bc4cf7fd6915c11fa16e4aad116b66c9468211230ea; \
        install-zig 0.14.1 zig-x86_64-linux-0.14.1.tar.xz 24aeeec8af16c381934a6cd7d95c807a8cb2cf7df9fa40d359aa884195c4716c; \
        install-zig 0.15.2 zig-x86_64-linux-0.15.2.tar.xz 02aa270f183da276e5b5920b1dac44a63f1a49e55050ebde3aecc9eb82f93239; \
        install-zig 0.16.0 zig-x86_64-linux-0.16.0.tar.xz 70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00 ;; \
      arm64) \
        install-zig 0.13.0 zig-linux-aarch64-0.13.0.tar.xz 041ac42323837eb5624068acd8b00cd5777dac4cf91179e8dad7a7e90dd0c556; \
        install-zig 0.14.1 zig-aarch64-linux-0.14.1.tar.xz f7a654acc967864f7a050ddacfaa778c7504a0eca8d2b678839c21eea47c992b; \
        install-zig 0.15.2 zig-aarch64-linux-0.15.2.tar.xz 958ed7d1e00d0ea76590d27666efbf7a932281b3d7ba0c6b01b0ff26498f667f; \
        install-zig 0.16.0 zig-aarch64-linux-0.16.0.tar.xz ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac

# --- dev: the image builds and tests run in ----------------------------------
FROM ${DEBIAN_IMAGE} AS dev
ARG DEBIAN_SNAPSHOT
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# git: `zentinel run --changed-only/--diff`; jq: e2e report assertions.
RUN sed -i \
      -e "s|^URIs: http://deb.debian.org/debian-security$|URIs: http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}|" \
      -e "s|^URIs: http://deb.debian.org/debian$|URIs: http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}|" \
      /etc/apt/sources.list.d/debian.sources \
 && apt-get -o Acquire::Check-Valid-Until=false update \
 && apt-get install -y --no-install-recommends \
      ca-certificates=20230311+deb12u1 \
      git=1:2.39.5-0+deb12u3 \
      jq=1.6-2.1+deb12u2 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=fetch /opt /opt

# The container runs as the invoking host uid (scripts/docker-dev.sh), which has
# no passwd entry, so HOME and the Zig caches are world-writable sticky dirs.
# Named volumes mounted at /cache (global cache) and /work/.zig-cache (the
# repository's local cache, kept off the slow host bind mount) inherit these
# permissions on first use.
RUN mkdir -p /home/dev /cache/zig /work/.zig-cache \
 && chmod 1777 /home/dev /cache /cache/zig /work/.zig-cache
ENV HOME=/home/dev \
    ZIG_GLOBAL_CACHE_DIR=/cache/zig \
    ZIG_TOOLCHAINS_DIR=/opt \
    PATH=/opt/zig-0.16.0:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /work
