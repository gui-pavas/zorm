const std = @import("std");
const Dialect = @import("dialect.zig").Dialect;
const Value = @import("value.zig").Value;

pub const Query = struct {
    sql: []const u8,
    params: []Value,

    pub fn deinit(self: *const Query, allocator: std.mem.Allocator) void {
        allocator.free(self.sql);
        allocator.free(self.params);
    }
};

pub const QueryBuilder = struct {
    allocator: std.mem.Allocator,
    dialect: Dialect,
    sql: std.ArrayList(u8),
    params: std.ArrayList(Value),
    has_where: bool,

    pub fn init(allocator: std.mem.Allocator, dialect: Dialect) QueryBuilder {
        return .{
            .allocator = allocator,
            .dialect = dialect,
            .sql = .empty,
            .params = .empty,
            .has_where = false,
        };
    }

    pub fn deinit(self: *QueryBuilder) void {
        self.sql.deinit(self.allocator);
        self.params.deinit(self.allocator);
    }

    pub fn select(self: *QueryBuilder, columns: []const []const u8) !*QueryBuilder {
        try self.sql.appendSlice(self.allocator, "SELECT ");
        for (columns, 0..) |col, idx| {
            const quoted = try self.dialect.quotedIdentifier(self.allocator, col);
            defer self.allocator.free(quoted);
            if (idx > 0) try self.sql.appendSlice(self.allocator, ", ");
            try self.sql.appendSlice(self.allocator, quoted);
        }
        return self;
    }

    pub fn insertInto(self: *QueryBuilder, table: []const u8, columns: []const []const u8) !*QueryBuilder {
        const quoted_table = try self.dialect.quotedIdentifier(self.allocator, table);
        defer self.allocator.free(quoted_table);

        try self.sql.writer(self.allocator).print("INSERT INTO {s} (", .{quoted_table});
        for (columns, 0..) |col, idx| {
            const quoted_col = try self.dialect.quotedIdentifier(self.allocator, col);
            defer self.allocator.free(quoted_col);
            if (idx > 0) try self.sql.appendSlice(self.allocator, ", ");
            try self.sql.appendSlice(self.allocator, quoted_col);
        }
        try self.sql.appendSlice(self.allocator, ") VALUES (");
        for (columns, 0..) |_, idx| {
            if (idx > 0) try self.sql.appendSlice(self.allocator, ", ");
            const placeholder = try self.dialect.placeholder(self.allocator, idx + 1);
            defer self.allocator.free(placeholder);
            try self.sql.appendSlice(self.allocator, placeholder);
        }
        try self.sql.appendSlice(self.allocator, ")");
        return self;
    }

    pub fn update(self: *QueryBuilder, table: []const u8) !*QueryBuilder {
        const quoted_table = try self.dialect.quotedIdentifier(self.allocator, table);
        defer self.allocator.free(quoted_table);
        try self.sql.writer(self.allocator).print("UPDATE {s}", .{quoted_table});
        return self;
    }

    pub fn set(self: *QueryBuilder, assignments: []const Assignment) !*QueryBuilder {
        try self.sql.appendSlice(self.allocator, " SET ");
        for (assignments, 0..) |assignment, idx| {
            const quoted_col = try self.dialect.quotedIdentifier(self.allocator, assignment.column);
            defer self.allocator.free(quoted_col);
            if (idx > 0) try self.sql.appendSlice(self.allocator, ", ");
            const placeholder = try self.dialect.placeholder(self.allocator, self.params.items.len + 1);
            defer self.allocator.free(placeholder);
            try self.sql.writer(self.allocator).print("{s} = {s}", .{ quoted_col, placeholder });
            try self.params.append(self.allocator, assignment.value);
        }
        return self;
    }

    pub fn deleteFrom(self: *QueryBuilder, table: []const u8) !*QueryBuilder {
        const quoted_table = try self.dialect.quotedIdentifier(self.allocator, table);
        defer self.allocator.free(quoted_table);
        try self.sql.writer(self.allocator).print("DELETE FROM {s}", .{quoted_table});
        return self;
    }

    pub fn from(self: *QueryBuilder, table: []const u8) !*QueryBuilder {
        const quoted_table = try self.dialect.quotedIdentifier(self.allocator, table);
        defer self.allocator.free(quoted_table);
        try self.sql.writer(self.allocator).print(" FROM {s}", .{quoted_table});
        return self;
    }

    pub fn whereEq(self: *QueryBuilder, column: []const u8, value: Value) !*QueryBuilder {
        const keyword = if (self.has_where) " AND " else " WHERE ";
        try self.sql.appendSlice(self.allocator, keyword);

        const quoted_col = try self.dialect.quotedIdentifier(self.allocator, column);
        defer self.allocator.free(quoted_col);
        const placeholder = try self.dialect.placeholder(self.allocator, self.params.items.len + 1);
        defer self.allocator.free(placeholder);

        try self.sql.writer(self.allocator).print("{s} = {s}", .{ quoted_col, placeholder });
        try self.params.append(self.allocator, value);
        self.has_where = true;
        return self;
    }

    pub fn orderBy(self: *QueryBuilder, column: []const u8, ascending: bool) !*QueryBuilder {
        const quoted_col = try self.dialect.quotedIdentifier(self.allocator, column);
        defer self.allocator.free(quoted_col);
        try self.sql.writer(self.allocator).print(" ORDER BY {s} {s}", .{ quoted_col, if (ascending) "ASC" else "DESC" });
        return self;
    }

    pub fn limit(self: *QueryBuilder, n: usize) !*QueryBuilder {
        try self.sql.writer(self.allocator).print(" LIMIT {d}", .{n});
        return self;
    }

    pub fn param(self: *QueryBuilder, value: Value) !*QueryBuilder {
        try self.params.append(self.allocator, value);
        return self;
    }

    pub fn build(self: *QueryBuilder) !Query {
        return .{
            .sql = try self.sql.toOwnedSlice(self.allocator),
            .params = try self.params.toOwnedSlice(self.allocator),
        };
    }
};

pub const Assignment = struct {
    column: []const u8,
    value: Value,
};

test "postgres select query with params" {
    var qb = QueryBuilder.init(std.testing.allocator, .postgres);
    defer qb.deinit();

    _ = try qb.select(&.{ "id", "email" });
    _ = try qb.from("users");
    _ = try qb.whereEq("id", .{ .int = 42 });
    _ = try qb.limit(1);

    const query = try qb.build();
    defer query.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("SELECT \"id\", \"email\" FROM \"users\" WHERE \"id\" = $1 LIMIT 1", query.sql);
    try std.testing.expectEqual(@as(usize, 1), query.params.len);
}
