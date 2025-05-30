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

const CompletionOptions = struct {
    triggerCharacters: ?[][]const u8 = null,
};

pub const InitializeResult = struct {
    serverInfo: ServerInfo,
    capabilities: ServerCapabilities,

    const ServerInfo = struct {
        name: []const u8,
        version: []const u8,
    };

    const ServerCapabilities = struct {
        textDocumentSync: TextDocumentSyncOptions,
        hoverProvider: bool,
        completionProvider: CompletionOptions,
    };

    const TextDocumentSyncOptions = struct {
        change: ?u8,
        openClose: bool,
        save: SaveOptions,
    };

    const SaveOptions = struct {
        includeText: bool,
    };
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
                .textDocumentSync = .{
                    .change = 1,
                    .openClose = true,
                    .save = .{ .includeText = true },
                },
                .hoverProvider = true,
                .completionProvider = CompletionOptions{},
            },
        },
    };
}

test "initialize" {
    const msg = "{\"clientInfo\": {\"name\": \"vim\", \"version\": \"3.4\"}}";
    const parsed = try std.json.parseFromSlice(
        InitializeRequest.InitializeParams,
        std.testing.allocator,
        msg,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    try std.testing.expectEqualStrings("vim", parsed.value.clientInfo.?.name);
}
