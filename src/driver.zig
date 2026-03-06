const std = @import("std");
const Dialect = @import("dialect.zig").Dialect;
const Query = @import("query_builder.zig").Query;
const Value = @import("value.zig").Value;

pub const DriverError = error{
    ExternalCommandFailed,
    MissingDatabasePath,
    UnsupportedFeature,
};

pub const Driver = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        execute: *const fn (ctx: *anyopaque, sql: []const u8) anyerror!void,
        executeQuery: *const fn (ctx: *anyopaque, query: Query) anyerror!void,
    };

    pub fn execute(self: Driver, sql: []const u8) !void {
        return self.vtable.execute(self.ctx, sql);
    }

    pub fn executeQuery(self: Driver, query: Query) !void {
        return self.vtable.executeQuery(self.ctx, query);
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
        };

        return .{
            .ctx = value,
            .vtable = &.{
                .execute = vtable.execute,
                .executeQuery = vtable.executeQuery,
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
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .env_map = env_map,
        .max_output_bytes = 1024 * 1024,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code == 0) return,
        else => {},
    }

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
