const std = @import("std");
const Driver = @import("driver.zig").Driver;

pub const Seeder = struct {
    id: []const u8,
    name: []const u8,
    run_sql: []const u8,
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(Seeder),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{ .allocator = allocator, .items = .empty };
    }

    pub fn deinit(self: *Registry) void {
        self.items.deinit(self.allocator);
    }

    pub fn add(self: *Registry, seeder: Seeder) !void {
        try self.items.append(self.allocator, seeder);
    }
};

pub const Store = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        isExecuted: *const fn (ctx: *anyopaque, id: []const u8) anyerror!bool,
        markExecuted: *const fn (ctx: *anyopaque, id: []const u8) anyerror!void,
    };

    pub fn isExecuted(self: Store, id: []const u8) !bool {
        return self.vtable.isExecuted(self.ctx, id);
    }

    pub fn markExecuted(self: Store, id: []const u8) !void {
        return self.vtable.markExecuted(self.ctx, id);
    }

    pub fn from(comptime T: type, value: *T) Store {
        const table = struct {
            fn isExecuted(ctx: *anyopaque, id: []const u8) anyerror!bool {
                const ptr: *T = @ptrCast(@alignCast(ctx));
                return ptr.isExecuted(id);
            }

            fn markExecuted(ctx: *anyopaque, id: []const u8) anyerror!void {
                const ptr: *T = @ptrCast(@alignCast(ctx));
                try ptr.markExecuted(id);
            }
        };

        return .{
            .ctx = value,
            .vtable = &.{
                .isExecuted = table.isExecuted,
                .markExecuted = table.markExecuted,
            },
        };
    }
};

pub const Runner = struct {
    driver: Driver,
    store: Store,

    pub fn init(driver: Driver, store: Store) Runner {
        return .{ .driver = driver, .store = store };
    }

    pub fn run(self: Runner, registry: *const Registry) !usize {
        var executed: usize = 0;
        for (registry.items.items) |seeder| {
            if (try self.store.isExecuted(seeder.id)) continue;
            try self.driver.execute(seeder.run_sql);
            try self.store.markExecuted(seeder.id);
            executed += 1;
        }
        return executed;
    }
};

pub const InMemoryStore = struct {
    allocator: std.mem.Allocator,
    ids: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator) InMemoryStore {
        return .{
            .allocator = allocator,
            .ids = .init(allocator),
        };
    }

    pub fn deinit(self: *InMemoryStore) void {
        var it = self.ids.keyIterator();
        while (it.next()) |key| self.allocator.free(key.*);
        self.ids.deinit();
    }

    pub fn isExecuted(self: *InMemoryStore, id: []const u8) !bool {
        return self.ids.contains(id);
    }

    pub fn markExecuted(self: *InMemoryStore, id: []const u8) !void {
        const key = try self.allocator.dupe(u8, id);
        try self.ids.put(key, {});
    }
};
