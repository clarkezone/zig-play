const std = @import("std");

const StationAgregate = struct {
    ally: std.mem.Allocator,
    name: []const u8,
    valuecount: u32, //unclear if this will overflow based on number of readings
    temperaturetotal: f64, //unclear if this will overflow based on number of readings.  For multithreaded case, 31M rows * max temp would need to be stored asuming split over 32 cores
    temperaturemin: f64,
    temperaturemax: f64,

    pub fn init(ally: std.mem.Allocator, name: []const u8) !StationAgregate {
        return StationAgregate{
            .ally = ally,
            .name = try ally.dupe(u8, name),
            .valuecount = 0,
            .temperaturetotal = 0,
            .temperaturemin = 0,
            .temperaturemax = 0,
        };
    }

    pub fn deinit(self: *StationAgregate) void {
        self.ally.free(self.name);
    }

    pub fn averageTemperature(self: StationAgregate) f64 {
        if (self.valuecount == 0) {
            return 0.0;
        }
        // if denominator is f32, rounding is broken
        return self.temperaturetotal / @as(f64, @floatFromInt(self.valuecount));
        //return try std.math.divCeil(f64, self.temperaturetotal, @as(f64, @floatFromInt(self.valuecount)));
    }

    pub fn recordTemperature(self: *StationAgregate, value: f64) void {
        self.*.temperaturetotal += value;
        if (self.*.temperaturemin == 0) {
            self.*.temperaturemin = value;
        }
        if (self.*.temperaturemax == 0) {
            self.*.temperaturemax = value;
        }
        if (value < self.*.temperaturemin) {
            self.*.temperaturemin = value;
        } else if (value > self.*.temperaturemax) {
            self.*.temperaturemax = value;
        }
        self.*.valuecount += 1;
    }
};

test "StationAgregate" {
    const ally = std.testing.allocator;
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
    stations: std.StringArrayHashMap(StationAgregate),

    //TODO error return causes deinit not to be found
    pub fn init(ally: std.mem.Allocator) Stations {
        var tracker = std.StringArrayHashMap(StationAgregate).init(ally);
        // no perf improvement:
        tracker.ensureTotalCapacity(10000) catch {
            unreachable;
        };
        const st = Stations{ .ally = ally, .stations = tracker };
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
        const thing = try self.stations.getOrPut(name);
        if (!thing.found_existing) {
            thing.value_ptr.* = try StationAgregate.init(self.ally, name);
            thing.key_ptr.* = thing.value_ptr.*.name;
        }
        thing.value_ptr.*.recordTemperature(temp);
    }

    pub fn PrintSummary(self: *Stations) void {
        std.debug.print("Storagecount {}\n", .{self.stations.count()});
    }

    fn compareStrings(_: void, lhs: []const u8, rhs: []const u8) bool {
        return std.mem.order(u8, lhs, rhs).compare(std.math.CompareOperator.lt);
    }

    pub fn PrintSpecific(self: *Stations, name: []const u8) !void {
        const out = std.io.getStdOut().writer();

        const result = self.stations.get(name);
        if (result) |ri| {
            try out.print("{s}={d}/{d}/{d}\n", .{
                ri.name,
                ri.temperaturemin,
                ri.averageTemperature(),
                ri.temperaturemax,
            });
            try out.print("{s}={d:.1}/{s}/{d:.1}\n", .{
                ri.name,
                ri.temperaturemin,
                ri.averageTemperature(),
                ri.temperaturemax,
            });
        }
    }

    pub fn PrintAll(self: *Stations) !void {
        const out = std.io.getStdOut().writer();
        //var it = self.stations.iterator();
        const stationlist = std.ArrayList([]const u8);
        var list = stationlist.init(self.ally);
        defer list.deinit();
        try list.appendSlice(self.stations.keys());
        const rawlist = try list.toOwnedSlice();
        std.sort.insertion([]const u8, rawlist, {}, compareStrings);
        //doesn't work
        //self.stations.sort(lessthan);
        try out.print("{{", .{});
        std.debug.print("sorted: ", .{});
        for (rawlist) |li| {
            const result = self.stations.get(li);
            if (result) |ri| {
                try out.print("{s}={d:.1}/{d:.1}/{d:.1}, ", .{
                    ri.name,
                    ri.temperaturemin,
                    ri.averageTemperature(),
                    ri.temperaturemax,
                });
            }
        }
        try out.print("}}\n", .{});
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
    const thing = try tracker.getOrPut(testkey);
    try std.testing.expect(!thing.found_existing);
    if (thing.found_existing) {
        std.debug.print("\nFound\n", .{});
    } else {
        thing.value_ptr.* = StationAgregate.init("sssname");
        std.debug.print("\nNot Found\n", .{});
    }
    const thing2 = try tracker.getOrPut(testkey);
    try std.testing.expect(thing2.found_existing);
    if (thing2.found_existing) {
        std.debug.print("Found with data {s}\n", .{thing.value_ptr.*.name});
    } else {
        std.debug.print("Not Found\n", .{});
    }
}

pub fn main() !void {
    //const path = "../../data/measurements_1B.txt";
    //const path = "../../data/measurements_1M.txt";
    //const path = "../../data/measurements_5k.txt";
    const path = "measurements_official.txt";
    try processFileStream(path);
}

const passError = error{ DelimiterNotFound, LineIsComment };

pub fn parseLine(buff: []const u8) !struct { name: []const u8, value: f32 } {
    if (buff[0] != '#') return passError.LineIsComment;
    var splitindex: usize = 0;
    splitindex = std.mem.indexOfScalar(u8, buff, ';') orelse {
        return passError.DelimiterNotFound;
    };
    const stationName = buff[0..splitindex];
    const tempStr = buff[splitindex + 1 ..];
    const temp = try std.fmt.parseFloat(f32, tempStr);
    return .{ .name = stationName, .value = temp };
}

test "parseLine" {
    //# Adapted from https://simplemaps.com/data/world-cities
    //# Licensed under Creative Commons Attribution 4.0 (https://creativecommons.org/licenses/by/4.0/)

    const line = "foobar;2.444";
    const parsed = try parseLine(line);
    try std.testing.expect(std.mem.eql(u8, parsed.name, "foobar"));
    try std.testing.expect(parsed.value == 2.444);

    const nodelim = "foobar2.444\n";
    const parsed2 = try parseLine(nodelim);
    try std.testing.expect(parsed2 == passError.DelimiterNotFound);

    const withcomment = "# Adapted from https://simplemaps.com/data/world-cities";
    const parsed3 = try parseLine(withcomment);
    try std.testing.expect(parsed3 == passError.LineIsComment);
}

pub fn processFileStream(filename: []const u8) !void {
    var timer = try std.time.Timer.start();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var stats = Stations.init(allocator);
    defer stats.deinit();

    const sourceFile = try std.fs.cwd().openFile(filename, .{});
    defer sourceFile.close();
    const reader = std.fs.File.reader(sourceFile);
    var buf4: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf4);

    var rowcount: u64 = 0;
    while (true) {
        stream.reset();
        reader.streamUntilDelimiter(stream.writer(), '\n', null) catch break;
        const buf = stream.getWritten();
        rowcount += 1;
        if (parseLine(buf)) |vals| {
            try stats.Store(vals.name, vals.value);
        } else |err| {
            if (err == passError.LineIsComment) {
                continue;
            } else {
                return err;
            }
        }
    }
    const elapsed: f32 = @floatFromInt(timer.read());
    const elapsedSecs = elapsed / 1e9;

    //    const elapsedSecs = @as(f32, @floatFromInt(timer.read())) / 1e9;

    try stats.PrintAll();
    //    try stats.PrintSpecific("Farkhâna");
    std.debug.print("{} rows scanned from file in {d:.3} secs.\n", .{ rowcount, elapsedSecs });
    std.debug.print("done\n", .{});
}
