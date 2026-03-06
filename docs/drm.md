# DRM (Driver Runtime Model)

DRM is zorm's runtime database execution model.

## Generic Driver

`Driver` is a vtable-based abstraction with query execution plus transaction/introspection helpers.

- `execute(sql: []const u8)`
- `executeQuery(query: Query)`
- `beginTransaction() -> Transaction`
- `prepare(allocator, sql) -> PreparedStatement`
- `listTables(allocator, schema)`
- `describeTable(allocator, table)`

Any backend can be adapted through:

```zig
const d = zorm.Driver.from(@TypeOf(impl), &impl);
```

Your `impl` must provide matching methods.

## Built-in Adapters

- `PostgresDriver` (`psql`)
- `MySqlDriver` (`mysql`)
- `MariaDbDriver` (`mariadb`)
- `SqliteDriver` (`sqlite3`)
- `CassandraDriver` (`cqlsh`)

These adapters execute SQL by invoking native database CLI tools.

## Query Rendering

`renderQuery(allocator, dialect, query)` converts placeholders to SQL literals.

- Postgres placeholders: `$1`, `$2`, ...
- Other dialects: `?`

Literal formatting includes string escaping and dialect-specific blob literal formats.

## Transactions

`beginTransaction()` sends `BEGIN` and returns a `Transaction` handle:

- `commit()` -> sends `COMMIT`
- `rollback()` -> sends `ROLLBACK`

## Prepared Statement Protocol

`prepare(allocator, sql)` creates a reusable statement object:

```zig
var stmt = try driver.prepare(allocator, "SELECT * FROM users WHERE id = $1");
defer stmt.deinit();
try stmt.execute(&.{.{ .int = 1 }});
```

The protocol keeps SQL reusable and binds a fresh parameter list per execute call.

## Introspection

Use these hooks for runtime schema inspection:

- `listTables(allocator, schema)` returns table names.
- `describeTable(allocator, table)` returns `ColumnInfo` entries.

Driver implementations can provide these methods; otherwise `error.UnsupportedFeature` is returned.

## Example

```zig
var pg = zorm.PostgresDriver{
    .allocator = allocator,
    .database = "app_db",
    .user = "app",
    .password = "secret",
};

const driver = zorm.Driver.from(@TypeOf(pg), &pg);
try driver.execute("SELECT 1");
```

## Next

Read [Transactions](transactions.md), [Prepared Statements](prepared-statements.md), and [Introspection](introspection.md).
