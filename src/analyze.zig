const std = @import("std");
const fs = std.fs;
const State = @import("state.zig").State;
const log = std.log.scoped(.main);
const initialize = @import("lsp/initialize.zig");
const WorkspaceFolder = initialize.WorkspaceFolder;

pub fn scan_project(allocator: std.mem.Allocator, state: *State, workspace: WorkspaceFolder) !void {
    _ = state;
    log.info("{any}\n", .{workspace});
    const dir = try fs.openDirAbsolute(workspace.name, .{ .iterate = true });
    var walker = try dir.walk(allocator);
    while (try walker.next()) |file| {
        switch (file.kind) {
            fs.File.Kind.file => {
                if (std.mem.endsWith(u8, file.basename, ".py")) {} else if (std.mem.endsWith(u8, file.basename, ".yml") or std.mem.endsWith(u8, file.basename, ".yaml")) {
                    log.info("{any}: {s} {s}/{s}\n", .{ file.kind, file.basename, workspace.name, file.path });
                }
            },
            else => {},
        }
    }
}
