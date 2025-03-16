const std = @import("std");
const json = std.json;

const DecodeError = error{
    NoContent,
    InvalidHeader,
};

const BaseMessage = struct {
    method: []u8,
};

pub fn encodeMessage(allocator: std.mem.Allocator, msg: anytype) ![]u8 {
    const content = try json.stringifyAlloc(allocator, msg, .{});
    defer allocator.free(content);
    return std.fmt.allocPrint(allocator, "Content-Length: {d}\r\n\r\n{s}", .{ content.len, content });
}

pub fn parseMethod(allocator: std.mem.Allocator, msg: []const u8) ![]u8 {
    const parsed = try json.parseFromSliceLeaky(BaseMessage, allocator, msg, .{ .ignore_unknown_fields = true });
    return parsed.method;
}

test "encodeMessage" {
    const allocator = std.testing.allocator;
    const msg = .{ .testing = "test" };
    const encoded = try encodeMessage(allocator, msg);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("Content-Length: 18\r\n\r\n{\"testing\":\"test\"}", encoded);
}

test "parseMethod" {
    const allocator = std.testing.allocator;
    const method = try parseMethod(allocator, "{\"method\":\"testing\"}");
    defer allocator.free(method);
    try std.testing.expectEqualStrings("testing", method);
}
