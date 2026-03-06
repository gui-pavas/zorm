# Migrations

## Types

- `Migration`: `{ id, name, up_sql, down_sql }`
- `MigrationRegistry`: ordered list of migrations
- `MigrationStore`: persistence contract for migration state
- `MigrationRunner`: orchestration of bootstrap/up/down

## Store Contract

`MigrationStore` defines:

- `ensureTable()`
- `isApplied(id)`
- `markApplied(migration)`
- `markRolledBack(id)`

## Runner Behavior

`runner.up(registry)`:

1. Creates/ensures migration metadata table
2. Skips already-applied entries
3. Executes each `up_sql`
4. Marks migration as applied

`runner.down(registry, steps)` rolls back in reverse order using `down_sql`.

## Minimal Example

```zig
var reg = zorm.MigrationRegistry.init(allocator);
defer reg.deinit();

try reg.add(.{
    .id = "202603060001",
    .name = "create_users",
    .up_sql = "CREATE TABLE users (id SERIAL PRIMARY KEY)",
    .down_sql = "DROP TABLE users",
});

var store = zorm.MigrationInMemoryStore.init(allocator);
defer store.deinit();

const runner = zorm.MigrationRunner.init(
    allocator,
    .postgres,
    zorm.Driver.from(@TypeOf(pg), &pg),
    zorm.MigrationStore.from(@TypeOf(store), &store),
);

_ = try runner.up(&reg);
```

## Next

Read [Seeders](seeders.md).
