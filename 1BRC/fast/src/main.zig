const std = @import("std");

const scanstate = struct {
    startFromFirstnewline: bool,
    start: u64,
    end: u64,
    length: u64,
    linecount: u64, //out
    file: std.fs.File,
    waitgroup: *std.Thread.WaitGroup,
};

fn scanfilesegment(state: *scanstate) void {
    std.debug.print("Thread start: {} end: {}\n", .{ state.start, state.end });
    //TODO std.os.MAP.SHARED not working in 0.12
    //TODO can we map portions of the file to save memory?
    //const mapper = std.os.mmap(null, state.*.end, std.os.PROT.READ, std.os.MAP.SHARED, state.*.file.handle, state.*.start) catch |err| {
    const mapper = std.os.mmap(null, state.*.length, std.os.PROT.READ, std.os.MAP.SHARED, state.*.file.handle, 0) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };
    //TODO 9. use n threads
    //TODO 8. find mindpoint that is newline boundary
    //TODO 7. look at tokenizer and handle newline + ;
    //TODO 6. add bench command to build.zig using hyperfine
    //TODO 5. use argument for filepath and add a hyperfine test [x]
    //TODO 4. pass results back and add on main thread, ensure adds up to 1B [x]
    //TODO 3. use two fixed threads [x]
    //TODO 2. loop and count all newlines [x]
    //TODO 2.5 add timer [x]
    var totallines: u64 = 0;
    var returnpos = std.mem.indexOfScalarPos(u8, mapper, state.start, '\n');
    while (returnpos) |pos| {
        if (pos < state.end) {
            totallines += 1;
            returnpos = std.mem.indexOfScalarPos(u8, mapper, pos + 1, '\n');
        } else {
            std.debug.print("Breaking at: {}\n", .{pos});
            break;
        }
    }
    defer std.os.munmap(mapper);
    state.*.linecount = totallines;
    std.debug.print("Thread Stop with linecount {}\n", .{totallines});
    state.*.waitgroup.finish();
}

pub fn scanfile(filename: []const u8) !void {
    //TODO 6 add flags to switch modes
    const fileh = try std.fs.cwd().openFile(filename, .{});
    defer fileh.close();
    var waitgroup = std.Thread.WaitGroup{};

    const filelen = try fileh.getEndPos();
    var ss: scanstate = .{ .startFromFirstnewline = false, .start = 0, .end = filelen / 2, .length = filelen, .linecount = 0, .file = fileh, .waitgroup = &waitgroup };
    var ss2: scanstate = .{ .startFromFirstnewline = false, .start = filelen / 2, .end = filelen, .length = filelen, .linecount = 0, .file = fileh, .waitgroup = &waitgroup };

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
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();
    const filename = try getargs(allocator);
    defer allocator.free(filename);
    std.debug.print("Speed of light test running against {s}..\n", .{filename});
    try scanfile(filename);
}

//TODO 5. add tests to ensure simple map case works
test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
