const std = @import("std");

pub const WorkspaceFolder = struct {
    name: []const u8,
    uri: []const u8,
};
pub const InitializeRequest = struct {
    id: usize,
    params: InitializeParams,

    const InitializeParams = struct {
        clientInfo: ?ClientInfo,
        workspaceFolders: ?[]WorkspaceFolder,

        pub const ClientInfo = struct {
            name: []u8,
            version: []u8,
        };
    };
};

pub const InitializeResult = struct {
    serverInfo: ServerInfo,
    capabilities: ServerCapabilities,

    const ServerInfo = struct {
        name: []const u8,
        version: []const u8,
    };

    const ServerCapabilities = struct {
        textDocumentSync: u8,
        //notebookDocumentSync: NotebookDocumentSyncOptions,
        hoverProvider: bool,
    };

    const NotebookDocumentSyncOptions = struct {
        mode: []const u8,
        notebookSelector: NotebookSelector,
    };

    const NotebookSelector = struct {
        notebook: NotebookCellTextDocumentFilter,
        cells: ?[1]NotebookCell,
    };
};

pub const NotebookCellTextDocumentFilter = struct {
    scheme: []const u8,
    notebookType: []const u8,
};

pub const NotebookCell = struct {
    language: []const u8,
};

pub const InitializeResponse = struct {
    id: usize,
    result: InitializeResult,
};

pub fn NewInitializeResponse(id: usize) InitializeResponse {
    return InitializeResponse{
        .id = id,
        .result = InitializeResult{
            .serverInfo = .{ .name = "dbxls", .version = "0.1alpha" },
            .capabilities = .{
                .textDocumentSync = 1,
                // .notebookDocumentSync = .{ .mode = "notebook", .notebookSelector = .{ .notebook = NotebookCellTextDocumentFilter{ .scheme = "file", .notebookType = "jupyter-notebook" }, .cells = [1]NotebookCell{.{ .language = "python" }} } },
                .hoverProvider = true,
            },
        },
    };
}

test "initialize" {
    const msg = "{\"clientInfo\": {\"name\": \"vim\", \"version\": \"3.4\"}}";
    const parsed = try std.json.parseFromSlice(InitializeRequest.InitializeParams, std.testing.allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("vim", parsed.value.clientInfo.?.name);
}
