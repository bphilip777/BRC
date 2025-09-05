// Std
const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
// Random - Does this work with multithreading?
const RndGen = std.Random.DefaultPrng;
const seed: u64 = 11223344;
var rnd = RndGen.init(seed);
const rand = rnd.random();
inline fn randomNumber(min: u16, max: u16) u16 {
    return rand.intRangeLessThan(u16, min, max);
}
// Base filepath
const basepath = "src/measurements_ver";
const ext = ".txt";
// Weather Stations
const WeatherStations = @import("WeatherStations.zig");
// Show End Str
const end_str = if (@import("builtin").os.tag == .windows) "\r\n" else "\n";
// Limit
const NUM_ROWS_LIMIT: u32 = 1024 * 1024 * 1024;
const MIN_ROWS_PER_THREAD: u32 = 4096;
// Errors
const CreateMeasurementsError = error{
    TooFewRows,
    TooManyRows,
};
// Thread stuff
const Mutex = std.Thread.Mutex;
const Thread = std.Thread;

// Versions
pub fn ver0(num_rows: u32) !void {
    // uses bufprint to write row by row
    if (num_rows == 0) return CreateMeasurementsError.TooFewRows;
    if (num_rows > NUM_ROWS_LIMIT) return CreateMeasurementsError.TooManyRows;
    // create filename
    var filename_buffer: [128]u8 = undefined;
    const filename = std.fmt.bufPrint(
        &filename_buffer,
        "{s}_{}_{}{s}",
        .{ basepath, 0, num_rows, ext },
    ) catch unreachable;
    // create file
    var file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();
    // create + write data
    var data_buffer: [128]u8 = undefined;
    // writing very little data at a time
    for (0..num_rows) |_| {
        const row = randomNumber(0, WeatherStations.stations.len);
        const station = WeatherStations.stations[row];

        const data = std.fmt.bufPrint(
            &data_buffer,
            "{s};{s};{s}",
            .{ station.id, station.temp, end_str },
        ) catch unreachable;
        _ = try file.write(data);
    }
}

pub fn ver1(num_rows: u32) !void {
    // memcpy instead of bufprint
    // uses larger buffers
    // improved speed by up to 8x - still not that fast though
    if (num_rows == 0) return CreateMeasurementsError.TooFewRows;
    if (num_rows > NUM_ROWS_LIMIT) return CreateMeasurementsError.TooManyRows;
    // create filename
    var filename_buffer: [128]u8 = undefined;
    const filename = std.fmt.bufPrint(
        &filename_buffer,
        "{s}_{}_{}{s}",
        .{ basepath, 1, num_rows, ext },
    ) catch unreachable;
    // create file
    var file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();
    // write to file
    try writer1(file, num_rows);
}

fn writer1(file: std.fs.File, num_rows: u32) !void {
    if (num_rows == 0) return;
    // buffers
    var data_buffer: [4096]u8 = undefined;
    // idxs
    var curr_row: u32 = 0; // current row
    var buf_start: u32 = 0;
    var buf_end: u32 = 0;
    const num_semicolons: u32 = 2;
    while (curr_row < num_rows) : (curr_row += 1) {
        const random_row = randomNumber(0, WeatherStations.stations.len);
        const station = WeatherStations.stations[random_row];
        // const data = std.fmt.bufPrint(
        //     &row_buffer,
        //     "{s};{s};{s}",
        //     .{ station.id, station.temp, end_str },
        // ) catch unreachable;
        buf_end = buf_start + //
            @as(u32, @truncate(station.id.len)) + //
            @as(u32, @truncate(station.temp.len)) + //
            @as(u32, @truncate(end_str.len)) + //
            num_semicolons;
        if (buf_end >= data_buffer.len) { // write data buffer
            _ = try file.write(data_buffer[0..buf_start]);
            buf_end -= buf_start;
            buf_start = 0;
        } else { // write daat
            buf_end = buf_start + //
                @as(u32, @truncate(station.id.len));
            @memcpy(data_buffer[buf_start..buf_end], station.id);
            @memset(data_buffer[buf_start .. buf_start + 1], ';');
            buf_start += 1;
            buf_end = buf_start + //
                @as(u32, @truncate(station.temp.len));
            @memcpy(data_buffer[buf_start..buf_end], station.temp);
            buf_start = buf_end;
            @memset(data_buffer[buf_start .. buf_start + 1], ';');
            buf_start += 1;
            buf_end = buf_start + //
                @as(u32, @truncate(end_str.len));
            @memcpy(data_buffer[buf_start..buf_end], end_str);
        }
        buf_start = buf_end;
    }
}

fn storeRandomNumber(arr: []u16, offset: u32, n_idxs: u32) void {
    print("Offset: {}, Idxs: {}\n", .{ offset, n_idxs });
    for (0..n_idxs) |i| {
        arr[offset + i] = randomNumber(0, WeatherStations.stations.len);
    }
}

fn computeNThreads(num_rows: u32) u32 {
    const total_threads = Thread.getCpuCount() catch 1;
    const usable_threads = total_threads - @intFromBool(total_threads > 1);
    const data_threads = num_rows / MIN_ROWS_PER_THREAD;
    return @max(1, @min(usable_threads, data_threads));
}

fn computeRnds(allo: Allocator, num_rows: u32, n_threads: u32) ![]u16 {
    // create mem
    const all_rnds: []u16 = try allo.alloc(u16, num_rows);
    errdefer allo.free(all_rnds);
    // create threads
    var threads: [32]Thread = undefined;
    // compute offsets
    const idxs_per_thread: u32 = num_rows / n_threads;
    var curr_offset: u32 = 0;
    // spawn threads + compute rnds
    for (0..n_threads) |i| {
        threads[i] = try std.Thread.spawn(
            .{},
            storeRandomNumber,
            .{ all_rnds, curr_offset, idxs_per_thread },
        );
        curr_offset += idxs_per_thread;
    }
    for (0..n_threads) |i| threads[i].join();
    if (curr_offset != num_rows) {
        storeRandomNumber(all_rnds, curr_offset, num_rows - curr_offset);
    }
    return all_rnds;
}

fn computeOffsets(all_rnds: []u32, offsets: *u32) void {
    var i: usize = 0;
    for (all_rnds) |curr_rnd| {
        const station = WeatherStations.stations[curr_rnd];
        i += station.id.len + station.temp.len;
    }
    offsets.* = i;
}

pub fn ver2(allo: Allocator, num_rows: u32) !void {
    // same as ver1 but threaded
    if (num_rows == 0) return CreateMeasurementsError.TooFewRows;
    if (num_rows > NUM_ROWS_LIMIT) return CreateMeasurementsError.TooManyRows;
    // create filename
    // var filename_buffer: [128]u8 = undefined;
    // const filename = std.fmt.bufPrint(
    //     &filename_buffer,
    //     "{s}_{}_{}{s}",
    //     .{ basepath, 2, num_rows, ext },
    // ) catch unreachable;
    // _ = filename;

    // compute threads
    const n_threads = computeNThreads(num_rows);
    // pre-compute all random numbers
    const all_rnds = try computeRnds(allo, num_rows, n_threads);
    defer allo.free(all_rnds);
    for (all_rnds) |val| print("{} ", .{val});
    print("\n", .{});
    // compute offsets
    const offsets = blk: {
        var offsets: [32]u32 = undefined;
        for (0..n_threads) |i| {
            offsets[i] = 1;
        }
    };
}

fn writer2(
    file: std.fs.File,
    offset: usize, // offset into file
    rows: usize, // amount of rows to write
) !void {
    try file.seekTo(offset);
    try writer1(file, @truncate(rows));
}
