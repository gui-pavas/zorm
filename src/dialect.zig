const std = @import("std");

pub const Dialect = enum {
    postgres,
    mysql,
    sqlite,
    mariadb,
    cassandra,

    pub fn fromString(raw: []const u8) ?Dialect {
        if (std.mem.eql(u8, raw, "postgres") or std.mem.eql(u8, raw, "postgresql") or std.mem.eql(u8, raw, "pg")) return .postgres;
        if (std.mem.eql(u8, raw, "mysql")) return .mysql;
        if (std.mem.eql(u8, raw, "sqlite") or std.mem.eql(u8, raw, "sqlite3")) return .sqlite;
        if (std.mem.eql(u8, raw, "mariadb")) return .mariadb;
        if (std.mem.eql(u8, raw, "cassandra")) return .cassandra;
        return null;
    }

    pub fn name(self: Dialect) []const u8 {
        return switch (self) {
            .postgres => "postgres",
            .mysql => "mysql",
            .sqlite => "sqlite",
            .mariadb => "mariadb",
            .cassandra => "cassandra",
        };
    }

    pub fn placeholder(self: Dialect, allocator: std.mem.Allocator, index: usize) ![]const u8 {
        return switch (self) {
            .postgres => std.fmt.allocPrint(allocator, "${d}", .{index}),
            .mysql, .sqlite, .mariadb, .cassandra => allocator.dupe(u8, "?"),
        };
    }

    pub fn quotedIdentifier(self: Dialect, allocator: std.mem.Allocator, ident: []const u8) ![]const u8 {
        return switch (self) {
            .postgres, .sqlite => std.fmt.allocPrint(allocator, "\"{s}\"", .{ident}),
            .mysql, .mariadb => std.fmt.allocPrint(allocator, "`{s}`", .{ident}),
            .cassandra => allocator.dupe(u8, ident),
        };
    }

    pub fn migrationsTableSql(self: Dialect) []const u8 {
        return switch (self) {
            .postgres =>
            \\CREATE TABLE IF NOT EXISTS zorm_migrations (
            \\  id TEXT PRIMARY KEY,
            \\  name TEXT NOT NULL,
            \\  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            \\);
            ,
            .mysql, .mariadb =>
            \\CREATE TABLE IF NOT EXISTS zorm_migrations (
            \\  id VARCHAR(64) PRIMARY KEY,
            \\  name VARCHAR(255) NOT NULL,
            \\  applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
            \\);
            ,
            .sqlite =>
            \\CREATE TABLE IF NOT EXISTS zorm_migrations (
            \\  id TEXT PRIMARY KEY,
            \\  name TEXT NOT NULL,
            \\  applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            \\);
            ,
            .cassandra =>
            \\CREATE TABLE IF NOT EXISTS zorm_migrations (
            \\  id text PRIMARY KEY,
            \\  name text,
            \\  applied_at timestamp
            \\);
            ,
        };
    }
};

test "from string" {
    try std.testing.expectEqual(Dialect.postgres, Dialect.fromString("pg").?);
    try std.testing.expect(Dialect.fromString("unknown") == null);
}
