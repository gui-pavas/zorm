const std = @import("std");

pub const Dialect = @import("dialect.zig").Dialect;
pub const Driver = @import("driver.zig").Driver;
pub const QueryBuilder = @import("query_builder.zig").QueryBuilder;
pub const Query = @import("query_builder.zig").Query;
pub const Value = @import("value.zig").Value;
pub const schema = @import("schema.zig");

pub const PostgresDriver = @import("driver.zig").PostgresDriver;
pub const MySqlDriver = @import("driver.zig").MySqlDriver;
pub const MariaDbDriver = @import("driver.zig").MariaDbDriver;
pub const SqliteDriver = @import("driver.zig").SqliteDriver;
pub const CassandraDriver = @import("driver.zig").CassandraDriver;
pub const renderQuery = @import("driver.zig").renderQuery;

pub const SchemaTable = @import("schema.zig").Table;
pub const SchemaColumn = @import("schema.zig").Column;
pub const SchemaIndex = @import("schema.zig").Index;
pub const SchemaForeignKey = @import("schema.zig").ForeignKey;
pub const SchemaColumnType = @import("schema.zig").ColumnType;
pub const CompiledSchema = @import("schema.zig").CompiledSchema;

pub const Migration = @import("migration.zig").Migration;
pub const MigrationRegistry = @import("migration.zig").Registry;
pub const MigrationRunner = @import("migration.zig").Runner;
pub const MigrationStore = @import("migration.zig").Store;
pub const MigrationInMemoryStore = @import("migration.zig").InMemoryStore;

pub const Seeder = @import("seeder.zig").Seeder;
pub const SeederRegistry = @import("seeder.zig").Registry;
pub const SeederRunner = @import("seeder.zig").Runner;
pub const SeederStore = @import("seeder.zig").Store;
pub const SeederInMemoryStore = @import("seeder.zig").InMemoryStore;

pub const cli = @import("cli.zig");

test "dialect postgres placeholder" {
    const value = try Dialect.postgres.placeholder(std.testing.allocator, 3);
    defer std.testing.allocator.free(value);
    try std.testing.expectEqualStrings("$3", value);
}
