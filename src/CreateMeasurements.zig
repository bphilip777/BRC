const std = @import("std");
const print = std.debug.print;
const allo = std.mem.Allocator;
const WeatherStations = @import("WeatherStations.zig").stations;

fn roundToTenths(x: f32) f32 {
    return @round(x * 10.0) / 10.0;
}

fn sampleGaussian(rng: *const std.Random, mean: f32, variance: f32) f32 {
    const uu1: f32 = rng.float(f32);
    const uu2: f32 = rng.float(f32);
    const z0 = @sqrt(-2.0 * @log(uu1)) * @cos(2.0 * std.math.pi * uu2);
    return roundToTenths(mean + z0 * @sqrt(variance));
}

pub fn ver0(num_rows: u32) !void {
    // Naive approach - line by line
    var buffer: [128]u8 = undefined;
    // create file
    const filename = try std.fmt.bufPrint(
        &buffer,
        "src/measurements_ver0_{}.txt",
        .{num_rows},
    );
    var file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();
    // create random generator
    var RndGen = std.Random.DefaultPrng.init(0);
    const rng = RndGen.random();
    // loop
    for (0..num_rows) |_| {
        // get station
        const row = rng.intRangeLessThan(u32, 0, WeatherStations.len);
        const station = WeatherStations[row];
        // convert to value
        const new_temp = sampleGaussian(&rng, station.temp, 10);
        const newline = try std.fmt.bufPrint(&buffer, "{s};{};\r\n", .{ station.id, new_temp });
        _ = try file.write(newline);
    }
}

pub fn ver1(num_rows: u32) !void {
    // Buffered approach
    var line_buf: [128]u8 = undefined;
    const filename = try std.fmt.bufPrint(
        &line_buf,
        "src/measurements_ver1_{}.txt",
        .{num_rows},
    );
    var file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();
    // create random generator
    var RndGen = std.Random.DefaultPrng.init(0);
    const rng = RndGen.random();
    // data
    var data_buf: [4096]u8 = undefined;
    var data_idx: u16 = 0;
    // loop
    for (0..num_rows) |_| {
        const row = rng.intRangeLessThan(u32, 0, WeatherStations.len);
        const station = WeatherStations[row];
        const new_temp = sampleGaussian(&rng, station.temp, 10);
        const newline = try std.fmt.bufPrint(&line_buf, "{s};{};\r\n", .{ station.id, new_temp });
        if ((data_idx + newline.len) > data_buf.len) {
            _ = try file.write(data_buf[0..data_idx]);
            data_idx = 0;
        }
        @memcpy(data_buf[data_idx .. data_idx + newline.len], newline);
        data_idx += @truncate(newline.len);
    }
}

fn computeNThreads(allo: Allocator, num_rows: u32) u8 {
    const total_threads = try std.Thread.getCpuCount();
    const usable_threads = total_threads - @intFromBool(total_threads > 1);
    const min_rows_per_thread: u16 = 1024;
    const desired_threads = num_rows / min_rows_per_thread;
    return @max(1, @min(usable_threads, desired_threads));
}

pub fn ver2(num_rows: u32) !void {
    var line_buf: [128]u8 = undefined;
    // create filename
    const filename = try std.fmt.bufPrint(&line_buf, "src/measurements_ver2_{}.txt", .{num_rows});
    var file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();
    // create random generator
    var RndGen = std.Random.DefaultPrng.init(0);
    const rng = RndGen.random();
    // compute threads
    const n_threads: u8 = try computeNThreads(num_rows);
    var threads: [32]std.Thread = undefined;
    // precompute random numbers
    const rows = try preComputeRows(num_rows, n_threads, &rng);
    defer allo.free(rows);
    // compute offsets into memory
    var offsets = [_]u64{0} ** 32;
    preComputeOffsets(&offsets, num_rows, n_threads, &rng);
    // loop
    // const n_rows_per_thread
    // for (0..num_rows) |_| {
    //
    // }
}

fn fillRows(rng: *const std.Random, rows: []u16) !void {
    for (0..rows.len) |i| {
        rows[i] = rng.intRangeLessThan(u32, 0, WeatherStations.len);
    }
}

fn preComputeRows(
    num_rows: u32,
    n_threads: u8,
    rng: *const std.Random,
) ![]u16 {
    var rows = try allo.alloc(u16, num_rows);
    errdefer allo.free(rows);
    const n_rows_per_thread = rows / n_threads;
    var curr_start: u32 = 0;
    var threads: [32]std.Thread = undefined;
    for (0..n_threads) |i| {
        threads[i] = try std.Thread.spawn(
            .{},
            fillRows,
            .{ &rng, rows[curr_start .. curr_start + n_rows_per_thread] },
        );
        curr_start += n_rows_per_thread;
    }
    for (0..n_threads) |i| threads[i].join();
    if (curr_start < num_rows) {
        fillRows(&rng, rows[curr_start..num_rows]);
    }
    return rows;
}

fn fillOffsets(offset: *u64, rows: []u16) void {
    for (rows) |row| {
        const station = WeatherStations[row];
        offset.* += station.id.len + @ceil(@log10(station.temp)) + 4;
    }
}

fn preComputeOffsets(offsets: []u64, num_rows: u32, rows: []u16, n_threads: u8) void {
    std.debug.assert(offsets.len > n_threads);
    const n_rows_per_thread = num_rows / n_threads;
    var threads: [32]std.Thread = undefined;
    var curr_idx: u32 = 0;
    for (0..n_threads) |i| {
        threads[i] = try std.Thread.spawn(
            .{},
            fillOffsets,
            .{ &offsets[i], rows[curr_idx .. curr_idx + n_rows_per_thread] },
        );
        curr_idx += n_rows_per_thread;
    }
    for (0..n_threads) |i| threads[i].join();
    if (curr_idx < num_rows) {
        offsets[n_threads] = fillOffsets(rows);
    }
    for (0..n_threads) |i| {
        offsets[i] += offsets[i - 1];
    }
}
