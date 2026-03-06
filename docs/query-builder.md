# Query Builder

`QueryBuilder` builds SQL and parameter lists in a dialect-aware way.

## Supported Builder Operations

- `select(columns)`
- `from(table)`
- `insertInto(table, columns)`
- `update(table)`
- `set(assignments)`
- `deleteFrom(table)`
- `whereEq(column, value)`
- `orderBy(column, asc)`
- `limit(n)`
- `param(value)`
- `build()`

## Example

```zig
var qb = zorm.QueryBuilder.init(allocator, .postgres);
defer qb.deinit();

_ = try qb.select(&.{ "id", "email" });
_ = try qb.from("users");
_ = try qb.whereEq("id", .{ .int = 42 });
_ = try qb.limit(1);

const q = try qb.build();
defer q.deinit(allocator);
```

For postgres, placeholders become `$1`, `$2`, etc.
For mysql/sqlite/mariadb/cassandra, placeholders are `?`.

## Next

Read [Schema Builder (DSL)](schema-builder.md).
