const std = @import("std");

const scanstate = struct {
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
    //TODO 8. use n threads
    //TODO 7. find mindpoint that is newline boundary
    //TODO 6. look at tokenizer and handle newline + ;
    //TODO 5. use argument for filepath and add a hyperfine test
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

pub fn scanfile() !void {
    //TODO 6 add flags to switch modes
    const fileh = try std.fs.cwd().openFile("../../data/measurements_1B.txt", .{});
    defer fileh.close();
    var waitgroup = std.Thread.WaitGroup{};

    const filelen = try fileh.getEndPos();
    var ss: scanstate = .{ .start = 0, .end = filelen / 2, .length = filelen, .linecount = 0, .file = fileh, .waitgroup = &waitgroup };
    var ss2: scanstate = .{ .start = filelen / 2, .end = filelen, .length = filelen, .linecount = 0, .file = fileh, .waitgroup = &waitgroup };

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

pub fn main() !void {
    std.debug.print("Speed of light test running..\n", .{});
    try scanfile();
}

//TODO 5. add tests to ensure simple map case works
test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
