# Introspection

Introspection APIs expose runtime schema metadata through the driver abstraction.

## API

- `driver.listTables(allocator, schema)`
- `driver.describeTable(allocator, table)`

## Example

```zig
var tables = try driver.listTables(allocator, null);
defer tables.deinit();

for (tables.items) |table_name| {
    var cols = try driver.describeTable(allocator, table_name);
    defer cols.deinit();
}
```

`describeTable` returns `ColumnInfo` values with:

- `name`
- `type_name`
- `nullable`
- `default_value_sql`
- `is_primary_key`

## Behavior Notes

- Drivers can implement these hooks optionally.
- If unsupported by a driver, calls return `error.UnsupportedFeature`.
