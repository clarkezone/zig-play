const std = @import("std");

pub fn main() !void {
    const path = "../data/weather_stations.csv";
    const sourceFile = try std.fs.cwd().openFile(path, .{});
    defer sourceFile.close();
    const reader = std.fs.File.reader(sourceFile);
    var buf: [1024]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        std.debug.print("Hello {s} {s}\n", .{ line, buf });
    }
}
