const std = @import("std");
const Yaml = @import("yaml").Yaml;
const fs = std.fs;
const log = std.log.scoped(.analyze);

const project_analyze = @import("../analyze/project.zig");
const initialize = @import("../lsp/initialize.zig");
const State = @import("../State.zig");

/// creates the initial state from the databricks config, e.g. 'databricks.yml' and
/// all included yaml files
pub fn scan(allocator: std.mem.Allocator, state: *State, workspace: []const u8) !void {
    log.info("Scanning project {s}", .{workspace});
    var dir = try fs.openDirAbsolute(workspace, .{ .iterate = true });
    defer dir.close();
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    var files = std.ArrayList([]const u8).init(allocator);
    while (try walker.next()) |file| {
        switch (file.kind) {
            fs.File.Kind.file => {
                const ext = fs.path.extension(file.basename);
                // for now ignore everything that's not a yaml file
                // Python files will be scanned once they're opened/edited/saved
                if ((std.mem.eql(u8, ext, ".yml") or std.mem.eql(u8, ext, ".yaml")) and
                    !std.mem.startsWith(u8, file.basename, "."))
                {
                    const file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ workspace, file.path });
                    try files.append(file_path);
                }
            },
            else => continue,
        }
    }
    for (files.items) |file_path| {
        log.info("Parsing file: {s}", .{fs.path.basename(file_path)});
        project_analyze.parse_dbx_config(allocator, file_path, state) catch |err| {
            log.err("Error parsing file ({any}): {s}", .{ err, file_path });
        };
    }
    log.info("{} jobs, {} variables", .{ state.jobs.count(), state.variables.count() });
}

fn parseValue(yaml_value: ?Yaml.Value) !State.Value {
    if (yaml_value == null) return .none;

    switch (yaml_value.?) {
        .string => return State.Value{ .string = try yaml_value.?.asString() },
        .int => return State.Value{ .integer = try yaml_value.?.asInt() },
        .boolean => return State.Value{ .boolean = try yaml_value.?.asBool() },
        else => return .none,
    }
}

/// parses a yaml file and updates the project state
fn parse_dbx_config(allocator: std.mem.Allocator, path: []const u8, state: *State) !void {
    var f = try fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer f.close();
    const source = try f.readToEndAlloc(allocator, std.math.maxInt(u32));
    var yaml: Yaml = .{ .source = source };
    try yaml.load(allocator);
    log.info("num documents: {d}", .{yaml.docs.items.len});
    const dbx = yaml.docs.items[0].map;
    const targets = dbx.get("targets");
    var target_names = std.ArrayList([]const u8).init(allocator);
    if (targets != null) {
        for (0..targets.?.map.entries.len) |i| {
            const t = targets.?.map.entries.get(i);
            try target_names.append(t.key);
            var mode: []const u8 = "production";
            if (t.value.map.get("mode")) |m| {
                mode = (try parseValue(m)).string;
            }
            var target = State.Target{
                .mode = std.meta.stringToEnum(State.DevMode, mode) orelse .production,
                .variables = State.ValueMap.init(allocator),
            };

            const target_variables = t.value.map.get("variables");
            if (target_variables) |target_params| {
                const target_vars = target_params.map.entries;
                for (0..target_vars.len) |iv| {
                    const target_var = target_vars.get(iv);
                    const value = try parseValue(target_var.value);
                    if (value == .none) continue;
                    try target.variables.put(target_var.key, value);
                }
            }
            try state.targets.put(t.key, target);
        }
    }
    if (dbx.get("variables")) |variables| {
        var variable_entries = variables.map.entries;
        for (0..variable_entries.len) |i| {
            const entry = variable_entries.get(i);
            const value = entry.value.map;
            var description: ?[]const u8 = null;
            if (value.get("description")) |desc| {
                description = try desc.asString();
            }
            const default = try parseValue(value.get("default"));
            try state.variables.put(entry.key, State.Variable{
                .name = entry.key,
                .description = description,
                .default = default,
            });
        }
    }

    const resources = dbx.get("resources");
    if (resources == null) {
        return;
    }

    const jobs = resources.?.map.get("jobs");
    if (jobs == null) {
        return;
    }

    var jobs_iter = jobs.?.map.iterator();
    while (jobs_iter.next()) |job_entry| {
        const job_name = job_entry.key_ptr.*;
        var job = State.Job{
            .parameters = State.ValueMap.init(allocator),
            .tasks = std.StringHashMap(State.NotebookTask).init(allocator),
        };

        const job_info = job_entry.value_ptr.*.map;
        const job_parameters = job_info.get("parameters");

        if (job_parameters == null) {
            continue;
        }

        for (job_parameters.?.list) |parameter| {
            var p = parameter.map;
            const variable_name = try p.get("name").?.asString();
            try job.parameters.put(variable_name, try parseValue(p.get("default")));
        }

        const tasks = job_info.get("tasks");
        for (tasks.?.list) |task_entry| {
            var task_key: []const u8 = "";
            const notebook_task = task_entry.map.get("notebook_task").?;
            if (task_entry.map.get("task_key")) |key| {
                task_key = key.string;
            }
            const notebook_path = try parseValue(notebook_task.map.get("notebook_path"));
            var notebook_uri: ?[]const u8 = null;
            if (state.workspace) |workspace| {
                notebook_uri = try pathToUri(
                    allocator,
                    workspace,
                    notebook_path.string,
                );
            }

            var task = State.NotebookTask{
                .key = task_key,
                .notebook_uri = notebook_uri orelse "",
                .base_parameters = State.ValueMap.init(allocator),
                .job = job_name,
            };

            if (notebook_task.map.get("base_parameters")) |parameters| {
                var p_iter = parameters.map.iterator();
                while (p_iter.next()) |parameter| {
                    try task.base_parameters.put(
                        parameter.key_ptr.*,
                        try parseValue(parameter.value_ptr.*),
                    );
                }
            }
            try job.tasks.put(task_key, task);
        }
        try state.jobs.put(job_name, job);
    }
}

fn pathToUri(allocator: std.mem.Allocator, workspace: []const u8, path: []const u8) !?[]const u8 {
    if (std.mem.indexOf(u8, path, "/files/")) |index| {
        const uri = try std.mem.concat(allocator, u8, &.{ "file://", workspace, "/", path[index + 7 ..], ".py" });
        return uri;
    }
    return null;
}

test "pathToUri" {
    const workspace = "/home/user/workspace/project";
    const uri = try pathToUri(
        std.testing.allocator,
        workspace,
        "${workspace.root_path}/files/src/project/notebook",
    );
    defer std.testing.allocator.free(uri.?);

    try std.testing.expectEqualStrings(
        "file:///home/user/workspace/project/src/project/notebook.py",
        uri.?,
    );
}
