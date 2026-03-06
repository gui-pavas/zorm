const std = @import("std");
const Dialect = @import("dialect.zig").Dialect;
const Query = @import("query_builder.zig").Query;
const Value = @import("value.zig").Value;

pub const DriverError = error{
    ExternalCommandFailed,
    MissingDatabasePath,
    UnsupportedFeature,
    TransactionAlreadyClosed,
};

pub const StringList = struct {
    allocator: std.mem.Allocator,
    items: []const []const u8,

    pub fn deinit(self: *StringList) void {
        for (self.items) |item| self.allocator.free(item);
        self.allocator.free(self.items);
    }
};

pub const ColumnInfo = struct {
    name: []const u8,
    type_name: []const u8,
    nullable: bool = true,
    default_value_sql: ?[]const u8 = null,
    is_primary_key: bool = false,
};

pub const ColumnInfoList = struct {
    allocator: std.mem.Allocator,
    items: []const ColumnInfo,

    pub fn deinit(self: *ColumnInfoList) void {
        for (self.items) |item| {
            self.allocator.free(item.name);
            self.allocator.free(item.type_name);
            if (item.default_value_sql) |value| self.allocator.free(value);
        }
        self.allocator.free(self.items);
    }
};

pub const PreparedStatement = struct {
    allocator: std.mem.Allocator,
    driver: Driver,
    sql: []const u8,

    pub fn deinit(self: *PreparedStatement) void {
        self.allocator.free(self.sql);
    }

    pub fn execute(self: *const PreparedStatement, params: []const Value) !void {
        const copied_params = try self.allocator.dupe(Value, params);
        defer self.allocator.free(copied_params);

        const query = Query{
            .sql = self.sql,
            .params = copied_params,
        };
        try self.driver.executeQuery(query);
    }
};

pub const Transaction = struct {
    driver: Driver,
    active: bool = true,

    pub fn commit(self: *Transaction) !void {
        if (!self.active) return DriverError.TransactionAlreadyClosed;
        try self.driver.execute("COMMIT");
        self.active = false;
    }

    pub fn rollback(self: *Transaction) !void {
        if (!self.active) return DriverError.TransactionAlreadyClosed;
        try self.driver.execute("ROLLBACK");
        self.active = false;
    }
};

pub const Driver = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        execute: *const fn (ctx: *anyopaque, sql: []const u8) anyerror!void,
        executeQuery: *const fn (ctx: *anyopaque, query: Query) anyerror!void,
        listTables: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, schema: ?[]const u8) anyerror!StringList,
        describeTable: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, table: []const u8) anyerror!ColumnInfoList,
    };

    pub fn execute(self: Driver, sql: []const u8) !void {
        return self.vtable.execute(self.ctx, sql);
    }

    pub fn executeQuery(self: Driver, query: Query) !void {
        return self.vtable.executeQuery(self.ctx, query);
    }

    pub fn beginTransaction(self: Driver) !Transaction {
        try self.execute("BEGIN");
        return .{ .driver = self };
    }

    pub fn prepare(self: Driver, allocator: std.mem.Allocator, sql: []const u8) !PreparedStatement {
        return .{
            .allocator = allocator,
            .driver = self,
            .sql = try allocator.dupe(u8, sql),
        };
    }

    pub fn listTables(self: Driver, allocator: std.mem.Allocator, schema: ?[]const u8) !StringList {
        return self.vtable.listTables(self.ctx, allocator, schema);
    }

    pub fn describeTable(self: Driver, allocator: std.mem.Allocator, table: []const u8) !ColumnInfoList {
        return self.vtable.describeTable(self.ctx, allocator, table);
    }

    pub fn from(comptime T: type, value: *T) Driver {
        const vtable = struct {
            fn execute(ctx: *anyopaque, sql: []const u8) anyerror!void {
                const ptr: *T = @ptrCast(@alignCast(ctx));
                try ptr.execute(sql);
            }

            fn executeQuery(ctx: *anyopaque, query: Query) anyerror!void {
                const ptr: *T = @ptrCast(@alignCast(ctx));
                try ptr.executeQuery(query);
            }

            fn listTables(ctx: *anyopaque, allocator: std.mem.Allocator, schema: ?[]const u8) anyerror!StringList {
                const ptr: *T = @ptrCast(@alignCast(ctx));
                if (@hasDecl(T, "listTables")) {
                    return ptr.listTables(allocator, schema);
                }
                return DriverError.UnsupportedFeature;
            }

            fn describeTable(ctx: *anyopaque, allocator: std.mem.Allocator, table: []const u8) anyerror!ColumnInfoList {
                const ptr: *T = @ptrCast(@alignCast(ctx));
                if (@hasDecl(T, "describeTable")) {
                    return ptr.describeTable(allocator, table);
                }
                return DriverError.UnsupportedFeature;
            }
        };

        return .{
            .ctx = value,
            .vtable = &.{
                .execute = vtable.execute,
                .executeQuery = vtable.executeQuery,
                .listTables = vtable.listTables,
                .describeTable = vtable.describeTable,
            },
        };
    }
};

pub fn renderQuery(allocator: std.mem.Allocator, dialect: Dialect, query: Query) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    switch (dialect) {
        .postgres => {
            var i: usize = 0;
            while (i < query.sql.len) {
                if (query.sql[i] == '$') {
                    const start = i + 1;
                    var j = start;
                    while (j < query.sql.len and std.ascii.isDigit(query.sql[j])) : (j += 1) {}

                    if (j > start) {
                        const idx = std.fmt.parseInt(usize, query.sql[start..j], 10) catch {
                            try out.append(allocator, query.sql[i]);
                            i += 1;
                            continue;
                        };

                        if (idx == 0 or idx > query.params.len) return error.InvalidParameterIndex;

                        const lit = try toSqlLiteral(allocator, dialect, query.params[idx - 1]);
                        defer allocator.free(lit);
                        try out.appendSlice(allocator, lit);
                        i = j;
                        continue;
                    }
                }

                try out.append(allocator, query.sql[i]);
                i += 1;
            }
        },
        .mysql, .sqlite, .mariadb, .cassandra => {
            var param_idx: usize = 0;
            for (query.sql) |ch| {
                if (ch == '?') {
                    if (param_idx >= query.params.len) return error.InvalidParameterIndex;
                    const lit = try toSqlLiteral(allocator, dialect, query.params[param_idx]);
                    defer allocator.free(lit);
                    try out.appendSlice(allocator, lit);
                    param_idx += 1;
                    continue;
                }
                try out.append(allocator, ch);
            }
            if (param_idx != query.params.len) return error.InvalidParameterIndex;
        },
    }

    return out.toOwnedSlice(allocator);
}

fn toSqlLiteral(allocator: std.mem.Allocator, dialect: Dialect, value: Value) ![]const u8 {
    return switch (value) {
        .null => allocator.dupe(u8, "NULL"),
        .bool => |v| allocator.dupe(u8, if (v) "TRUE" else "FALSE"),
        .int => |v| std.fmt.allocPrint(allocator, "{d}", .{v}),
        .float => |v| std.fmt.allocPrint(allocator, "{d}", .{v}),
        .text => |v| quoteTextLiteral(allocator, v),
        .blob => |v| quoteBlobLiteral(allocator, dialect, v),
    };
}

fn quoteTextLiteral(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try out.append(allocator, '\'');
    for (value) |ch| {
        if (ch == '\'') {
            try out.appendSlice(allocator, "''");
        } else {
            try out.append(allocator, ch);
        }
    }
    try out.append(allocator, '\'');

    return out.toOwnedSlice(allocator);
}

fn quoteBlobLiteral(allocator: std.mem.Allocator, dialect: Dialect, value: []const u8) ![]const u8 {
    const hex = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(value)});
    defer allocator.free(hex);

    return switch (dialect) {
        .postgres => std.fmt.allocPrint(allocator, "'\\x{s}'::bytea", .{hex}),
        .mysql, .mariadb => std.fmt.allocPrint(allocator, "X'{s}'", .{hex}),
        .sqlite => std.fmt.allocPrint(allocator, "x'{s}'", .{hex}),
        .cassandra => std.fmt.allocPrint(allocator, "0x{s}", .{hex}),
    };
}

fn runExternal(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    env_map: ?*const std.process.EnvMap,
) !void {
    const stdout = try runExternalCapture(allocator, argv, env_map);
    allocator.free(stdout);
}

fn runExternalCapture(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    env_map: ?*const std.process.EnvMap,
) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .env_map = env_map,
        .max_output_bytes = 1024 * 1024,
    });
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code == 0) return result.stdout,
        else => {},
    }

    allocator.free(result.stdout);
    return DriverError.ExternalCommandFailed;
}

pub const PostgresDriver = struct {
    allocator: std.mem.Allocator,
    executable: []const u8 = "psql",
    connection_uri: ?[]const u8 = null,
    database: ?[]const u8 = null,
    host: ?[]const u8 = null,
    port: ?u16 = null,
    user: ?[]const u8 = null,
    password: ?[]const u8 = null,

    pub fn execute(self: *PostgresDriver, sql: []const u8) !void {
        var argv = std.ArrayList([]const u8).empty;
        defer argv.deinit(self.allocator);

        try argv.append(self.allocator, self.executable);

        if (self.connection_uri) |uri| {
            try argv.append(self.allocator, uri);
        } else {
            if (self.host) |host| {
                try argv.appendSlice(self.allocator, &.{ "-h", host });
            }
            if (self.port) |port| {
                const port_value = try std.fmt.allocPrint(self.allocator, "{d}", .{port});
                defer self.allocator.free(port_value);
                try argv.appendSlice(self.allocator, &.{ "-p", port_value });
            }
            if (self.user) |user| {
                try argv.appendSlice(self.allocator, &.{ "-U", user });
            }
            if (self.database) |database| {
                try argv.appendSlice(self.allocator, &.{ "-d", database });
            }
        }

        try argv.appendSlice(self.allocator, &.{ "-v", "ON_ERROR_STOP=1", "-q", "-c", sql });

        var env_storage: std.process.EnvMap = .init(self.allocator);
        defer env_storage.deinit();

        const env_ptr: ?*const std.process.EnvMap = if (self.password) |pwd| blk: {
            try env_storage.put("PGPASSWORD", pwd);
            break :blk &env_storage;
        } else null;

        try runExternal(self.allocator, argv.items, env_ptr);
    }

    pub fn executeQuery(self: *PostgresDriver, query: Query) !void {
        const sql = try renderQuery(self.allocator, .postgres, query);
        defer self.allocator.free(sql);
        try self.execute(sql);
    }
};

pub const MySqlDriver = struct {
    allocator: std.mem.Allocator,
    executable: []const u8 = "mysql",
    database: ?[]const u8 = null,
    host: ?[]const u8 = null,
    port: ?u16 = null,
    user: ?[]const u8 = null,
    password: ?[]const u8 = null,

    pub fn execute(self: *MySqlDriver, sql: []const u8) !void {
        var argv = std.ArrayList([]const u8).empty;
        defer argv.deinit(self.allocator);

        try argv.append(self.allocator, self.executable);
        try argv.appendSlice(self.allocator, &.{ "--batch", "--raw", "--silent" });

        if (self.host) |host| try argv.appendSlice(self.allocator, &.{ "--host", host });
        if (self.port) |port| {
            const port_value = try std.fmt.allocPrint(self.allocator, "{d}", .{port});
            defer self.allocator.free(port_value);
            try argv.appendSlice(self.allocator, &.{ "--port", port_value });
        }
        if (self.user) |user| try argv.appendSlice(self.allocator, &.{ "--user", user });
        if (self.database) |database| try argv.appendSlice(self.allocator, &.{ "--database", database });

        try argv.appendSlice(self.allocator, &.{ "--execute", sql });

        var env_storage: std.process.EnvMap = .init(self.allocator);
        defer env_storage.deinit();

        const env_ptr: ?*const std.process.EnvMap = if (self.password) |pwd| blk: {
            try env_storage.put("MYSQL_PWD", pwd);
            break :blk &env_storage;
        } else null;

        try runExternal(self.allocator, argv.items, env_ptr);
    }

    pub fn executeQuery(self: *MySqlDriver, query: Query) !void {
        const sql = try renderQuery(self.allocator, .mysql, query);
        defer self.allocator.free(sql);
        try self.execute(sql);
    }
};

pub const MariaDbDriver = struct {
    allocator: std.mem.Allocator,
    executable: []const u8 = "mariadb",
    database: ?[]const u8 = null,
    host: ?[]const u8 = null,
    port: ?u16 = null,
    user: ?[]const u8 = null,
    password: ?[]const u8 = null,

    pub fn execute(self: *MariaDbDriver, sql: []const u8) !void {
        var base = MySqlDriver{
            .allocator = self.allocator,
            .executable = self.executable,
            .database = self.database,
            .host = self.host,
            .port = self.port,
            .user = self.user,
            .password = self.password,
        };
        try base.execute(sql);
    }

    pub fn executeQuery(self: *MariaDbDriver, query: Query) !void {
        const sql = try renderQuery(self.allocator, .mariadb, query);
        defer self.allocator.free(sql);
        try self.execute(sql);
    }
};

pub const SqliteDriver = struct {
    allocator: std.mem.Allocator,
    executable: []const u8 = "sqlite3",
    database_path: []const u8,

    pub fn execute(self: *SqliteDriver, sql: []const u8) !void {
        if (self.database_path.len == 0) return DriverError.MissingDatabasePath;

        const argv = [_][]const u8{ self.executable, self.database_path, sql };
        try runExternal(self.allocator, &argv, null);
    }

    pub fn executeQuery(self: *SqliteDriver, query: Query) !void {
        const sql = try renderQuery(self.allocator, .sqlite, query);
        defer self.allocator.free(sql);
        try self.execute(sql);
    }
};

pub const CassandraDriver = struct {
    allocator: std.mem.Allocator,
    executable: []const u8 = "cqlsh",
    host: ?[]const u8 = null,
    port: ?u16 = null,
    keyspace: ?[]const u8 = null,
    user: ?[]const u8 = null,
    password: ?[]const u8 = null,

    pub fn execute(self: *CassandraDriver, sql: []const u8) !void {
        var argv = std.ArrayList([]const u8).empty;
        defer argv.deinit(self.allocator);

        try argv.append(self.allocator, self.executable);
        if (self.host) |host| try argv.append(self.allocator, host);

        if (self.port) |port| {
            const port_value = try std.fmt.allocPrint(self.allocator, "{d}", .{port});
            defer self.allocator.free(port_value);
            try argv.appendSlice(self.allocator, &.{ "--port", port_value });
        }

        if (self.user) |user| try argv.appendSlice(self.allocator, &.{ "--username", user });
        if (self.password) |password| try argv.appendSlice(self.allocator, &.{ "--password", password });
        if (self.keyspace) |keyspace| try argv.appendSlice(self.allocator, &.{ "--keyspace", keyspace });

        try argv.appendSlice(self.allocator, &.{ "-e", sql });
        try runExternal(self.allocator, argv.items, null);
    }

    pub fn executeQuery(self: *CassandraDriver, query: Query) !void {
        const sql = try renderQuery(self.allocator, .cassandra, query);
        defer self.allocator.free(sql);
        try self.execute(sql);
    }
};

pub const LoggingDriver = struct {
    logs: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) LoggingDriver {
        return .{
            .logs = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LoggingDriver) void {
        for (self.logs.items) |entry| self.allocator.free(entry);
        self.logs.deinit(self.allocator);
    }

    pub fn execute(self: *LoggingDriver, sql: []const u8) !void {
        try self.logs.append(self.allocator, try self.allocator.dupe(u8, sql));
    }

    pub fn executeQuery(self: *LoggingDriver, query: Query) !void {
        try self.logs.append(self.allocator, try self.allocator.dupe(u8, query.sql));
    }

    pub fn listTables(self: *LoggingDriver, allocator: std.mem.Allocator, schema: ?[]const u8) !StringList {
        _ = self;
        _ = schema;
        const items = try allocator.alloc([]const u8, 0);
        return .{
            .allocator = allocator,
            .items = items,
        };
    }

    pub fn describeTable(self: *LoggingDriver, allocator: std.mem.Allocator, table: []const u8) !ColumnInfoList {
        _ = self;
        _ = table;
        const items = try allocator.alloc(ColumnInfo, 0);
        return .{
            .allocator = allocator,
            .items = items,
        };
    }
};

test "renderQuery replaces postgres placeholders" {
    const q = Query{
        .sql = "SELECT * FROM users WHERE id = $1 AND email = $2",
        .params = &.{ .{ .int = 42 }, .{ .text = "ada@example.com" } },
    };

    const sql = try renderQuery(std.testing.allocator, .postgres, q);
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings(
        "SELECT * FROM users WHERE id = 42 AND email = 'ada@example.com'",
        sql,
    );
}

test "renderQuery replaces question mark placeholders" {
    const q = Query{
        .sql = "INSERT INTO users (id, name, active) VALUES (?, ?, ?)",
        .params = &.{ .{ .int = 7 }, .{ .text = "Ada" }, .{ .bool = true } },
    };

    const sql = try renderQuery(std.testing.allocator, .sqlite, q);
    defer std.testing.allocator.free(sql);

    try std.testing.expectEqualStrings(
        "INSERT INTO users (id, name, active) VALUES (7, 'Ada', TRUE)",
        sql,
    );
}

test "driver prepared statement executes with params" {
    var logger = LoggingDriver.init(std.testing.allocator);
    defer logger.deinit();

    const driver = Driver.from(@TypeOf(logger), &logger);
    var stmt = try driver.prepare(std.testing.allocator, "SELECT * FROM users WHERE id = $1");
    defer stmt.deinit();

    try stmt.execute(&.{.{ .int = 99 }});

    try std.testing.expectEqual(@as(usize, 1), logger.logs.items.len);
    try std.testing.expectEqualStrings("SELECT * FROM users WHERE id = $1", logger.logs.items[0]);
}

test "driver transaction commit emits commands" {
    var logger = LoggingDriver.init(std.testing.allocator);
    defer logger.deinit();

    const driver = Driver.from(@TypeOf(logger), &logger);
    var tx = try driver.beginTransaction();
    try tx.commit();

    try std.testing.expectEqual(@as(usize, 2), logger.logs.items.len);
    try std.testing.expectEqualStrings("BEGIN", logger.logs.items[0]);
    try std.testing.expectEqualStrings("COMMIT", logger.logs.items[1]);
}

test "driver introspection falls back to implementation" {
    var logger = LoggingDriver.init(std.testing.allocator);
    defer logger.deinit();

    const driver = Driver.from(@TypeOf(logger), &logger);

    var tables = try driver.listTables(std.testing.allocator, null);
    defer tables.deinit();
    try std.testing.expectEqual(@as(usize, 0), tables.items.len);

    var columns = try driver.describeTable(std.testing.allocator, "users");
    defer columns.deinit();
    try std.testing.expectEqual(@as(usize, 0), columns.items.len);
}
