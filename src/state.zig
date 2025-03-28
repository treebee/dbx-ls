const std = @import("std");
const notebook_document = @import("notebook_document.zig");

const NotebookCell = notebook_document.NotebookCell;
pub const ParsedNotebook = struct {
    cells: []NotebookCell,
};

pub const State = struct {
    notebooks: std.hash_map.StringHashMap(ParsedNotebook),

    pub fn init(allocator: std.mem.Allocator) State {
        return State{
            .notebooks = std.hash_map.StringHashMap(ParsedNotebook).init(allocator),
        };
    }

    pub fn format(
        self: State,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        var notebook_iter = self.notebooks.keyIterator();
        while (notebook_iter.next()) |uri| {
            try writer.print("uri = {s}\n", .{uri.*});
            for (0.., self.notebooks.get(uri.*).?.cells) |i, cell| {
                try writer.print("\t({d}) {s} {s}\n", .{ i, cell.language, cell.text });
            }
        }

        try writer.writeAll("");
    }
};
