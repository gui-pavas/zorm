# Overview

zorm is a lightweight Zig ORM toolkit focused on explicit SQL workflows.

## Goals

- Keep APIs small and composable.
- Support multiple SQL dialects.
- Make migration/seeding workflows easy to wire.
- Keep schema definitions close to SQL semantics.

## Core Features

- Dialect abstraction (`postgres`, `mysql`, `sqlite`, `mariadb`, `cassandra`)
- Query builder with typed value params
- Generic `Driver` + concrete adapters
- Migration runner with pluggable store
- Seeder runner with pluggable store
- Schema DSL (`table`, `column`, `index`, `foreignKey`) compiled to SQL

## Module Layout

- `src/root.zig`: public exports
- `src/dialect.zig`: dialect mapping and SQL helpers
- `src/query_builder.zig`: query construction
- `src/value.zig`: runtime value type
- `src/driver.zig`: driver abstraction + adapters
- `src/migration.zig`: migration registry/store/runner
- `src/seeder.zig`: seeder registry/store/runner
- `src/schema.zig`: schema DSL compiler
- `src/cli.zig`: CLI command handlers

## Next

Continue with [Installation](installation.md).
