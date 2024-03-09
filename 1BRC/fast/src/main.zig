const std = @import("std");

const scanconfig = struct {
    start: u64,
    end: u64,
    length: u64,
    linecount: u64,
    file: std.fs.File,
    waitgroup: *std.Thread.WaitGroup,
};

fn scanfilesegment(state: *scanconfig) void {
    std.debug.print("Thread start: {} end: {}\n", .{ state.start, state.end });
    //TODO std.os.MAP.SHARED not working in 0.12
    //TODO can we map portions of the file to save memory?
    //const mapper = std.os.mmap(null, state.*.end, std.os.PROT.READ, std.os.MAP.SHARED, state.*.file.handle, state.*.start) catch |err| {
    const mapper = std.os.mmap(null, state.*.length, std.os.PROT.READ, std.os.MAP.SHARED, state.*.file.handle, 0) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };
    //TODO 10. Add full weather impl from naive, profile
    //TODO 9. use n threads [x]
    //TODO 8. find mindpoint that is newline boundary [x]
    //TODO 7. look at tokenizer handle newline + ;
    //TODO 6. bench with hyperfine script: [x]
    //  1) ensure 1B exists or gen with python
    //  2) build with -OReleaseFast
    //  3) run with hyperfine:
    //    hyperfine --warmup=3 --show-output --command-name="./fast/zig-out/bin/fast ./data/measurements_1B.txt" "./fast/zig-out/bin/fast ./data/measurements_1B.txt"
    //TODO 5. use argument for filepath and add a hyperfine test [x]
    //TODO 4. pass results back and add on main thread, ensure adds up to 1B [x]
    //TODO 3. use two fixed threads [x]
    //TODO 2. loop and count all newlines [x]
    //TODO 2.5 add timer [x]
    if (state.start != 0) {
        //attempt fast forward.
        var returnpos = std.mem.indexOfScalarPos(u8, mapper, state.start, '\n');
        if (returnpos) |pos| {
            // don't count the first line
            state.start = pos + 1; // always increment start to ensure loop not entered if first seek takes out of bounds
        } else {
            unreachable;
        }
    }
    while (state.start < state.end) {
        //TODO : ensure we don't overshoot the end
        var returnpos = std.mem.indexOfScalarPos(u8, mapper, state.start, '\n');
        if (returnpos) |pos| {
            if (pos <= state.end) {
                state.linecount += 1;
            }
            // always increment start to ensure loop is exited
            state.start = pos + 1;
        } else {
            break;
        }
    }
    defer std.os.munmap(mapper);
    std.debug.print("Thread Stop with linecount {}\n", .{state.linecount});
    state.*.waitgroup.finish();
}

pub fn scanfile(filename: []const u8) !void {
    //TODO 6 add flags to switch modes
    const fileh = try std.fs.cwd().openFile(filename, .{});
    defer fileh.close();
    var waitgroup = std.Thread.WaitGroup{};

    const filelen = try fileh.getEndPos();
    var ss: scanconfig = .{ .start = 0, .end = filelen / 2, .length = filelen, .linecount = 0, .file = fileh, .waitgroup = &waitgroup };
    var ss2: scanconfig = .{ .start = filelen / 2, .end = filelen, .length = filelen, .linecount = 0, .file = fileh, .waitgroup = &waitgroup };

    var timer = try std.time.Timer.start();
    const th = try std.Thread.spawn(.{}, scanfilesegment, .{&ss});
    const th2 = try std.Thread.spawn(.{}, scanfilesegment, .{&ss2});
    defer th.join();
    defer th2.join();
    waitgroup.start(); //BUG if thread doesn't start due to join immediately due to error
    waitgroup.start();
    waitgroup.wait();

    const elapsedSecs = @as(f32, @floatFromInt(timer.read())) / 1e9;
    std.debug.print("\nFound: {} lines in {d:5} seconds\n", .{ ss.linecount + ss2.linecount, elapsedSecs });
}

pub fn scanfile2(filename: []const u8, cpucount: usize, ally: std.mem.Allocator) !void {
    const fileh = try std.fs.cwd().openFile(filename, .{});
    defer fileh.close();
    var waitgroup = std.Thread.WaitGroup{};
    var threadconfigs: std.ArrayList(scanconfig) = std.ArrayList(scanconfig).init(ally);
    defer threadconfigs.deinit();
    const filelen = try fileh.getEndPos();
    try populateThreadConfigs(filelen, cpucount, &threadconfigs, &waitgroup, fileh);
    var timer = try std.time.Timer.start();
    for (threadconfigs.items) |*ss| {
        const tr = try std.Thread.spawn(.{}, scanfilesegment, .{ss});
        defer tr.join();
        waitgroup.start();
    }
    waitgroup.wait();
    var totallines: u64 = 0;
    for (threadconfigs.items) |*ss| {
        totallines += ss.linecount;
    }
    const elapsedSecs = @as(f32, @floatFromInt(timer.read())) / 1e9;
    std.debug.print("\nFound: {} lines in {d:5} seconds\n", .{ totallines, elapsedSecs });
    //TODO ?make config immutable and output state, thread handle part of a stored mutable struct
}

//TODO make it compile on 0.12 tree

pub fn populateThreadConfigs(filelen: usize, cpucount: usize, threadconfigs: *std.ArrayList(scanconfig), wg: *std.Thread.WaitGroup, fileh: std.fs.File) !void {
    const scanbytesperfor = filelen / cpucount;
    var nextStart: u64 = 0;
    var nextEnd: u64 = scanbytesperfor;
    for (0..cpucount) |i| {
        std.debug.print("CPU: {}\n", .{i});
        var ss: scanconfig = .{ .start = nextStart, .end = nextEnd, .length = filelen, .linecount = 0, .file = fileh, .waitgroup = wg };
        nextStart = nextEnd;
        nextEnd += scanbytesperfor;
        try threadconfigs.append(ss);
    }
}

test "populateThreadConfigs" {
    //TODO replace all references to the 1B item with something checked in
    const filename = "../../data/weather_stations.csv";
    const fileh = try std.fs.cwd().openFile(filename, .{});
    defer fileh.close();
    const filelen = try fileh.getEndPos();
    const ally = std.testing.allocator;
    var waitgroup = std.Thread.WaitGroup{};
    var threadconfigs: std.ArrayList(scanconfig) = std.ArrayList(scanconfig).init(ally);
    defer threadconfigs.deinit();
    //const cpucount = try std.Thread.getCpuCount();
    var cpucount: u8 = 1;
    try populateThreadConfigs(filelen, cpucount, &threadconfigs, &waitgroup, fileh);
    try std.testing.expectEqual(@as(usize, 1), threadconfigs.items.len);
    threadconfigs.clearAndFree();

    cpucount = 2;
    try populateThreadConfigs(filelen, cpucount, &threadconfigs, &waitgroup, fileh);
    try std.testing.expectEqual(@as(usize, 2), threadconfigs.items.len);
    threadconfigs.clearAndFree();

    cpucount = 3;
    try populateThreadConfigs(filelen, cpucount, &threadconfigs, &waitgroup, fileh);
    const sliced = threadconfigs.items[0..3];
    try std.testing.expectEqual(@as(usize, 3), sliced.len);

    //TODO verify computations for known filesize in each config, ensure every byte is covered
}

pub fn getargs(ally: std.mem.Allocator) ![]const u8 {
    const args = try std.process.argsAlloc(ally);
    defer ally.free(args);
    if (args.len < 2) {
        try std.fmt.format(std.io.getStdErr().writer(), "Usage: {s} <argument>\n", .{"speedoflight"});
        std.os.exit(1);
    }
    var filename = try ally.alloc(u8, args[1].len);
    @memcpy(filename, args[1]);
    return filename;
}

pub fn main() !void {
    var buffer: [1024 * 1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();
    const filename = try getargs(allocator);
    defer allocator.free(filename);
    std.debug.print("Speed of light test running against {s}..\n", .{filename});
    //try scanfile(filename);
    const cpucount = try std.Thread.getCpuCount();
    try scanfile2(filename, cpucount, allocator);
}

//TODO 5. add tests to ensure simple map case works
test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
