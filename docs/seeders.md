# Seeders

## Types

- `Seeder`: `{ id, name, run_sql }`
- `SeederRegistry`: list of seed scripts
- `SeederStore`: execution state persistence
- `SeederRunner`: executes pending seeders once

## Store Contract

- `isExecuted(id)`
- `markExecuted(id)`

## Runner Behavior

`SeederRunner.run(registry)`:

1. Skips already-executed seeders
2. Executes `run_sql`
3. Marks seed as executed

## Minimal Example

```zig
var reg = zorm.SeederRegistry.init(allocator);
defer reg.deinit();

try reg.add(.{
    .id = "202603060001",
    .name = "seed_admin",
    .run_sql = "INSERT INTO users (email) VALUES ('admin@example.com')",
});

var store = zorm.SeederInMemoryStore.init(allocator);
defer store.deinit();

const runner = zorm.SeederRunner.init(
    zorm.Driver.from(@TypeOf(pg), &pg),
    zorm.SeederStore.from(@TypeOf(store), &store),
);

_ = try runner.run(&reg);
```

## Next

See [CLI](cli.md) for generator commands.
