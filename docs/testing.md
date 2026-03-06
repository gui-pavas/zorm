# Testing

Run all test targets:

```bash
zig build test
```

## Coverage Areas

- Dialect parsing and placeholder behavior
- QueryBuilder SQL generation
- Driver query rendering
- Migration runner logic
- Schema compiler behavior

## Recommended workflow

1. `zig build test`
2. Add focused unit tests for new behavior
3. Keep dialect-specific assertions explicit
