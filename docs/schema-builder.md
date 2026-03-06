# Schema Builder (DSL)

The schema module compiles structured table definitions into SQL statements.

## DSL Primitives

- `schema.table(name, columns)`
- `schema.column(name, type)`
- `schema.index(columns)`
- `schema.foreignKey(column, ref_table, ref_column)`

## Compile API

```zig
const compiled = try zorm.schema.compileCreateTable(allocator, .postgres, spec);
defer compiled.deinit();
```

`compiled.statements` contains:

1. `CREATE TABLE ...`
2. `CREATE INDEX ...` (one per index)

Additional schema SQL compilers:

- `compileDropTableSql(...)`
- `compileRenameTableSql(...)`
- `compileAddColumnSql(...)`
- `compileDropColumnSql(...)`
- `compileRenameColumnSql(...)`
- `compileCreateIndexOnTableSql(...)`
- `compileDropIndexSql(...)`

## Example

```zig
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

var idx = zorm.schema.index(&.{"email"});
idx.unique = true;

var spec = zorm.schema.table("users", &cols);
spec.indexes = &.{idx};

var compiled = try zorm.schema.compileCreateTable(allocator, .postgres, spec);
defer compiled.deinit();
```

## Dialect Notes

- Postgres: `SERIAL` / `BIGSERIAL` for auto-increment integer/bigint.
- SQLite: `INTEGER PRIMARY KEY AUTOINCREMENT` handling.
- Cassandra: requires at least one primary key; certain FK/index features are restricted.
- `compileDropColumnSql` is unsupported for `sqlite` and `cassandra`.
- `compileRenameColumnSql` is unsupported for `cassandra`.

## Next

See [Schema Operations](schema-operations.md) for alter/drop/rename helpers, then [Migrations](migrations.md) for execution flow.
