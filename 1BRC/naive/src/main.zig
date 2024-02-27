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
    resultcount: u64,

    //TODO error return causes deinit not to be found
    pub fn init(ally: std.mem.Allocator) Stations {
        var tracker = std.StringArrayHashMap(StationAgregate).init(ally);
        // no perf improvement:
        tracker.ensureTotalCapacity(10000) catch {
            unreachable;
        };
        const stat = Stations{ .ally = ally, .stations = tracker, .resultcount = 0 };
        return stat;
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
        self.resultcount += 1;
    }

    pub fn PrintSummary(self: *Stations) void {
        std.debug.print("Rowscancount{} Storagecount {}\n", .{ self.resultcount, self.stations.count() });
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

    pub fn PrintAll(self: *const Stations) !void {
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

const passError = error{ DelimiterNotFound, LineIsComment };

pub fn parseLine(buff: []const u8) !struct { name: []const u8, value: f32 } {
    if (buff[0] == '#') return passError.LineIsComment;
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
    const e = parseLine(nodelim);
    try std.testing.expectError(passError.DelimiterNotFound, e);

    const withcomment = "# Adapted from https://simplemaps.com/data/world-cities";
    const e2 = parseLine(withcomment);
    try std.testing.expectError(passError.LineIsComment, e2);
}

/// Read the file and process the data.  Caller owns stations returned and must call deinit()
pub fn getStatsFromFileStream(allocator: std.mem.Allocator, filename: []const u8) !Stations {
    var stats = Stations.init(allocator);

    const sourceFile = try std.fs.cwd().openFile(filename, .{});
    defer sourceFile.close();
    const reader = std.fs.File.reader(sourceFile);
    var buf4: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf4);

    while (true) {
        stream.reset();
        reader.streamUntilDelimiter(stream.writer(), '\n', null) catch break;
        const buf = stream.getWritten();
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
    return stats;
}

test "getStatsFromFileStream" {
    const allocator = std.testing.allocator;
    const path = "../../data/weather_stations.csv";
    var stats = try getStatsFromFileStream(allocator, path);
    stats.deinit();
}

pub fn main() !void {
    //const path = "../../data/measurements_1B.txt";
    //const path = "../../data/measurements_1M.txt";
    //const path = "../../data/measurements_5k.txt";
    const path = "measurements_official.txt";
    var timer = try std.time.Timer.start();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var stats = try getStatsFromFileStream(allocator, path);
    const elapsedSecs = @as(f32, @floatFromInt(timer.read())) / 1e9;

    try stats.PrintAll();
    //    try stats.PrintSpecific("Farkhâna");
    std.debug.print("{} rows scanned from file in {d:.3} secs.\n", .{ stats.resultcount, elapsedSecs });
    std.debug.print("done\n", .{});
    stats.deinit();
}
