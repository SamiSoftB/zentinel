// Layer: deterministic_core
//
// Zig version policy (docs/ZIG_VERSION_POLICY.md, ADR-0007, ADR-0010). This is the
// single version-policy module. It owns two compiled-in facts:
//
//   - the NATIVE Zig version zentinel itself builds with, which the
//     version-coupled ZIR backend also requires exactly, and
//   - the supported TARGET range: the stable Zig releases whose projects zentinel
//     can mutation-test (0.13.x through 0.16.x).
//
// Discovery itself (running `zig version`) is a side effect performed by the
// presentation adapter, which passes the result in as `Discovery` data so this
// module stays pure and testable without invoking the real Zig binary.
const std = @import("std");

/// The native Zig version: zentinel builds with it, and the version-coupled ZIR
/// backend requires exactly it. Also the `[zig] version` config default.
pub const supported_version = "0.16.0";

/// Supported target range (ADR-0010): any stable `0.N.P` release with
/// `min_target_minor <= N <= max_target_minor`, any patch. Patch releases do not
/// change the grammar or the test-runner output zentinel classifies.
pub const min_target_minor: u16 = 13;
pub const max_target_minor: u16 = 16;

/// Human label for the supported target range, used in diagnostics.
pub const supported_range_label = "0.13.x through 0.16.x";

/// First minor whose grammar matches zentinel's built-in 0.16 parser. Zig 0.15
/// removed `usingnamespace` and `async`/`await`; older targets may still use them.
const native_grammar_min_minor: u16 = 15;

/// Result of attempting to discover the local Zig version. Produced by the
/// adapter; consumed by the pure classification below.
pub const Discovery = union(enum) {
    not_found,
    version: []const u8,
};

pub const Status = enum {
    supported,
    not_found,
    unsupported,
    malformed,
    /// A supported toolchain that differs from the project's `[zig] version`.
    mismatch,
};

/// Public diagnostic codes for Zig version failures (docs/ERROR_CODES.md).
pub const Code = enum {
    none,
    not_found,
    unsupported,

    pub fn token(self: Code) []const u8 {
        return switch (self) {
            .none => "",
            .not_found => "ZNTL_ZIG_NOT_FOUND",
            .unsupported => "ZNTL_ZIG_UNSUPPORTED_VERSION",
        };
    }
};

pub const Version = struct {
    major: u16,
    minor: u16,
    patch: u16,
    /// True when the string carries a pre-release or build suffix (`-`/`+`),
    /// e.g. a nightly `0.16.0-dev.*`. Such builds are never a supported release.
    pre: bool,
};

/// Parse `MAJOR.MINOR.PATCH` with an optional `-pre`/`+build` suffix. Returns
/// null for anything that is not three numeric components.
pub fn parseVersion(s: []const u8) ?Version {
    var core = s;
    var pre = false;
    if (std.mem.indexOfAny(u8, s, "-+")) |idx| {
        core = s[0..idx];
        pre = true;
    }
    var it = std.mem.splitScalar(u8, core, '.');
    const maj = it.next() orelse return null;
    const min = it.next() orelse return null;
    const pat = it.next() orelse return null;
    if (it.next() != null) return null;
    const major = std.fmt.parseInt(u16, maj, 10) catch return null;
    const minor = std.fmt.parseInt(u16, min, 10) catch return null;
    const patch = std.fmt.parseInt(u16, pat, 10) catch return null;
    return .{ .major = major, .minor = minor, .patch = patch, .pre = pre };
}

const native = parseVersion(supported_version).?;

/// The single source of truth for "is this a supported target release": a stable
/// (no pre-release/build suffix) `0.N.P` inside the target range. Operates on an
/// already-parsed `Version` so `classify` (which parses to detect `malformed`
/// first) does not parse twice.
fn versionIsSupported(parsed: Version) bool {
    return parsed.major == 0 and
        parsed.minor >= min_target_minor and
        parsed.minor <= max_target_minor and
        !parsed.pre;
}

fn versionIsNative(parsed: Version) bool {
    return parsed.major == native.major and parsed.minor == native.minor and
        parsed.patch == native.patch and !parsed.pre;
}

/// Whether `v` names a supported target release. Validates the `[zig] version`
/// config value, which must be an exact stable release (never an alias).
pub fn isSupportedVersion(v: []const u8) bool {
    const parsed = parseVersion(v) orelse return false;
    return versionIsSupported(parsed);
}

/// Whether the discovered toolchain is exactly the native version. Gates the
/// version-coupled ZIR backend, which must not widen with the target range.
pub fn isNative(discovery: Discovery) bool {
    return switch (discovery) {
        .not_found => false,
        .version => |v| if (parseVersion(v)) |p| versionIsNative(p) else false,
    };
}

/// True when a supported target version predates the grammar of zentinel's
/// built-in 0.16 parser (Zig 0.13/0.14), so its sources may use `usingnamespace`
/// or `async`/`await` that zentinel cannot parse. Drives an actionable hint on
/// backend parse errors; false for unparseable input.
pub fn predatesNativeGrammar(v: []const u8) bool {
    const parsed = parseVersion(v) orelse return false;
    return versionIsSupported(parsed) and parsed.minor < native_grammar_min_minor;
}

/// Classify a discovery result against the supported target range.
pub fn classify(discovery: Discovery) Status {
    switch (discovery) {
        .not_found => return .not_found,
        .version => |v| {
            const parsed = parseVersion(v) orelse return .malformed;
            return if (versionIsSupported(parsed)) .supported else .unsupported;
        },
    }
}

/// Classify a discovery result against the version a project declares in
/// `[zig] version`. A supported toolchain that is not exactly `expected` is a
/// `mismatch`: report evidence and cache keys must name the compiler that ran,
/// so zentinel never silently tests with a different toolchain than declared.
pub fn classifyExpected(discovery: Discovery, expected: []const u8) Status {
    const status = classify(discovery);
    if (status != .supported) return status;
    return if (std.mem.eql(u8, discovery.version, expected)) .supported else .mismatch;
}

pub fn codeFor(status: Status) Code {
    return switch (status) {
        .supported => .none,
        .not_found => .not_found,
        .unsupported, .malformed, .mismatch => .unsupported,
    };
}

/// Human diagnostic naming the detected version and the supported range.
pub fn message(arena: std.mem.Allocator, status: Status, detected: []const u8) std.mem.Allocator.Error![]const u8 {
    return messageExpected(arena, status, detected, supported_version);
}

/// Like `message`, but a `mismatch` names the project's declared `expected`
/// version and how to resolve the disagreement.
pub fn messageExpected(arena: std.mem.Allocator, status: Status, detected: []const u8, expected: []const u8) std.mem.Allocator.Error![]const u8 {
    return switch (status) {
        .supported => arena.dupe(u8, ""),
        .not_found => std.fmt.allocPrint(arena, "Zig executable not found; zentinel supports Zig {s}", .{supported_range_label}),
        .unsupported => std.fmt.allocPrint(arena, "unsupported Zig version {s}; zentinel supports Zig {s}", .{ detected, supported_range_label }),
        .malformed => std.fmt.allocPrint(arena, "could not parse Zig version '{s}'; zentinel supports Zig {s}", .{ detected, supported_range_label }),
        .mismatch => std.fmt.allocPrint(arena, "detected Zig {s} but [zig] version is \"{s}\"; put Zig {s} first on PATH or set [zig] version = \"{s}\"", .{ detected, expected, expected, detected }),
    };
}

fn detectedOf(discovery: Discovery) []const u8 {
    return switch (discovery) {
        .version => |v| v,
        .not_found => "",
    };
}

/// Rendered stderr status line for `zentinel version`: null when Zig is
/// supported (nothing extra to report), otherwise an `error[CODE]: message`
/// line. `zentinel version` stays exit 0 regardless; `zentinel check` treats
/// the same conditions as fatal.
pub fn statusLine(arena: std.mem.Allocator, discovery: Discovery) std.mem.Allocator.Error!?[]const u8 {
    const status = classify(discovery);
    if (status == .supported) return null;
    const msg = try message(arena, status, detectedOf(discovery));
    return try std.fmt.allocPrint(arena, "error[{s}]: {s}", .{ codeFor(status).token(), msg });
}

/// Return the discovered version only when it is a supported target release.
/// This prevents execution reports from synthesizing a version when Zig is
/// missing or unsupported.
pub fn supportedLabel(discovery: Discovery) ?[]const u8 {
    return switch (discovery) {
        .version => |v| if (isSupportedVersion(v)) v else null,
        .not_found => null,
    };
}

/// Fatal execution-path diagnostic line against the project's declared
/// `expected` version. Empty string means the discovered Zig is exactly the
/// declared supported version; non-empty lines should be printed to stderr and
/// exit 2.
pub fn fatalStatusLine(arena: std.mem.Allocator, discovery: Discovery, expected: []const u8) std.mem.Allocator.Error![]const u8 {
    const status = classifyExpected(discovery, expected);
    if (status == .supported) return "";
    const msg = try messageExpected(arena, status, detectedOf(discovery), expected);
    return std.fmt.allocPrint(arena, "error[{s}]: {s}", .{ codeFor(status).token(), msg });
}

pub fn failureExit(discovery: Discovery, expected: []const u8) u8 {
    return if (classifyExpected(discovery, expected) == .supported) 0 else 2;
}
