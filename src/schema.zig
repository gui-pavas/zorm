const std = @import("std");
const Dialect = @import("dialect.zig").Dialect;

pub const SchemaError = error{
    UnsupportedFeature,
    MissingPrimaryKey,
};

pub const ColumnType = union(enum) {
    integer,
    big_int,
    text,
    boolean,
    float,
    double,
    blob,
    uuid,
    timestamp,
    timestamptz,
    varchar: usize,
    custom: []const u8,
};

pub const Column = struct {
    name: []const u8,
    typ: ColumnType,
    nullable: bool = true,
    primary_key: bool = false,
    unique: bool = false,
    auto_increment: bool = false,
    default_value_sql: ?[]const u8 = null,
};

pub const Index = struct {
    columns: []const []const u8,
    unique: bool = false,
    name: ?[]const u8 = null,
};

pub const ReferenceAction = enum {
    cascade,
    restrict,
    set_null,
    set_default,
    no_action,
};

pub const ForeignKey = struct {
    column: []const u8,
    ref_table: []const u8,
    ref_column: []const u8,
    name: ?[]const u8 = null,
    on_delete: ?ReferenceAction = null,
    on_update: ?ReferenceAction = null,
};

pub const Table = struct {
    name: []const u8,
    columns: []const Column,
    indexes: []const Index = &.{},
    foreign_keys: []const ForeignKey = &.{},
    if_not_exists: bool = true,
};

pub const CompiledSchema = struct {
    allocator: std.mem.Allocator,
    statements: []const []const u8,

    pub fn deinit(self: *CompiledSchema) void {
        for (self.statements) |stmt| self.allocator.free(stmt);
        self.allocator.free(self.statements);
    }
};

pub fn column(name: []const u8, typ: ColumnType) Column {
    return .{ .name = name, .typ = typ };
}

pub fn index(columns: []const []const u8) Index {
    return .{ .columns = columns };
}

pub fn foreignKey(column_name: []const u8, ref_table: []const u8, ref_column: []const u8) ForeignKey {
    return .{
        .column = column_name,
        .ref_table = ref_table,
        .ref_column = ref_column,
    };
}

pub fn table(name: []const u8, columns_: []const Column) Table {
    return .{
        .name = name,
        .columns = columns_,
    };
}

pub fn compileCreateTable(allocator: std.mem.Allocator, dialect: Dialect, spec: Table) !CompiledSchema {
    var statements = std.ArrayList([]const u8).empty;
    errdefer {
        for (statements.items) |stmt| allocator.free(stmt);
        statements.deinit(allocator);
    }

    const create_stmt = try compileCreateTableSql(allocator, dialect, spec);
    try statements.append(allocator, create_stmt);

    for (spec.indexes) |idx| {
        const stmt = try compileCreateIndexSql(allocator, dialect, spec.name, idx);
        try statements.append(allocator, stmt);
    }

    return .{
        .allocator = allocator,
        .statements = try statements.toOwnedSlice(allocator),
    };
}

fn compileCreateTableSql(allocator: std.mem.Allocator, dialect: Dialect, spec: Table) ![]const u8 {
    var sql = std.ArrayList(u8).empty;
    defer sql.deinit(allocator);

    const quoted_table = try dialect.quotedIdentifier(allocator, spec.name);
    defer allocator.free(quoted_table);

    try sql.appendSlice(allocator, "CREATE TABLE ");
    if (spec.if_not_exists and dialect != .cassandra) {
        try sql.appendSlice(allocator, "IF NOT EXISTS ");
    }
    try sql.appendSlice(allocator, quoted_table);
    try sql.appendSlice(allocator, " (");

    var first = true;
    var cassandra_pk_count: usize = 0;

    for (spec.columns) |col| {
        if (!first) try sql.appendSlice(allocator, ", ");
        first = false;

        if (dialect == .cassandra and col.primary_key) cassandra_pk_count += 1;

        const col_sql = try compileColumnSql(allocator, dialect, col);
        defer allocator.free(col_sql);
        try sql.appendSlice(allocator, col_sql);
    }

    if (dialect == .cassandra) {
        if (cassandra_pk_count == 0) return SchemaError.MissingPrimaryKey;

        if (!first) try sql.appendSlice(allocator, ", ");
        try sql.appendSlice(allocator, "PRIMARY KEY (");

        var first_pk = true;
        for (spec.columns) |col| {
            if (!col.primary_key) continue;
            if (!first_pk) try sql.appendSlice(allocator, ", ");
            first_pk = false;

            const quoted_col = try dialect.quotedIdentifier(allocator, col.name);
            defer allocator.free(quoted_col);
            try sql.appendSlice(allocator, quoted_col);
        }

        try sql.appendSlice(allocator, ")");
    } else {
        for (spec.foreign_keys) |fk| {
            if (!first) try sql.appendSlice(allocator, ", ");
            first = false;

            const fk_sql = try compileForeignKeySql(allocator, dialect, fk);
            defer allocator.free(fk_sql);
            try sql.appendSlice(allocator, fk_sql);
        }
    }

    try sql.appendSlice(allocator, ");");
    return sql.toOwnedSlice(allocator);
}

fn compileColumnSql(allocator: std.mem.Allocator, dialect: Dialect, col: Column) ![]const u8 {
    var sql = std.ArrayList(u8).empty;
    defer sql.deinit(allocator);

    const quoted_col = try dialect.quotedIdentifier(allocator, col.name);
    defer allocator.free(quoted_col);
    const type_name = try mapColumnType(allocator, dialect, col);
    defer allocator.free(type_name);

    try sql.writer(allocator).print("{s} {s}", .{ quoted_col, type_name });

    if (dialect == .sqlite and col.auto_increment and col.primary_key) {
        try sql.appendSlice(allocator, " PRIMARY KEY AUTOINCREMENT");
        return sql.toOwnedSlice(allocator);
    }

    if (col.primary_key and dialect != .cassandra) try sql.appendSlice(allocator, " PRIMARY KEY");
    if (col.unique) try sql.appendSlice(allocator, " UNIQUE");
    if (!col.nullable) try sql.appendSlice(allocator, " NOT NULL");

    if (col.auto_increment and (dialect == .mysql or dialect == .mariadb)) {
        try sql.appendSlice(allocator, " AUTO_INCREMENT");
    }

    if (col.default_value_sql) |default_sql| {
        try sql.appendSlice(allocator, " DEFAULT ");
        try sql.appendSlice(allocator, default_sql);
    }

    return sql.toOwnedSlice(allocator);
}

fn compileForeignKeySql(allocator: std.mem.Allocator, dialect: Dialect, fk: ForeignKey) ![]const u8 {
    if (dialect == .cassandra) return SchemaError.UnsupportedFeature;

    var sql = std.ArrayList(u8).empty;
    defer sql.deinit(allocator);

    if (fk.name) |name| {
        const quoted_name = try dialect.quotedIdentifier(allocator, name);
        defer allocator.free(quoted_name);
        try sql.writer(allocator).print("CONSTRAINT {s} ", .{quoted_name});
    }

    const quoted_col = try dialect.quotedIdentifier(allocator, fk.column);
    defer allocator.free(quoted_col);
    const quoted_table = try dialect.quotedIdentifier(allocator, fk.ref_table);
    defer allocator.free(quoted_table);
    const quoted_ref_col = try dialect.quotedIdentifier(allocator, fk.ref_column);
    defer allocator.free(quoted_ref_col);

    try sql.writer(allocator).print(
        "FOREIGN KEY ({s}) REFERENCES {s} ({s})",
        .{ quoted_col, quoted_table, quoted_ref_col },
    );

    if (fk.on_delete) |action| {
        try sql.writer(allocator).print(" ON DELETE {s}", .{refActionSql(action)});
    }
    if (fk.on_update) |action| {
        try sql.writer(allocator).print(" ON UPDATE {s}", .{refActionSql(action)});
    }

    return sql.toOwnedSlice(allocator);
}

fn compileCreateIndexSql(
    allocator: std.mem.Allocator,
    dialect: Dialect,
    table_name: []const u8,
    idx: Index,
) ![]const u8 {
    if (dialect == .cassandra and idx.unique) return SchemaError.UnsupportedFeature;
    if (dialect == .cassandra and idx.columns.len != 1) return SchemaError.UnsupportedFeature;

    const resolved_name = if (idx.name) |name|
        try allocator.dupe(u8, name)
    else
        try defaultIndexName(allocator, table_name, idx);
    defer allocator.free(resolved_name);

    const quoted_index = try dialect.quotedIdentifier(allocator, resolved_name);
    defer allocator.free(quoted_index);
    const quoted_table = try dialect.quotedIdentifier(allocator, table_name);
    defer allocator.free(quoted_table);

    var sql = std.ArrayList(u8).empty;
    defer sql.deinit(allocator);

    try sql.appendSlice(allocator, "CREATE ");
    if (idx.unique) try sql.appendSlice(allocator, "UNIQUE ");
    try sql.writer(allocator).print("INDEX {s} ON {s} (", .{ quoted_index, quoted_table });

    for (idx.columns, 0..) |col, i| {
        if (i > 0) try sql.appendSlice(allocator, ", ");
        const quoted_col = try dialect.quotedIdentifier(allocator, col);
        defer allocator.free(quoted_col);
        try sql.appendSlice(allocator, quoted_col);
    }

    try sql.appendSlice(allocator, ");");
    return sql.toOwnedSlice(allocator);
}

fn defaultIndexName(allocator: std.mem.Allocator, table_name: []const u8, idx: Index) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator, table_name);
    try out.append(allocator, '_');

    for (idx.columns, 0..) |col, i| {
        if (i > 0) try out.append(allocator, '_');
        try out.appendSlice(allocator, col);
    }

    if (idx.unique) {
        try out.appendSlice(allocator, "_uniq");
    } else {
        try out.appendSlice(allocator, "_idx");
    }

    return out.toOwnedSlice(allocator);
}

fn mapColumnType(allocator: std.mem.Allocator, dialect: Dialect, col: Column) ![]const u8 {
    if (col.auto_increment and col.typ == .integer) {
        return switch (dialect) {
            .postgres => allocator.dupe(u8, "SERIAL"),
            .mysql, .mariadb => allocator.dupe(u8, "INT"),
            .sqlite => allocator.dupe(u8, "INTEGER"),
            .cassandra => SchemaError.UnsupportedFeature,
        };
    }

    if (col.auto_increment and col.typ == .big_int) {
        return switch (dialect) {
            .postgres => allocator.dupe(u8, "BIGSERIAL"),
            .mysql, .mariadb => allocator.dupe(u8, "BIGINT"),
            .sqlite => allocator.dupe(u8, "INTEGER"),
            .cassandra => SchemaError.UnsupportedFeature,
        };
    }

    return switch (col.typ) {
        .integer => allocator.dupe(u8, switch (dialect) {
            .postgres => "INTEGER",
            .mysql, .mariadb => "INT",
            .sqlite => "INTEGER",
            .cassandra => "int",
        }),
        .big_int => allocator.dupe(u8, switch (dialect) {
            .postgres => "BIGINT",
            .mysql, .mariadb => "BIGINT",
            .sqlite => "INTEGER",
            .cassandra => "bigint",
        }),
        .text => allocator.dupe(u8, switch (dialect) {
            .cassandra => "text",
            else => "TEXT",
        }),
        .boolean => allocator.dupe(u8, switch (dialect) {
            .cassandra => "boolean",
            else => "BOOLEAN",
        }),
        .float => allocator.dupe(u8, switch (dialect) {
            .cassandra => "float",
            else => "FLOAT",
        }),
        .double => allocator.dupe(u8, switch (dialect) {
            .cassandra => "double",
            else => "DOUBLE",
        }),
        .blob => allocator.dupe(u8, switch (dialect) {
            .postgres => "BYTEA",
            .mysql, .mariadb => "LONGBLOB",
            .sqlite => "BLOB",
            .cassandra => "blob",
        }),
        .uuid => allocator.dupe(u8, switch (dialect) {
            .postgres, .cassandra => "UUID",
            .mysql, .mariadb => "CHAR(36)",
            .sqlite => "TEXT",
        }),
        .timestamp => allocator.dupe(u8, switch (dialect) {
            .postgres, .mysql, .mariadb => "TIMESTAMP",
            .sqlite => "TEXT",
            .cassandra => "timestamp",
        }),
        .timestamptz => allocator.dupe(u8, switch (dialect) {
            .postgres => "TIMESTAMPTZ",
            .mysql, .mariadb => "TIMESTAMP",
            .sqlite => "TEXT",
            .cassandra => "timestamp",
        }),
        .varchar => |size| std.fmt.allocPrint(allocator, "VARCHAR({d})", .{size}),
        .custom => |raw| allocator.dupe(u8, raw),
    };
}

fn refActionSql(action: ReferenceAction) []const u8 {
    return switch (action) {
        .cascade => "CASCADE",
        .restrict => "RESTRICT",
        .set_null => "SET NULL",
        .set_default => "SET DEFAULT",
        .no_action => "NO ACTION",
    };
}

test "postgres schema compile with index and foreign key" {
    var columns = [_]Column{
        blk: {
            var c = column("id", .integer);
            c.primary_key = true;
            c.auto_increment = true;
            c.nullable = false;
            break :blk c;
        },
        blk: {
            var c = column("team_id", .integer);
            c.nullable = false;
            break :blk c;
        },
        blk: {
            var c = column("email", .varchar(255));
            c.nullable = false;
            break :blk c;
        },
    };

    var idx = index(&.{"email"});
    idx.unique = true;

    var fk = foreignKey("team_id", "teams", "id");
    fk.on_delete = .cascade;

    var spec = table("users", &columns);
    spec.indexes = &.{idx};
    spec.foreign_keys = &.{fk};

    var compiled = try compileCreateTable(std.testing.allocator, .postgres, spec);
    defer compiled.deinit();

    try std.testing.expectEqual(@as(usize, 2), compiled.statements.len);
    try std.testing.expectEqualStrings(
        "CREATE TABLE IF NOT EXISTS \"users\" (\"id\" SERIAL PRIMARY KEY NOT NULL, \"team_id\" INTEGER NOT NULL, \"email\" VARCHAR(255) NOT NULL, FOREIGN KEY (\"team_id\") REFERENCES \"teams\" (\"id\") ON DELETE CASCADE);",
        compiled.statements[0],
    );
    try std.testing.expectEqualStrings(
        "CREATE UNIQUE INDEX \"users_email_uniq\" ON \"users\" (\"email\");",
        compiled.statements[1],
    );
}

test "sqlite autoincrement primary key compile" {
    var columns = [_]Column{
        blk: {
            var c = column("id", .integer);
            c.primary_key = true;
            c.auto_increment = true;
            c.nullable = false;
            break :blk c;
        },
        blk: {
            var c = column("name", .text);
            c.nullable = false;
            break :blk c;
        },
    };

    const spec = table("widgets", &columns);
    var compiled = try compileCreateTable(std.testing.allocator, .sqlite, spec);
    defer compiled.deinit();

    try std.testing.expectEqual(@as(usize, 1), compiled.statements.len);
    try std.testing.expectEqualStrings(
        "CREATE TABLE IF NOT EXISTS \"widgets\" (\"id\" INTEGER PRIMARY KEY AUTOINCREMENT, \"name\" TEXT NOT NULL);",
        compiled.statements[0],
    );
}

test "cassandra compile requires primary key" {
    var columns = [_]Column{column("name", .text)};
    const spec = table("users", &columns);

    try std.testing.expectError(
        SchemaError.MissingPrimaryKey,
        compileCreateTable(std.testing.allocator, .cassandra, spec),
    );
}
