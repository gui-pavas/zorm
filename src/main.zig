const std = @import("std");
const Io = std.Io;

const zorm = @import("zorm");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr_writer = &stderr_file_writer.interface;

    zorm.cli.run(arena, io, args, stdout_writer) catch |err| {
        switch (err) {
            error.MissingCommand, error.UnknownCommand => {
                try stderr_writer.print("invalid command\n", .{});
                try zorm.cli.writeHelp(stderr_writer);
                return;
            },
            error.MissingName => {
                try stderr_writer.print("missing resource name\n", .{});
                return;
            },
            error.InvalidDialect => {
                try stderr_writer.print("invalid dialect value\n", .{});
                return;
            },
            else => return err,
        }
    };

    try stdout_writer.flush(); // Don't forget to flush!
    try stderr_writer.flush();
}
