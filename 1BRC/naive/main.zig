const std = @import("std");

pub fn main() !void {
    const path = "../data/weather_stations.csv";
    try printallstream(path);
}

pub fn printall(filename: []const u8) !void {
    const sourceFile = try std.fs.cwd().openFile(filename, .{});
    defer sourceFile.close();
    const reader = std.fs.File.reader(sourceFile);
    var buf: [1024]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        std.debug.print("Hello {s}\n", .{line});
    }
}

pub fn printallstream(filename: []const u8) !void {
    //@memset(&buf, 0);
    //var buf2: [1024]u8 = std.mem.zeroes([1024]u8);
    //_ = buf2;
    //var buf3: [1024]u8 = [1]u8{0} ** 1024;
    //_ = buf3;
    //
    const sourceFile = try std.fs.cwd().openFile(filename, .{});
    defer sourceFile.close();
    const reader = std.fs.File.reader(sourceFile);
    var buf4: [1024]u8 = undefined;
    var strem = std.io.fixedBufferStream(&buf4);

    while (true) {
        strem.reset();
        reader.streamUntilDelimiter(strem.writer(), '\n', null) catch return;
        std.debug.print("{s}\n", .{buf4[0..try strem.getPos()]});
    }
    std.debug.print("done\n", .{});

    ////    const input_string = "some_string_with_delimiter!";
    ////    var input_fbs = std.io.fixedbufferstream(input_string);
    ////    const reader = input_fbs.reader();
    ////
    ////    var output: [input_string.len]u8 = undefined;
    ////    var output_fbs = std.io.fixedbufferstream(&output);
    ////    const writer = output_fbs.writer();
    ////
    ////    try reader.streamuntildelimiter(writer, '!', input_fbs.buffer.len);
    ////    try std.testing.expectequalstrings("some_string_with_delimiter", output_fbs.getwritten());
    ////    try std.testing.expecterror(error.endofstream, reader.streamuntildelimiter(writer, '!', input_fbs.buffer.len));

}
