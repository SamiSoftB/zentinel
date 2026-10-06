//! Portable zentinel fixture: compiles and tests unchanged on every supported
//! target Zig (0.13 through 0.16), using only `std.testing.expectEqual`.
//! `add` is pinned by its test, so its arithmetic mutant is killed; `clamp` is
//! only exercised away from its exact bounds, so its comparison_boundary mutants
//! survive. scripts/e2e-zig-matrix.sh asserts both outcomes per toolchain.
const std = @import("std");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn clamp(x: i32, lo: i32, hi: i32) i32 {
    if (x < lo) return lo;
    if (x > hi) return hi;
    return x;
}

test "add" {
    try std.testing.expectEqual(@as(i32, 5), add(2, 3));
}

test "clamp away from the exact bounds" {
    try std.testing.expectEqual(@as(i32, 0), clamp(-5, 0, 10));
    try std.testing.expectEqual(@as(i32, 5), clamp(5, 0, 10));
    try std.testing.expectEqual(@as(i32, 10), clamp(50, 0, 10));
}
