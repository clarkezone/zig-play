const std = @import("std");

pub fn main() !void {
    std.debug.print("Speed of light test running..", .{});

    //TODO 6 add flags to switch modes
    const fileh = try std.fs.cwd().openFile("../../data/measurements_1B.txt", .{});
    defer fileh.close();

    //TODO std.os.MAP.SHARED not working in 0.12
    //TODO 1. replace length [x]
    const mapper = try std.os.mmap(null, try fileh.getEndPos(), std.os.PROT.READ, std.os.MAP.PRIVATE, fileh.handle, 0);
    //TODO 4. use multiple threads
    //TODO 3. look at tokenizer and handle newline + ;
    //TODO 2. loop and count all newlines [x]
    //TODO 2.5 add timer [x]
    var totallines: u64 = 0;
    var returnpos = std.mem.indexOfScalarPos(u8, mapper, 0, '\n');
    var timer = try std.time.Timer.start();
    while (returnpos) |pos| {
        totallines += 1;
        returnpos = std.mem.indexOfScalarPos(u8, mapper, pos + 1, '\n');
    }
    defer std.os.munmap(mapper);
    const elapsedSecs = @as(f32, @floatFromInt(timer.read())) / 1e9;
    std.debug.print("\nFound: {} lines in {d:5} seconds\n", .{ totallines, elapsedSecs });
}

//TODO 5. add tests to ensure simple map case works
test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
