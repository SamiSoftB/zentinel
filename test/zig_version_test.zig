const std = @import("std");
const zentinel = @import("zentinel");
const zig_version = zentinel.zig_version;
const harness = @import("support/harness.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const unsupported_snapshot = @embedFile("snapshots/zig_unsupported.txt");

test "native version is 0.16.0 and classifies as supported" {
    try expectEqualStrings("0.16.0", zig_version.supported_version);
    try expectEqual(zig_version.Status.supported, zig_version.classify(.{ .version = "0.16.0" }));
}

test "every stable release in the 0.13-0.16 target range is supported" {
    // All stable releases published in the range (ziglang.org index.json), plus a
    // hypothetical future patch: the range rule accepts any patch of a minor.
    for ([_][]const u8{ "0.13.0", "0.14.0", "0.14.1", "0.15.1", "0.15.2", "0.16.0", "0.16.1" }) |v| {
        try expectEqual(zig_version.Status.supported, zig_version.classify(.{ .version = v }));
        try expect(zig_version.isSupportedVersion(v));
    }
}

test "releases outside the 0.13-0.16 target range are unsupported" {
    for ([_][]const u8{ "0.12.1", "0.11.0", "0.17.0", "1.0.0", "1.13.0" }) |v| {
        try expectEqual(zig_version.Status.unsupported, zig_version.classify(.{ .version = v }));
        try expect(!zig_version.isSupportedVersion(v));
    }
}

test "nightly/dev builds are unsupported even inside the target range" {
    try expectEqual(zig_version.Status.unsupported, zig_version.classify(.{ .version = "0.16.0-dev.123+abcdef" }));
    try expectEqual(zig_version.Status.unsupported, zig_version.classify(.{ .version = "0.15.0-dev.1+abc" }));
    try expect(!zig_version.isSupportedVersion("0.14.1+local"));
}

test "malformed version strings are malformed" {
    try expectEqual(zig_version.Status.malformed, zig_version.classify(.{ .version = "not-a-version" }));
    try expectEqual(zig_version.Status.malformed, zig_version.classify(.{ .version = "0.16" }));
    try expectEqual(zig_version.Status.malformed, zig_version.classify(.{ .version = "" }));
    try expect(!zig_version.isSupportedVersion("latest"));
}

test "missing Zig executable classifies as not_found" {
    try expectEqual(zig_version.Status.not_found, zig_version.classify(.not_found));
}

test "a supported toolchain that differs from the declared version is a mismatch" {
    try expectEqual(zig_version.Status.supported, zig_version.classifyExpected(.{ .version = "0.14.1" }, "0.14.1"));
    try expectEqual(zig_version.Status.mismatch, zig_version.classifyExpected(.{ .version = "0.13.0" }, "0.16.0"));
    try expectEqual(zig_version.Status.mismatch, zig_version.classifyExpected(.{ .version = "0.14.0" }, "0.14.1"));
    // Range and presence failures keep their own status; mismatch is only for
    // two supported versions that disagree.
    try expectEqual(zig_version.Status.unsupported, zig_version.classifyExpected(.{ .version = "0.17.0" }, "0.16.0"));
    try expectEqual(zig_version.Status.not_found, zig_version.classifyExpected(.not_found, "0.13.0"));
}

test "only the exact native release is native (ZIR gate)" {
    try expect(zig_version.isNative(.{ .version = "0.16.0" }));
    for ([_][]const u8{ "0.13.0", "0.14.1", "0.15.2", "0.16.1", "0.16.0-dev.1+abc", "garbage" }) |v| {
        try expect(!zig_version.isNative(.{ .version = v }));
    }
    try expect(!zig_version.isNative(.not_found));
}

test "only 0.13 and 0.14 targets predate the native parser grammar" {
    try expect(zig_version.predatesNativeGrammar("0.13.0"));
    try expect(zig_version.predatesNativeGrammar("0.14.1"));
    try expect(!zig_version.predatesNativeGrammar("0.15.2"));
    try expect(!zig_version.predatesNativeGrammar("0.16.0"));
    try expect(!zig_version.predatesNativeGrammar("0.12.1"));
    try expect(!zig_version.predatesNativeGrammar("nope"));
}

test "status codes map to the public ZNTL tokens" {
    try expectEqualStrings("ZNTL_ZIG_NOT_FOUND", zig_version.codeFor(.not_found).token());
    try expectEqualStrings("ZNTL_ZIG_UNSUPPORTED_VERSION", zig_version.codeFor(.unsupported).token());
    try expectEqualStrings("ZNTL_ZIG_UNSUPPORTED_VERSION", zig_version.codeFor(.malformed).token());
    try expectEqualStrings("ZNTL_ZIG_UNSUPPORTED_VERSION", zig_version.codeFor(.mismatch).token());
}

test "unsupported diagnostic names detected version and supported range (snapshot)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const msg = try zig_version.message(a, .unsupported, "0.12.1");
    const produced = try std.fmt.allocPrint(a, "{s}\n", .{msg});
    try harness.expectSnapshot(unsupported_snapshot, produced);
    try expect(std.mem.indexOf(u8, msg, "0.12.1") != null);
    try expect(std.mem.indexOf(u8, msg, "0.13.x through 0.16.x") != null);
}

test "mismatch diagnostic names both versions and the remedy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const msg = try zig_version.messageExpected(arena.allocator(), .mismatch, "0.13.0", "0.16.0");
    try expectEqualStrings(
        "detected Zig 0.13.0 but [zig] version is \"0.16.0\"; put Zig 0.16.0 first on PATH or set [zig] version = \"0.13.0\"",
        msg,
    );
}

test "version-command Zig status is silent when supported and coded otherwise" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Supported Zig (native or any in-range target): `zentinel version` reports
    // nothing extra on stderr.
    try expect((try zig_version.statusLine(a, .{ .version = "0.16.0" })) == null);
    try expect((try zig_version.statusLine(a, .{ .version = "0.13.0" })) == null);

    // Missing Zig: reported but non-fatal for `version` (the caller still exits 0).
    const missing = (try zig_version.statusLine(a, .not_found)).?;
    try expect(std.mem.indexOf(u8, missing, "ZNTL_ZIG_NOT_FOUND") != null);

    // Unsupported Zig: reported with detected version and the supported range.
    const unsupported = (try zig_version.statusLine(a, .{ .version = "0.17.0" })).?;
    try expect(std.mem.indexOf(u8, unsupported, "ZNTL_ZIG_UNSUPPORTED_VERSION") != null);
    try expect(std.mem.indexOf(u8, unsupported, "0.17.0") != null);
}

test "execution paths use a fatal Zig diagnostic against the declared version and never synthesize a label" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try expectEqualStrings("0.16.0", (zig_version.supportedLabel(.{ .version = "0.16.0" })).?);
    try expectEqualStrings("0.14.1", (zig_version.supportedLabel(.{ .version = "0.14.1" })).?);
    try expect(zig_version.supportedLabel(.not_found) == null);
    try expect(zig_version.supportedLabel(.{ .version = "0.12.1" }) == null);

    const missing = try zig_version.fatalStatusLine(a, .not_found, "0.16.0");
    try expect(std.mem.indexOf(u8, missing, "ZNTL_ZIG_NOT_FOUND") != null);
    try expectEqual(@as(u8, 2), zig_version.failureExit(.not_found, "0.16.0"));

    const supported = try zig_version.fatalStatusLine(a, .{ .version = "0.13.0" }, "0.13.0");
    try expectEqualStrings("", supported);
    try expectEqual(@as(u8, 0), zig_version.failureExit(.{ .version = "0.13.0" }, "0.13.0"));

    // A supported toolchain that disagrees with the declared version is fatal.
    const mismatch = try zig_version.fatalStatusLine(a, .{ .version = "0.15.2" }, "0.16.0");
    try expect(std.mem.startsWith(u8, mismatch, "error[ZNTL_ZIG_UNSUPPORTED_VERSION]: "));
    try expect(std.mem.indexOf(u8, mismatch, "0.15.2") != null);
    try expectEqual(@as(u8, 2), zig_version.failureExit(.{ .version = "0.15.2" }, "0.16.0"));
}
