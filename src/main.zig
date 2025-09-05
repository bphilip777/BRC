const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;

const CreateMeasurements = @import("CreateMeasurements.zig");
const ver0 = CreateMeasurements.ver0;
const ver1 = CreateMeasurements.ver1;
const ver2 = CreateMeasurements.ver2;

// TODO:
// 1. finish writerv2
// 2. finish reader v0-3
// 3. test speed of all of them

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allo: Allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    // _ = allo;

    const num_rows: u32 = 2 * 4096 + 1;
    // try timer(.{ .ver0 = ver0 }, .{ .num_rows = num_rows });
    // try timer(.{ .ver1 = ver1 }, .{ .num_rows = num_rows });
    try timer(.{ .ver2 = ver2 }, .{ .allo = allo, .num_rows = num_rows });
}

const Versions = union(enum) {
    ver0: fn (u32) @typeInfo(@typeInfo(@TypeOf(CreateMeasurements.ver0)).@"fn".return_type.?).error_union.error_set!void,
    ver1: fn (u32) @typeInfo(@typeInfo(@TypeOf(CreateMeasurements.ver1)).@"fn".return_type.?).error_union.error_set!void,
    ver2: fn (std.mem.Allocator, u32) @typeInfo(@typeInfo(@TypeOf(CreateMeasurements.ver2)).@"fn".return_type.?).error_union.error_set!void,
};

const Inputs = struct {
    allo: ?Allocator = null,
    num_rows: u32,
};

fn timer(
    versions: Versions,
    inputs: Inputs,
) !void {
    const start = std.time.nanoTimestamp();
    switch (versions) {
        .ver0 => |ver| try ver(inputs.num_rows),
        .ver1 => |ver| try ver(inputs.num_rows),
        .ver2 => |ver| try ver(inputs.allo.?, inputs.num_rows),
    }
    const end = std.time.nanoTimestamp();

    var diff = end - start;
    const ns_per = [_]@TypeOf(diff){
        std.time.ns_per_min,
        std.time.ns_per_s,
        std.time.ns_per_ms,
        std.time.ns_per_us,
    };
    const units = [_][]const u8{ "min", "s", "ms", "us" };

    var times: [4]@TypeOf(diff) = undefined;
    for (0..times.len) |i| {
        times[i] = @divTrunc(diff, ns_per[i]);
        diff -= times[i] * ns_per[i];
    }

    print("Took: ", .{});
    for (times, units) |time, unit| {
        print("{}{s} ", .{ time, unit });
    } else print("\n", .{});
}
