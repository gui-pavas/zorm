![zorm_badge](./assets/badge.png)

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
- Transaction primitives (`BEGIN`/`COMMIT`/`ROLLBACK`)
- Prepared statement protocol (reusable SQL + bound params)
- Introspection hooks (`listTables`, `describeTable`)
- Migration and seeding runners ready for app workflows
- Schema DSL for `table`, `column`, `index`, and `foreignKey`
- Richer schema operations (`drop/rename/add/drop column/index`)

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

### Install Via `zig fetch`


```bash
zig fetch --save https://github.com/<owner>/zorm/archive/refs/tags/v1.0.0.tar.gz
```

Then wire the dependency into your build:

```zig
const dep = b.dependency("zorm", .{
    .target = target,
    .optimize = optimize,
});
b.root_module.addImport("zorm", dep.module("zorm"));
```

And import in code:

```zig
const zorm = @import("zorm");
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

## Transactions + Prepared Statements

```zig
const std = @import("std");
const zorm = @import("zorm");

pub fn runTx(allocator: std.mem.Allocator, driver: zorm.Driver) !void {
    var tx = try driver.beginTransaction();
    errdefer tx.rollback() catch {};

    var stmt = try driver.prepare(allocator, "INSERT INTO users (email, active) VALUES ($1, $2)");
    defer stmt.deinit();

    try stmt.execute(&.{
        .{ .text = "ada@example.com" },
        .{ .bool = true },
    });

    try tx.commit();
}
```

## Introspection

```zig
const std = @import("std");
const zorm = @import("zorm");

pub fn inspect(allocator: std.mem.Allocator, driver: zorm.Driver) !void {
    var tables = try driver.listTables(allocator, null);
    defer tables.deinit();

    for (tables.items) |table_name| {
        std.debug.print("table: {s}\n", .{table_name});

        var cols = try driver.describeTable(allocator, table_name);
        defer cols.deinit();
        for (cols.items) |col| {
            std.debug.print("  - {s} ({s})\n", .{ col.name, col.type_name });
        }
    }
}
```

## Richer Schema Operations

```zig
const std = @import("std");
const zorm = @import("zorm");

pub fn schemaOps(allocator: std.mem.Allocator) !void {
    var add_col = zorm.schema.column("last_login_at", .timestamp);
    add_col.nullable = true;

    const add_sql = try zorm.schema.compileAddColumnSql(allocator, .postgres, "users", add_col);
    defer allocator.free(add_sql);

    const rename_sql = try zorm.schema.compileRenameTableSql(allocator, .postgres, "users", "app_users");
    defer allocator.free(rename_sql);

    const drop_idx_sql = try zorm.schema.compileDropIndexSql(allocator, .postgres, "users_email_uniq", true);
    defer allocator.free(drop_idx_sql);
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
- [Advanced Features](docs/advanced-features.md)
- [Transactions](docs/transactions.md)
- [Prepared Statements](docs/prepared-statements.md)
- [Introspection](docs/introspection.md)
- [Schema Operations](docs/schema-operations.md)
- [CLI](docs/cli.md)
- [Testing](docs/testing.md)

## Status

Core APIs are implemented and tested, including transactions, introspection hooks, prepared statements, and richer schema operations.

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
