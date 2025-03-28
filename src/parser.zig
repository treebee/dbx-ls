const std = @import("std");
const log = std.log.scoped(.main);
const notebook_document = @import("notebook_document.zig");
const State = @import("state.zig").State;
const NotebookCell = notebook_document.NotebookCell;

fn write_line(writer: anytype, line: []const u8) !void {
    try writer.print("{s}", .{line});
    try writer.writeByte('\n');
}

pub fn parse_notebook(allocator: std.mem.Allocator, state: *State, uri: []const u8, content: []const u8) !void {
    var line_iter = std.mem.splitSequence(u8, content, "\n");
    const first = line_iter.next().?;
    if (!std.mem.startsWith(u8, first, "# Databricks notebook source")) {
        log.warn("Not a databricks notebook: {s}", .{uri});
        return error.NotANotebookDocument;
    }

    var buffer: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    var previous_is_magic = false;
    var notebook_cells = std.ArrayList(NotebookCell).init(allocator);

    var language = "py";
    while (line_iter.next()) |line| {
        if (is_magic(line)) {
            if (is_shell(line)) {
                language = "sh";
            } else if (is_markdown(line)) {
                language = "md";
            }

            try write_line(fbs.writer(), line);
            previous_is_magic = true;
        } else if (is_command(line)) {
            const cell_content = try std.fmt.allocPrint(allocator, "{s}", .{fbs.getWritten()});
            try notebook_cells.append(NotebookCell.init(language, cell_content));
            language = "py";
            fbs.reset();
            previous_is_magic = false;
        } else {
            try write_line(fbs.writer(), line);
            previous_is_magic = false;
        }
    }
    if (try fbs.getPos() > 1) {
        const cell_content = try std.fmt.allocPrint(allocator, "{s}", .{fbs.getWritten()});
        try notebook_cells.append(NotebookCell{ .language = language, .text = cell_content });
    }
    try state.notebooks.put(uri, .{ .cells = notebook_cells.items });
}

pub inline fn is_magic(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "# MAGIC");
}

pub inline fn is_shell(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "# MAGIC %sh");
}

pub inline fn is_markdown(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "# MAGIC %md");
}

pub inline fn is_command(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "# COMMAND ----------");
}
