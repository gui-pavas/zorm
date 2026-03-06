# Prepared Statements

zorm includes a lightweight prepared statement protocol for reusing SQL with different parameter sets.

## API

- `driver.prepare(allocator, sql) -> PreparedStatement`
- `PreparedStatement.execute(params)`
- `PreparedStatement.deinit()`

## Example

```zig
var stmt = try driver.prepare(allocator, "INSERT INTO users (email, active) VALUES ($1, $2)");
defer stmt.deinit();

try stmt.execute(&.{
    .{ .text = "ada@example.com" },
    .{ .bool = true },
});
```

## Behavior Notes

- The statement stores SQL once and accepts a new `[]Value` param list on each call.
- Placeholder style is still dialect-aware (`$1`... for postgres, `?` for other dialects).
- Current protocol delegates execution to `executeQuery`.
