const std = @import("std");
const notebook_document = @import("notebook_document.zig");

const NotebookCell = notebook_document.NotebookCell;
pub const ParsedNotebook = struct {
    cells: []NotebookCell,
};

pub const State = struct {
    notebooks: std.hash_map.StringHashMap(ParsedNotebook),
    project_config: DatabricksProjectConfig,

    pub const DatabricksProjectConfig = struct {
        variables: std.hash_map.StringHashMap(Variable),
    };

    pub const Value = union(enum) {
        string: []const u8,
        integer: i64,
        none,

        pub fn format(
            self: Value,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;

            switch (self) {
                .string => try writer.print("{s}", .{self.string}),
                .integer => try writer.print("{d}", .{self.integer}),
                .none => try writer.print("null", .{}),
            }

            try writer.writeAll("");
        }
    };

    pub const Variable = struct {
        name: []const u8,
        description: ?[]const u8,
        default: Value,
        targets: std.StringArrayHashMap(Value),
    };

    pub fn init(allocator: std.mem.Allocator) State {
        const variables = std.hash_map.StringHashMap(Variable).init(allocator);
        return State{ .notebooks = std.hash_map.StringHashMap(ParsedNotebook).init(allocator), .project_config = DatabricksProjectConfig{
            .variables = variables,
        } };
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
        var variable_iter = self.project_config.variables.keyIterator();
        while (variable_iter.next()) |variable| {
            try writer.print("{s}:\n\tdescription: {s}\n\tdefault: {s}\n\ttargets: ", .{
                variable.*,
                self.project_config.variables.get(variable.*).?.description orelse "null",
                self.project_config.variables.get(variable.*).?.default,
            });
            var targets = self.project_config.variables.get(variable.*).?.targets.iterator();
            while (targets.next()) |target| {
                const target_name = target.key_ptr.*;
                try writer.print("{s}=", .{target_name});
                const target_var = target.value_ptr.*;
                try writer.print("{s}\t", .{target_var});
            }
        }
        try writer.writeAll("");
    }
};
