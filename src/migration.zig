const std = @import("std");
const Dialect = @import("dialect.zig").Dialect;
const Driver = @import("driver.zig").Driver;

pub const Migration = struct {
    id: []const u8,
    name: []const u8,
    up_sql: []const u8,
    down_sql: []const u8,
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(Migration),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .items = .empty,
        };
    }

    pub fn deinit(self: *Registry) void {
        self.items.deinit(self.allocator);
    }

    pub fn add(self: *Registry, migration: Migration) !void {
        try self.items.append(self.allocator, migration);
    }
};

pub const Store = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        ensureTable: *const fn (ctx: *anyopaque) anyerror!void,
        isApplied: *const fn (ctx: *anyopaque, id: []const u8) anyerror!bool,
        markApplied: *const fn (ctx: *anyopaque, migration: Migration) anyerror!void,
        markRolledBack: *const fn (ctx: *anyopaque, id: []const u8) anyerror!void,
    };

    pub fn ensureTable(self: Store) !void {
        return self.vtable.ensureTable(self.ctx);
    }

    pub fn isApplied(self: Store, id: []const u8) !bool {
        return self.vtable.isApplied(self.ctx, id);
    }

    pub fn markApplied(self: Store, migration: Migration) !void {
        return self.vtable.markApplied(self.ctx, migration);
    }

    pub fn markRolledBack(self: Store, id: []const u8) !void {
        return self.vtable.markRolledBack(self.ctx, id);
    }

    pub fn from(comptime T: type, value: *T) Store {
        const table = struct {
            fn ensureTable(ctx: *anyopaque) anyerror!void {
                const ptr: *T = @ptrCast(@alignCast(ctx));
                try ptr.ensureTable();
            }

            fn isApplied(ctx: *anyopaque, id: []const u8) anyerror!bool {
                const ptr: *T = @ptrCast(@alignCast(ctx));
                return ptr.isApplied(id);
            }

            fn markApplied(ctx: *anyopaque, migration: Migration) anyerror!void {
                const ptr: *T = @ptrCast(@alignCast(ctx));
                try ptr.markApplied(migration);
            }

            fn markRolledBack(ctx: *anyopaque, id: []const u8) anyerror!void {
                const ptr: *T = @ptrCast(@alignCast(ctx));
                try ptr.markRolledBack(id);
            }
        };

        return .{
            .ctx = value,
            .vtable = &.{
                .ensureTable = table.ensureTable,
                .isApplied = table.isApplied,
                .markApplied = table.markApplied,
                .markRolledBack = table.markRolledBack,
            },
        };
    }
};

pub const Runner = struct {
    allocator: std.mem.Allocator,
    dialect: Dialect,
    driver: Driver,
    store: Store,

    pub fn init(allocator: std.mem.Allocator, dialect: Dialect, driver: Driver, store: Store) Runner {
        return .{
            .allocator = allocator,
            .dialect = dialect,
            .driver = driver,
            .store = store,
        };
    }

    pub fn bootstrap(self: Runner) !void {
        _ = self.allocator;
        try self.driver.execute(self.dialect.migrationsTableSql());
        try self.store.ensureTable();
    }

    pub fn up(self: Runner, registry: *const Registry) !usize {
        try self.bootstrap();
        var applied_count: usize = 0;

        for (registry.items.items) |m| {
            if (try self.store.isApplied(m.id)) continue;
            try self.driver.execute(m.up_sql);
            try self.store.markApplied(m);
            applied_count += 1;
        }

        return applied_count;
    }

    pub fn down(self: Runner, registry: *const Registry, steps: usize) !usize {
        try self.bootstrap();
        var rolled: usize = 0;

        var i: usize = registry.items.items.len;
        while (i > 0 and rolled < steps) {
            i -= 1;
            const m = registry.items.items[i];
            if (!try self.store.isApplied(m.id)) continue;
            try self.driver.execute(m.down_sql);
            try self.store.markRolledBack(m.id);
            rolled += 1;
        }

        return rolled;
    }
};

pub const InMemoryStore = struct {
    allocator: std.mem.Allocator,
    applied_ids: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator) InMemoryStore {
        return .{
            .allocator = allocator,
            .applied_ids = .init(allocator),
        };
    }

    pub fn deinit(self: *InMemoryStore) void {
        var it = self.applied_ids.keyIterator();
        while (it.next()) |key| self.allocator.free(key.*);
        self.applied_ids.deinit();
    }

    pub fn ensureTable(self: *InMemoryStore) !void {
        _ = self;
    }

    pub fn isApplied(self: *InMemoryStore, id: []const u8) !bool {
        return self.applied_ids.contains(id);
    }

    pub fn markApplied(self: *InMemoryStore, migration: Migration) !void {
        const key = try self.allocator.dupe(u8, migration.id);
        try self.applied_ids.put(key, {});
    }

    pub fn markRolledBack(self: *InMemoryStore, id: []const u8) !void {
        const removed = self.applied_ids.fetchRemove(id);
        if (removed) |entry| self.allocator.free(entry.key);
    }
};

test "runner applies pending migrations" {
    var logger = @import("driver.zig").LoggingDriver.init(std.testing.allocator);
    defer logger.deinit();

    var store_impl = InMemoryStore.init(std.testing.allocator);
    defer store_impl.deinit();

    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.add(.{
        .id = "202603060001",
        .name = "create_users",
        .up_sql = "CREATE TABLE users (id INTEGER PRIMARY KEY)",
        .down_sql = "DROP TABLE users",
    });

    const runner = Runner.init(
        std.testing.allocator,
        .sqlite,
        Driver.from(@TypeOf(logger), &logger),
        Store.from(@TypeOf(store_impl), &store_impl),
    );

    const n = try runner.up(&registry);
    try std.testing.expectEqual(@as(usize, 1), n);
}
