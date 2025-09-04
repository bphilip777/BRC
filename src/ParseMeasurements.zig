const std = @import("std");
const print = std.debug.print;
const WeatherStations = @import("WeatherStations.zig");

pub fn ver0(idx: u32) !void {
    // create filename
    var filename_buffer: [128]u8 = undefined;
    const filename = try std.fmt.bufPrint(&filename_buffer, "src/measurments_ver0_{}.txt", .{idx});
    // open file
    var file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();
    // create buffer + reader
    var buffer: [4096]u8 = undefined;
    const reader = file.reader(&buffer);
    // read contens of file
    while (try reader.readPositional(&buffer)) |line| {
        print("{s}\n", .{line});
    }
}
