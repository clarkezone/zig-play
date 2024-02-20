const std = @import("std");

const StationAgregate = struct {
    ally: std.mem.Allocator,
    name: []const u8,
    valuecount: u32, //unclear if this will overflow based on number of readings
    temperaturetotal: f64, //unclear if this will overflow based on number of readings.  For multithreaded case, 31M rows * max temp would need to be stored asuming split over 32 cores

    pub fn init(ally: std.mem.Allocator, name: []const u8) !StationAgregate {
        return StationAgregate{
            .ally = ally,
            .name = try ally.dupe(u8, name),
            .valuecount = 0,
            .temperaturetotal = 0,
        };
    }

    pub fn deinit(self: *StationAgregate) void {
        self.ally.free(self.name);
    }

    pub fn averageTemperature(self: StationAgregate) f64 {
        if (self.valuecount == 0) {
            return 0.0;
        }
        return self.temperaturetotal / @as(f32, @floatFromInt(self.valuecount));
    }

    pub fn recordTemperature(self: *StationAgregate, value: f64) void {
        self.*.temperaturetotal += value;
        self.*.valuecount += 1;
    }
};

test "StationAgregate" {
    var ally = std.testing.allocator;
    var station = try StationAgregate.init(ally, "test");
    try std.testing.expect(station.averageTemperature() == 0.0);
    station.recordTemperature(10.0);
    try std.testing.expect(station.averageTemperature() == 10.0);
    station.recordTemperature(20.0);
    try std.testing.expect(station.averageTemperature() == 15.0);
    station.deinit();
}

const Stations = struct {
    ally: std.mem.Allocator,
    stations: std.StringHashMap(StationAgregate),

    pub fn init(ally: std.mem.Allocator) Stations {
        var tracker = std.StringHashMap(StationAgregate).init(ally);
        var st = Stations{ .ally = ally, .stations = tracker };
        return st;
    }

    pub fn deinit(self: *Stations) void {
        var it = self.stations.iterator();
        while (it.next()) |th| {
            self.ally.free(th.value_ptr.*.name);
        }
        self.stations.deinit();
    }

    pub fn Store(self: *Stations, name: []const u8, temp: f32) !void {
        var thing = try self.stations.getOrPut(name);
        if (!thing.found_existing) {
            thing.value_ptr.* = try StationAgregate.init(self.ally, name);
            thing.key_ptr.* = thing.value_ptr.*.name;
        }
        thing.value_ptr.*.recordTemperature(temp);
    }

    pub fn PrintSummary(self: *Stations) void {
        std.debug.print("Storagecount {}\n", .{self.stations.count()});
    }

    pub fn PrintAll(self: *Stations) void {
        var it = self.stations.iterator();
        while (it.next()) |t| {
            std.debug.print("Place: {s}\n", .{t.value_ptr.*.name});
        }
    }
};

test "hashmap stations" {
    var stats = Stations.init(std.testing.allocator);
    defer stats.deinit();
    try stats.Store("foo", 32);
    try stats.Store("foo", 10);
    try stats.Store("bar", 15);
    // TODO confirm two entries and value
}

test "hashmap stationagregate" {
    var tracker = std.StringHashMap(StationAgregate).init(std.testing.allocator);
    defer tracker.deinit();
    const testkey = "ssss";
    var thing = try tracker.getOrPut(testkey);
    try std.testing.expect(!thing.found_existing);
    if (thing.found_existing) {
        std.debug.print("\nFound\n", .{});
    } else {
        thing.value_ptr.* = StationAgregate.init("sssname");
        std.debug.print("\nNot Found\n", .{});
    }
    var thing2 = try tracker.getOrPut(testkey);
    try std.testing.expect(thing2.found_existing);
    if (thing2.found_existing) {
        std.debug.print("Found with data {s}\n", .{thing.value_ptr.*.name});
    } else {
        std.debug.print("Not Found\n", .{});
    }
}

pub fn main() !void {
    const path = "../../data/weather_stations.csv";
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

pub fn parseLine(buff: []const u8) !struct { name: []const u8, value: f32 } {
    var splitindex: usize = 0;
    for (buff, 0..) |b, i| {
        if (b == ';') {
            splitindex = i;
            break;
        }
    }
    var stationName = buff[0..splitindex];
    var tempStr = buff[splitindex + 1 ..];
    var temp = try std.fmt.parseFloat(f32, tempStr);
    return .{ .name = stationName, .value = temp };
}

test "parseLine" {
    //# Adapted from https://simplemaps.com/data/world-cities
    //# Licensed under Creative Commons Attribution 4.0 (https://creativecommons.org/licenses/by/4.0/)

    const line = "foobar;2.444";
    var parsed = try parseLine(line);
    try std.testing.expect(std.mem.eql(u8, parsed.name, "foobar"));
    try std.testing.expect(parsed.value == 2.444);
}

pub fn printallstream(filename: []const u8) !void {
    //@memset(&buf, 0);
    //var buf2: [1024]u8 = std.mem.zeroes([1024]u8);
    //_ = buf2;
    //var buf3: [1024]u8 = [1]u8{0} ** 1024;
    //_ = buf3;
    //
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var stats = Stations.init(allocator);
    defer stats.deinit();

    const sourceFile = try std.fs.cwd().openFile(filename, .{});
    defer sourceFile.close();
    const reader = std.fs.File.reader(sourceFile);
    var buf4: [1024]u8 = undefined;
    var strem = std.io.fixedBufferStream(&buf4);

    var rowcount: u16 = 0;
    while (true) {
        strem.reset();
        reader.streamUntilDelimiter(strem.writer(), '\n', null) catch break;
        var buf = strem.getWritten();
        if (buf[0] != '#') {
            rowcount += 1;
            const vals = parseLine(buf) catch |e| {
                std.debug.print("Parse Error with input: {s}, {}", .{ buf, e });
                return;
            };
            //std.debug.print("name: {s}, value: {}\n", .{ vals.name, vals.value });
            try stats.Store(vals.name, vals.value);
        }
    }
    std.debug.print("{} rows scanned from file.\n", .{rowcount});
    stats.PrintSummary();
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
