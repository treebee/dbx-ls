const std = @import("std");

pub const InitializeRequest = struct {
    id: usize,
    params: InitializeParams,

    const InitializeParams = struct {
        clientInfo: ?ClientInfo,

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
        hoverProvider: bool,
    };
};

pub const InitializeResponse = struct {
    id: usize,
    result: InitializeResult,
};

pub fn NewInitializeResponse(id: usize) InitializeResponse {
    return InitializeResponse{
        .id = id,
        .result = InitializeResult{ .serverInfo = .{ .name = "dbxls", .version = "0.1alpha" }, .capabilities = .{
            .textDocumentSync = 1,
            .hoverProvider = true,
        } },
    };
}

test "initialize" {
    const msg = "{\"clientInfo\": {\"name\": \"vim\", \"version\": \"3.4\"}}";
    const parsed = try std.json.parseFromSlice(InitializeRequest.InitializeParams, std.testing.allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("vim", parsed.value.clientInfo.?.name);
}
