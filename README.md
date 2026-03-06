# zorm

A lightweight Zig ORM toolkit with a typed query builder, migration/seeder runners, pluggable drivers, and a schema DSL that compiles to SQL per dialect.

Supported SQL dialects:
- postgres
- mysql
- sqlite
- mariadb
- cassandra

## Why zorm

- Small core with explicit APIs
- Dialect-aware SQL generation
- Driver abstraction with concrete adapters
- Migration and seeding runners ready for app workflows
- Schema DSL for `table`, `column`, `index`, and `foreignKey`

## Install / Build

Requirements:
- Zig `0.16.0-dev.2694+74f361a5c` or compatible

Build and test:

```bash
zig build
zig build test
```

Run CLI help:

```bash
zig build run -- help
```

## CLI

Create migration:

```bash
zig build run -- migration:create create_users --dialect postgres
```

Create seeder:

```bash
zig build run -- seed:create seed_users
```

## Quick Start (Library)

```zig
const std = @import("std");
const zorm = @import("zorm");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var qb = zorm.QueryBuilder.init(allocator, .postgres);
    defer qb.deinit();

    _ = try qb.select(&.{ "id", "email" });
    _ = try qb.from("users");
    _ = try qb.whereEq("id", .{ .int = 42 });

    const query = try qb.build();
    defer query.deinit(allocator);

    var pg = zorm.PostgresDriver{
        .allocator = allocator,
        .database = "app_db",
        .user = "app",
        .password = "secret",
    };

    const driver = zorm.Driver.from(@TypeOf(pg), &pg);
    try driver.executeQuery(query);
}
```

## Schema DSL Example

```zig
const std = @import("std");
const zorm = @import("zorm");

pub fn compileUsers(allocator: std.mem.Allocator) !void {
    var cols = [_]zorm.SchemaColumn{
        blk: {
            var c = zorm.schema.column("id", .integer);
            c.primary_key = true;
            c.auto_increment = true;
            c.nullable = false;
            break :blk c;
        },
        blk: {
            var c = zorm.schema.column("email", .varchar(255));
            c.nullable = false;
            break :blk c;
        },
    };

    var email_idx = zorm.schema.index(&.{"email"});
    email_idx.unique = true;

    var users = zorm.schema.table("users", &cols);
    users.indexes = &.{email_idx};

    var compiled = try zorm.schema.compileCreateTable(allocator, .postgres, users);
    defer compiled.deinit();

    for (compiled.statements) |sql| {
        std.debug.print("{s}\n", .{sql});
    }
}
```

## Documentation

Documentation Index:
- [Docs Home](docs/README.md)
- [Overview](docs/overview.md)
- [Installation](docs/installation.md)
- [DRM (Driver Runtime Model)](docs/drm.md)
- [Migrations](docs/migrations.md)
- [Seeders](docs/seeders.md)
- [Query Builder](docs/query-builder.md)
- [Schema Builder](docs/schema-builder.md)
- [CLI](docs/cli.md)
- [Testing](docs/testing.md)

## Status

Core APIs are implemented and tested. Some advanced capabilities (transactions, introspection, prepared statement protocol, richer schema ops) are natural next additions.

## How To Contribute

1. Fork the repository and create a feature branch.
2. Make focused changes with clear commit messages.
3. Run tests locally before opening a PR:

```bash
zig build test
```

4. If you add or change behavior, add or update tests in `src/`.
5. If you add or change public APIs, update docs in `README.md` and `docs/`.
6. Open a pull request with:
   - a short problem statement
   - a summary of what changed
   - notes about dialect-specific behavior (if relevant)
