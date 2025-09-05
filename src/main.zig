const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;

const CreateMeasurements = @import("CreateMeasurements.zig");
const wVer0 = CreateMeasurements.ver0;
const wVer1 = CreateMeasurements.ver1;
// const wVer2 = CreateMeasurements.ver2;

// const ParseMeasurements = @import("ParseMeasurements.zig");
// const rVer0 = ParseMeasurements.ver0;
// const rVer0 = CreateMeasurements.ver2;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allo: Allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    _ = allo;

    // create file
    const num_rows: u32 = 1024 * 1024;
    try timer(.{ .wVer0 = wVer0 }, .{ .num_rows = num_rows });
    try timer(.{ .wVer1 = wVer1 }, .{ .num_rows = num_rows });
    // try timer(.{ .wVer2 = wVer2 }, .{ .allo = allo, .num_rows = num_rows }); // still not working correctly

    // read file
    // try timer(.{ .rVer0 = rVer0 }, .{});
}

const Versions = union(enum) {
    wVer0: fn (u32) @typeInfo(@typeInfo(@TypeOf(CreateMeasurements.ver0)).@"fn".return_type.?).error_union.error_set!void,
    wVer1: fn (u32) @typeInfo(@typeInfo(@TypeOf(CreateMeasurements.ver1)).@"fn".return_type.?).error_union.error_set!void,
    // wVer2: fn (std.mem.Allocator, u32) @typeInfo(@typeInfo(@TypeOf(CreateMeasurements.ver2)).@"fn".return_type.?).error_union.error_set!void,
    // rVer0: fn () @typeInfo(@typeInfo(@TypeOf(ParseMeasurements.ver0)).@"fn".return_type.?).error_union.error_set!void,
};

const Inputs = struct {
    allo: ?Allocator = null,
    num_rows: u32 = 0,
};

fn timer(
    versions: Versions,
    inputs: Inputs,
) !void {
    const start = std.time.nanoTimestamp();
    switch (versions) {
        .wVer0 => |ver| try ver(inputs.num_rows),
        .wVer1 => |ver| try ver(inputs.num_rows),
        // .wVer2 => |ver| try ver(inputs.allo.?, inputs.num_rows),
        // .rVer0 => |ver| try ver(),
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
