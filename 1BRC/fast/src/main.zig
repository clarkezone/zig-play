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

            //doesn't change hash but replaces storage from name passed in to name stored / allocated
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

    pub fn GetStation(self: *Stations, name: []const u8) ?StationAgregate {
        const result = self.stations.get(name);
        return result;
    }

    pub fn PrintSpecific(self: *Stations, name: []const u8) !void {
        const out = std.io.getStdOut().writer();

        const result = self.GetStation(name);
        if (result) |ri| {
            try out.print("{s}={d}/{d}/{d}\n", .{
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
        defer self.ally.free(rawlist);
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

    try std.testing.expect(stats.resultcount == 3);

    const foo = stats.GetStation("foo");
    try std.testing.expect(foo.?.averageTemperature() == 21.0);
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

const scanconfig = struct {
    start: u64,
    end: u64,
    length: u64,
    linecount: u64,
    file: std.fs.File,
    waitgroup: *std.Thread.WaitGroup,
};

fn dostationoperation(mapper: []u8, state: *scanconfig) !void {
    //TODO fix this
    //TODO agregate stats
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var stats = Stations.init(gpa.allocator());
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
        var returnpos = std.mem.indexOfScalarPos(u8, mapper, state.start, '\n');
        if (returnpos) |pos| {
            if (parseLine(mapper[state.start..pos])) |vals| {
                try stats.Store(vals.name, vals.value);
            } else |err| {
                if (err == passError.LineIsComment) {
                    continue;
                } else {
                    return err;
                }
            }

            state.linecount += 1;
            state.start = pos + 1;
        } else {
            break;
        }
    }
}

fn dobaslineoperation(mapper: []u8, state: *scanconfig) !void {
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
        var returnpos = std.mem.indexOfScalarPos(u8, mapper, state.start, '\n');
        if (returnpos) |pos| {
            state.linecount += 1;
            state.start = pos + 1;
        } else {
            break;
        }
    }
}

fn scanfilesegment(state: *scanconfig) void {
    //std.debug.print("Thread start: {} end: {}\n", .{ state.start, state.end });
    //TODO std.os.MAP.SHARED not working in 0.12
    //TODO can we map portions of the file to save memory?
    //const mapper = stdobaslineoperationd.os.mmap(null, state.*.end, std.os.PROT.READ, std.os.MAP.SHARED, state.*.file.handle, state.*.start) catch |err| {
    const mapper = std.os.mmap(null, state.*.length, std.os.PROT.READ, std.os.MAP.SHARED, state.*.file.handle, 0) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };
    //dostationoperation(mapper, state) catch |err| {
    dobaslineoperation(mapper, state) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        unreachable;
    };
    defer std.os.munmap(mapper);
    std.debug.print("Thread Stop with linecount {}\n", .{state.linecount});
    state.*.waitgroup.finish();
}

pub fn scanfile(filename: []const u8, cpucount: usize, ally: std.mem.Allocator) !void {
    const fileh = try std.fs.cwd().openFile(filename, .{});
    defer fileh.close();
    var waitgroup = std.Thread.WaitGroup{};
    var threadconfigs: std.ArrayList(scanconfig) = std.ArrayList(scanconfig).init(ally);
    defer threadconfigs.deinit();
    const filelen = try fileh.getEndPos();
    try populateThreadConfigs(filelen, cpucount, &threadconfigs, &waitgroup, fileh);
    var timer = try std.time.Timer.start();
    for (threadconfigs.items) |*ss| {
        _ = try std.Thread.spawn(.{}, scanfilesegment, .{ss});
        //TODO fix this
        //defer tr.join();
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
    var nextEnd: u64 = scanbytesperfor - 1;
    for (0..cpucount) |i| {
        std.debug.print("CPU: {}\n", .{i});
        var ss: scanconfig = .{ .start = nextStart, .end = nextEnd, .length = filelen, .linecount = 0, .file = fileh, .waitgroup = wg };
        nextStart = nextEnd + 1;
        nextEnd += scanbytesperfor - 1;
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
    try scanfile(filename, cpucount, allocator);
}

//TODO 5. add tests to ensure simple map case works
test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
