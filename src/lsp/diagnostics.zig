const std = @import("std");
const text_document = @import("text_document.zig");

pub const Diagnostic = struct {
    range: text_document.Range,
    message: []const u8,
    severity: u16,
    code: []const u8,
    source: []const u8 = "dbxls",
};

pub const PublishDiagnosticsParams = struct {
    uri: []const u8,
    diagnostics: []const Diagnostic,
};

pub const DiagnosticsResponse = struct {
    method: []const u8,
    params: PublishDiagnosticsParams,
};

pub fn NewDiagnosticsResponse(
    uri: []const u8,
    diagnostics: []const Diagnostic,
) !DiagnosticsResponse {
    return DiagnosticsResponse{
        .method = "textDocument/publishDiagnostics",
        .params = .{ .uri = uri, .diagnostics = diagnostics },
    };
}
