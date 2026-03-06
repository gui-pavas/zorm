# CLI

The executable provides generators for migration and seed SQL files.

## Commands

- `zorm migration:create <name> [--dialect postgres|mysql|sqlite|mariadb|cassandra]`
- `zorm seed:create <name>`
- `zorm help`

## Examples

Create migration:

```bash
zig build run -- migration:create create_users --dialect postgres
```

Create seeder:

```bash
zig build run -- seed:create seed_users
```

## Output

- migrations are generated in `migrations/`
- seeders are generated in `seeders/`

File naming uses a hash-style stamp and slugified name.
