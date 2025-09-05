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
const WeatherStation = @import("WeatherStation.zig");
const WeatherStations = @import("WeatherStations.zig");
// file str consts
const end_str = if (@import("builtin").os.tag == .windows) "\r\n" else "\n";
const num_semicolons: u16 = 2;
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
    var idx = Idx{};
    while (curr_row < num_rows) : (curr_row += 1) {
        const random_row = randomNumber(0, WeatherStations.stations.len);
        const station = WeatherStations.stations[random_row];
        idx = try core(file, station, idx, &data_buffer);
    }
    if (idx.start != 0) {
        _ = try file.write(data_buffer[0..idx.start]);
    }
}

const Idx = struct {
    start: u16 = 0,
    end: u16 = 0,
};

inline fn core(
    file: std.fs.File,
    station: WeatherStation,
    idx: Idx,
    data_buffer: *[4096]u8,
) !Idx {
    var new_idx = idx;
    new_idx.end = new_idx.start + //
        @as(@TypeOf(new_idx.start), @truncate(station.id.len)) + //
        @as(@TypeOf(new_idx.start), @truncate(station.temp.len)) + //
        @as(@TypeOf(new_idx.start), @truncate(end_str.len)) + //
        num_semicolons;
    if (new_idx.end >= data_buffer.len) { // write data buffer
        _ = try file.write(data_buffer[0..new_idx.start]);
        new_idx.end -= new_idx.start;
        new_idx.start = 0;
    } else { // write data
        new_idx.end = new_idx.start + @as(@TypeOf(new_idx.start), @truncate(station.id.len));
        @memcpy(data_buffer[new_idx.start..new_idx.end], station.id);
        new_idx.start = new_idx.end;
        new_idx.end += 1;
        @memset(data_buffer[new_idx.start..new_idx.end], ';');
        new_idx.start = new_idx.end;
        new_idx.end = new_idx.start + @as(@TypeOf(new_idx.start), @truncate(station.temp.len));
        @memcpy(data_buffer[new_idx.start..new_idx.end], station.temp);
        new_idx.start = new_idx.end;
        new_idx.end += 1;
        @memset(data_buffer[new_idx.start..new_idx.end], ';');
        new_idx.start = new_idx.end;
        new_idx.end = new_idx.start + @as(@TypeOf(new_idx.start), @truncate(end_str.len));
        @memcpy(data_buffer[new_idx.start..new_idx.end], end_str);
    }
    new_idx.start = new_idx.end;
    return new_idx;
}

fn storeRandomNumber(arr: []u16) void {
    for (0..arr.len) |i| {
        arr[i] = randomNumber(0, WeatherStations.stations.len);
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
            .{all_rnds[curr_offset .. curr_offset + idxs_per_thread]},
        );
        curr_offset += idxs_per_thread;
    }
    for (0..n_threads) |i| threads[i].join();
    if (curr_offset != num_rows) {
        storeRandomNumber(all_rnds[curr_offset..num_rows]);
    }
    return all_rnds;
}

fn storeOffset(all_rnds: []u16, offset: *u64) void {
    for (all_rnds) |curr_rnd| {
        const station = WeatherStations.stations[curr_rnd];
        offset.* += station.id.len + station.temp.len + num_semicolons + end_str.len;
    }
}

fn computeOffsets(all_rnds: []u16, offsets: []u64, num_rows: u32, n_threads: u32) !void {
    std.debug.assert(offsets.len >= n_threads + 1);
    std.debug.assert(n_threads > 0);
    var threads: [32]Thread = undefined;
    // compute offsets
    const idxs_per_thread: u32 = num_rows / n_threads;
    var curr_offset: u32 = 0;
    // spawn threads + compute rnds
    for (0..n_threads) |i| {
        threads[i] = try Thread.spawn(
            .{},
            storeOffset,
            .{ all_rnds[curr_offset .. curr_offset + idxs_per_thread], &offsets[i] },
        );
        curr_offset += idxs_per_thread;
    }
    for (0..n_threads) |i| threads[i].join();
    for (1..n_threads) |i| offsets[i] += offsets[i - 1];
    // compute file size at end
    offsets[n_threads] = offsets[n_threads - 1];
    if (curr_offset < num_rows) {
        for (all_rnds[curr_offset..]) |all_rnd| {
            const station = WeatherStations.stations[all_rnd];
            offsets[n_threads] += station.id.len + //
                station.temp.len + //
                num_semicolons + //
                end_str.len;
        }
    }
}

pub fn ver2(allo: Allocator, num_rows: u32) !void {
    // _ = allo;
    // same as ver1 but threaded
    if (num_rows == 0) return CreateMeasurementsError.TooFewRows;
    if (num_rows > NUM_ROWS_LIMIT) return CreateMeasurementsError.TooManyRows;
    // // create filename
    var filename_buffer: [128]u8 = undefined;
    const filename = std.fmt.bufPrint(
        &filename_buffer,
        "{s}_{}_{}{s}",
        .{ basepath, 2, num_rows, ext },
    ) catch unreachable;
    print("Filename: {s}\n", .{filename});
    // create file
    var file = try std.fs.cwd().createFile(filename, .{ .truncate = true });
    defer file.close();
    // compute threads
    const n_threads = computeNThreads(num_rows);
    print("# Of Threads: {}\n", .{n_threads});
    // pre-compute all random numbers
    const all_rnds = try computeRnds(allo, num_rows, n_threads);
    defer allo.free(all_rnds);
    print("# of Rnds: {}\n", .{all_rnds.len});
    // compute offsets
    const offsets = blk: {
        var offsets = [_]u64{0} ** 32;
        try computeOffsets(all_rnds, &offsets, num_rows, n_threads);
        break :blk offsets;
    };
    print("Offsets: ", .{});
    for (offsets) |offset| print("{} ", .{offset});
    print("\n", .{});
    try file.setEndPos(offsets[n_threads]);
    const idxs_per_thread: u32 = num_rows / n_threads;
    try writer2(filename, all_rnds[idxs_per_thread .. idxs_per_thread * 2], offsets[1]);
    // for (offsets) |offset| print("{} ", .{offset});
    // var curr_pos: u64 = 0;
    // for (all_rnds) |all_rnd| {
    //     const station = WeatherStations.stations[all_rnd];
    //     curr_pos += station.id.len + station.temp.len + 2 + end_str.len;
    // }
    // print("Curr Pos: {}\n", .{curr_pos});
}

fn writer2(filename: []const u8, rnds: []u16, offset: u64) !void {
    std.debug.assert(rnds.len > 0);
    // file
    var file = try std.fs.cwd().openFile(filename, .{ .mode = .write_only });
    defer file.close();
    try file.seekTo(offset);
    // data
    var data_buffer: [4096]u8 = undefined;
    // buffer idx
    var idx = Idx{};
    for (rnds) |curr_row| {
        const station = WeatherStations.stations[curr_row];
        idx = try core(file, station, idx, &data_buffer);
    }
    if (idx.start != 0) {
        _ = try file.write(data_buffer[0..idx.start]);
    }
}
