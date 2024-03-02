const std = @import("std");

const scanstate = struct {
    start: u64,
    end: u64,
    file: std.fs.File,
    waitgroup: *std.Thread.WaitGroup,
};

fn scanfilesegment(state: *const scanstate) void {
    state.*.waitgroup.start();
    std.debug.print("Start\n", .{});
    //TODO std.os.MAP.SHARED not working in 0.12
    //TODO 1. replace length [x]
    const mapper = std.os.mmap(null, state.*.end, std.os.PROT.READ, std.os.MAP.PRIVATE, state.*.file.handle, state.*.start) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };
    //TODO 5. look at tokenizer and handle newline + ;
    //TODO 4. use multiple threads
    //TODO 3. use two fixed threads
    //TODO 2. loop and count all newlines [x]
    //TODO 2.5 add timer [x]
    var totallines: u64 = 0;
    var returnpos = std.mem.indexOfScalarPos(u8, mapper, 0, '\n');
    while (returnpos) |pos| {
        totallines += 1;
        returnpos = std.mem.indexOfScalarPos(u8, mapper, pos + 1, '\n');
    }
    defer std.os.munmap(mapper);
    std.debug.print("Stop\n", .{});
    state.*.waitgroup.finish();
}

pub fn scanfile() !void {
    //TODO 6 add flags to switch modes
    const fileh = try std.fs.cwd().openFile("../../data/measurements_1B.txt", .{});
    defer fileh.close();
    var waitgroup = std.Thread.WaitGroup{};

    const filelen = try fileh.getEndPos();
    const ss: scanstate = .{ .start = 0, .end = filelen / 2, .file = fileh, .waitgroup = &waitgroup };
    //const ss2: scanstate = .{ .start = filelen / 2, .end = filelen, .file = fileh, .waitgroup = &waitgroup };

    var timer = try std.time.Timer.start();
    const th = try std.Thread.spawn(.{}, scanfilesegment, .{&ss});
    //const th2 = try std.Thread.spawn(.{}, scanfilesegment, .{&ss2});
    waitgroup.wait();
    defer th.join();
    //defer th2.join();

    const elapsedSecs = @as(f32, @floatFromInt(timer.read())) / 1e9;
    std.debug.print("\nFound: {} lines in {d:5} seconds\n", .{ 0, elapsedSecs });
}

pub fn main() !void {
    std.debug.print("Speed of light test running..", .{});
    try scanfile();
}

//TODO 5. add tests to ensure simple map case works
test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
