# Schema Operations

Beyond `compileCreateTable`, zorm supports standalone schema operation compilers.

## Supported Operations

- `compileDropTableSql(...)`
- `compileRenameTableSql(...)`
- `compileAddColumnSql(...)`
- `compileDropColumnSql(...)`
- `compileRenameColumnSql(...)`
- `compileCreateIndexOnTableSql(...)`
- `compileDropIndexSql(...)`

## Example

```zig
var c = zorm.schema.column("last_login_at", .timestamp);
c.nullable = true;

const add_col = try zorm.schema.compileAddColumnSql(allocator, .postgres, "users", c);
defer allocator.free(add_col);

const rename_col = try zorm.schema.compileRenameColumnSql(allocator, .postgres, "users", "full_name", "name");
defer allocator.free(rename_col);

const drop_idx = try zorm.schema.compileDropIndexSql(allocator, .postgres, "users_email_uniq", true);
defer allocator.free(drop_idx);
```

## Dialect Notes

- `compileDropColumnSql` is unsupported for `sqlite` and `cassandra`.
- `compileRenameColumnSql` is unsupported for `cassandra`.
- `DROP TABLE ... CASCADE` is emitted only for postgres when requested.
