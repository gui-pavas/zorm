# DRM (Driver Runtime Model)

DRM is zorm's runtime database execution model.

## Generic Driver

`Driver` is a vtable-based abstraction with two operations:

- `execute(sql: []const u8)`
- `executeQuery(query: Query)`

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

Read [Query Builder](query-builder.md) and [Schema Builder](schema-builder.md).
