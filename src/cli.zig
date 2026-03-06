const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const Dialect = @import("dialect.zig").Dialect;

pub const CommandError = error{
    MissingCommand,
    MissingName,
    InvalidDialect,
    UnknownCommand,
};

var generation_counter: u64 = 0;

pub fn run(allocator: std.mem.Allocator, io: Io, args: []const []const u8, writer: anytype) !void {
    if (args.len < 2) return CommandError.MissingCommand;

    const command = args[1];
    if (std.mem.eql(u8, command, "migration:create")) {
        if (args.len < 3) return CommandError.MissingName;
        const name = args[2];
        const dialect = try parseDialectArg(args[3..]);
        const path = try createMigration(allocator, io, dialect, name);
        defer allocator.free(path);
        try writer.print("created migration: {s}\n", .{path});
        return;
    }

    if (std.mem.eql(u8, command, "seed:create")) {
        if (args.len < 3) return CommandError.MissingName;
        const name = args[2];
        const path = try createSeeder(allocator, io, name);
        defer allocator.free(path);
        try writer.print("created seeder: {s}\n", .{path});
        return;
    }

    if (std.mem.eql(u8, command, "help")) {
        try writeHelp(writer);
        return;
    }

    return CommandError.UnknownCommand;
}

fn parseDialectArg(args: []const []const u8) !Dialect {
    if (args.len < 2) return .postgres;
    if (!std.mem.eql(u8, args[0], "--dialect")) return .postgres;
    return Dialect.fromString(args[1]) orelse CommandError.InvalidDialect;
}

pub fn createMigration(allocator: std.mem.Allocator, io: Io, dialect: Dialect, raw_name: []const u8) ![]const u8 {
    try Io.Dir.cwd().createDirPath(io, "migrations");

    const stamp = nextStamp(raw_name);
    const slug = try slugify(allocator, raw_name);
    defer allocator.free(slug);

    const file_name = try std.fmt.allocPrint(allocator, "{x}_{s}.sql", .{ stamp, slug });
    defer allocator.free(file_name);

    const path = try std.fmt.allocPrint(allocator, "migrations/{s}", .{file_name});

    const content = try migrationTemplate(allocator, dialect, raw_name);
    defer allocator.free(content);

    try Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = content,
    });

    return path;
}

pub fn createSeeder(allocator: std.mem.Allocator, io: Io, raw_name: []const u8) ![]const u8 {
    try Io.Dir.cwd().createDirPath(io, "seeders");

    const stamp = nextStamp(raw_name);
    const slug = try slugify(allocator, raw_name);
    defer allocator.free(slug);

    const file_name = try std.fmt.allocPrint(allocator, "{x}_{s}.sql", .{ stamp, slug });
    defer allocator.free(file_name);

    const path = try std.fmt.allocPrint(allocator, "seeders/{s}", .{file_name});

    const content = try std.fmt.allocPrint(
        allocator,
        "-- Seeder: {s}\n-- Add your INSERT statements below\n\n-- Example:\n-- INSERT INTO users (name, email) VALUES ('Ada', 'ada@example.com');\n",
        .{raw_name},
    );
    defer allocator.free(content);

    try Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = content,
    });

    return path;
}

fn migrationTemplate(allocator: std.mem.Allocator, dialect: Dialect, name: []const u8) ![]const u8 {
    const up = switch (dialect) {
        .postgres => "CREATE TABLE users (id SERIAL PRIMARY KEY);",
        .mysql, .mariadb => "CREATE TABLE users (id BIGINT PRIMARY KEY AUTO_INCREMENT);",
        .sqlite => "CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT);",
        .cassandra => "CREATE TABLE users (id uuid PRIMARY KEY);",
    };

    const down = switch (dialect) {
        .postgres, .mysql, .sqlite, .mariadb, .cassandra => "DROP TABLE users;",
    };

    return std.fmt.allocPrint(
        allocator,
        "-- Migration: {s}\n-- Dialect: {s}\n\n-- UP\n{s}\n\n-- DOWN\n{s}\n",
        .{ name, dialect.name(), up, down },
    );
}

fn slugify(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var prev_dash = false;
    for (input) |ch| {
        if (std.ascii.isAlphanumeric(ch)) {
            try out.append(allocator, std.ascii.toLower(ch));
            prev_dash = false;
            continue;
        }

        if (!prev_dash) {
            try out.append(allocator, '_');
            prev_dash = true;
        }
    }

    if (out.items.len == 0) {
        try out.appendSlice(allocator, "migration");
    }

    while (out.items.len > 0 and out.items[out.items.len - 1] == '_') {
        _ = out.pop();
    }

    return out.toOwnedSlice(allocator);
}

fn nextStamp(name: []const u8) u64 {
    generation_counter +%= 1;
    const pid: u64 = switch (builtin.os.tag) {
        .linux => @intCast(std.os.linux.getpid()),
        else => 0,
    };
    return std.hash.Wyhash.hash(pid ^ generation_counter, name);
}

pub fn writeHelp(writer: anytype) !void {
    try writer.writeAll(
        \\zorm commands:
        \\  zorm migration:create <name> [--dialect postgres|mysql|sqlite|mariadb|cassandra]
        \\  zorm seed:create <name>
        \\  zorm help
        \\
    );
}

test "slugify keeps alnum and underscores" {
    const out = try slugify(std.testing.allocator, "Create Users Table!");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("create_users_table", out);
}
