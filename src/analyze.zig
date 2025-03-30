const std = @import("std");
const Yaml = @import("yaml").Yaml;
const fs = std.fs;
const State = @import("state.zig").State;
const log = std.log.scoped(.main);
const initialize = @import("lsp/initialize.zig");
const WorkspaceFolder = initialize.WorkspaceFolder;

const Value = union(enum) {
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

fn parse_databricks_config_file(allocator: std.mem.Allocator, path: []const u8, state: *State) !void {
    var f = try fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer f.close();
    const source = try f.readToEndAlloc(allocator, std.math.maxInt(u32));
    var yaml: Yaml = .{ .source = source };
    // TODO handle ParseError because of '$' not between " "
    try yaml.load(allocator);
    log.info("num documents: {d}", .{yaml.docs.items.len});
    const dbx = yaml.docs.items[0].map;
    const variables = dbx.get("variables");
    const targets = dbx.get("targets");
    var target_names = std.ArrayList([]const u8).init(allocator);
    if (targets != null) {
        for (0..targets.?.map.entries.len) |i| {
            try target_names.append(targets.?.map.entries.get(i).key);
        }
    }
    if (variables != null) {
        var variable_entries = variables.?.map.entries;
        for (0..variable_entries.len) |i| {
            const entry = variable_entries.get(i);
            // initialize a variable value for all available targets
            var values_for_target = std.StringArrayHashMap(State.Value).init(allocator);
            for (target_names.items) |target_name| {
                try values_for_target.put(target_name, .none);
            }
            const value = entry.value.map;
            var description: ?[]const u8 = null;
            if (value.get("description")) |desc| {
                description = try desc.asString();
            }
            var default: State.Value = .none;
            if (value.get("default")) |def|
                default = switch (def) {
                    .string => State.Value{ .string = try def.asString() },
                    .int => State.Value{ .integer = try def.asInt() },
                    else => continue,
                };
            try state.project_config.variables.put(entry.key, State.Variable{
                .name = entry.key,
                .description = description,
                .default = default,
                .targets = values_for_target,
            });
        }
    }
    if (targets != null) {
        for (0..targets.?.map.entries.len) |i| {
            const target = targets.?.map.entries.get(i);
            const target_variables = target.value.map.get("variables");
            if (target_variables != null) {
                const target_vars = target_variables.?.map.entries;
                for (0..target_vars.len) |iv| {
                    const target_var = target_vars.get(iv);
                    const value = switch (target_var.value) {
                        .string => State.Value{ .string = try target_var.value.asString() },
                        .int => State.Value{ .integer = try target_var.value.asInt() },
                        else => continue,
                    };
                    var tv = state.project_config.variables.get(target_var.key).?;
                    try tv.targets.put(target.key, value);
                }
            }
        }
    }
}

pub fn scan_project(allocator: std.mem.Allocator, state: *State, workspace: WorkspaceFolder) !void {
    log.info("{any}\n", .{workspace});
    const dir = try fs.openDirAbsolute(workspace.name, .{ .iterate = true });
    var walker = try dir.walk(allocator);
    while (try walker.next()) |file| {
        switch (file.kind) {
            fs.File.Kind.file => {
                const ext = fs.path.extension(file.basename);
                if (std.mem.eql(u8, ext, ".yml") or std.mem.eql(u8, ext, ".yaml")) {
                    log.debug("{any}: {s} {s}/{s}\n", .{ file.kind, file.basename, workspace.name, file.path });
                    const file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ workspace.name, file.path });
                    try parse_databricks_config_file(allocator, file_path, state);
                }
            },
            else => continue,
        }
    }
}
