const std = @import("std");

pub const Value = union(enum) {
    null,
    bool: bool,
    int: i64,
    float: f64,
    text: []const u8,
    blob: []const u8,

    pub fn format(self: Value, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            .null => try writer.writeAll("NULL"),
            .bool => |v| try writer.print("{}", .{v}),
            .int => |v| try writer.print("{d}", .{v}),
            .float => |v| try writer.print("{d}", .{v}),
            .text => |v| try writer.print("\"{s}\"", .{v}),
            .blob => |v| try writer.print("blob[{d}]", .{v.len}),
        }
    }
};
