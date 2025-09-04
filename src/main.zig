const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;

const CreateMeasurements = @import("CreateMeasurements.zig");
const ver0 = CreateMeasurements.ver0;
const ver1 = CreateMeasurements.ver1;
const ver2 = CreateMeasurements.ver2;

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const allo = gpa.allocator();
    // defer std.debug.assert(gpa.deinit() == .ok);

    const num_rows: u32 = 1024 * 1024;
    try timer(.{ .ver0 = .{ .my_fn = ver0, .num_rows = num_rows } });
    try timer(.{ .ver1 = .{ .my_fn = ver1, .num_rows = num_rows } });
    // try timer(allo, num_rows, ver2);
}

const Versions = union(enum) {
    ver0: struct {
        my_fn: fn (u32) @typeInfo(@typeInfo(@TypeOf(CreateMeasurements.ver0)).@"fn".return_type.?).error_union.error_set!void,
        num_rows: u32,
    },
    ver1: struct {
        my_fn: fn (u32) @typeInfo(@typeInfo(@TypeOf(CreateMeasurements.ver1)).@"fn".return_type.?).error_union.error_set!void,
        num_rows: u32,
    },
    ver2: struct {
        my_fn: fn (std.mem.Allocator, u32) @typeInfo(@typeInfo(@TypeOf(CreateMeasurements.ver2)).@"fn".return_type.?).error_union.error_set!void,
        allo: std.mem.Allocator,
        num_rows: u32,
    },
};

fn timer(
    version: Versions,
) !void {
    const start = std.time.nanoTimestamp();
    switch (version) {
        .ver0 => |ver| try ver.my_fn(ver.num_rows),
        .ver1 => |ver| try ver.my_fn(ver.num_rows),
        .ver2 => |ver| try ver.my_fn(ver.allo, ver.num_rows),
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
