const std = @import("std");
const Yaml = @import("yaml").Yaml;
const fs = std.fs;
const State = @import("state.zig").State;
const log = std.log.scoped(.main);
const initialize = @import("lsp/initialize.zig");
const WorkspaceFolder = initialize.WorkspaceFolder;

const DefaultValue = union {
    string: []const u8,
    integer: i64,
    null: @TypeOf(null),

    pub fn format(
        self: DefaultValue,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .string => try writer.print("{s}", .{self.string}),
            .integer => try writer.print("{d}", .{self.integer}),
            .null => try writer.print("null", .{}),
        }

        try writer.writeAll("");
    }
};

pub fn scan_project(allocator: std.mem.Allocator, state: *State, workspace: WorkspaceFolder) !void {
    log.info("{any}\n", .{workspace});
    const dir = try fs.openDirAbsolute(workspace.name, .{ .iterate = true });
    var walker = try dir.walk(allocator);
    while (try walker.next()) |file| {
        switch (file.kind) {
            fs.File.Kind.file => {
                if (std.mem.endsWith(u8, file.basename, ".py")) {} else if (std.mem.endsWith(u8, file.basename, ".yml") or std.mem.endsWith(u8, file.basename, ".yaml")) {
                    log.info("{any}: {s} {s}/{s}\n", .{ file.kind, file.basename, workspace.name, file.path });
                    const file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ workspace.name, file.path });
                    var f = fs.openFileAbsolute(file_path, .{ .mode = .read_only }) catch |err| {
                        log.err("error opening file {any}", .{err});
                        continue;
                    };
                    defer f.close();
                    const source = try f.readToEndAlloc(allocator, std.math.maxInt(u32));
                    var yaml: Yaml = .{ .source = source };
                    // TODO handle ParseError because of '$' not between " "
                    try yaml.load(allocator);
                    log.info("num documents: {d}", .{yaml.docs.items.len});
                    const dbx = yaml.docs.items[0].map;
                    const variables = dbx.get("variables");
                    if (variables != null) {
                        var i = variables.?.map.entries;
                        while (i.pop()) |entry| {
                            const value = entry.value.map;
                            var description: ?[]const u8 = null;
                            if (value.get("description")) |desc| {
                                description = try desc.asString();
                            }
                            var default: State.DefaultValue = .none;
                            if (value.get("default")) |def|
                                default = switch (def) {
                                    .string => State.DefaultValue{ .string = try def.asString() },
                                    .int => State.DefaultValue{ .integer = try def.asInt() },
                                    else => continue,
                                };
                            try state.project_config.variables.put(entry.key, State.Variable{ .name = entry.key, .description = description, .default = default });
                        }
                    }
                }
            },
            else => continue,
        }
    }
}
