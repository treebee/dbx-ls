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

pub fn decodeMessage(allocator: std.mem.Allocator, msg: []const u8) !struct { []u8, ?u32 } {
    var s = std.mem.splitSequence(u8, msg, "\r\n\r\n");
    const header = s.first();
    const content_length_bytes = header["Content-Length: ".len..];
    const content_length = std.fmt.parseInt(u32, content_length_bytes, 10) catch {
        return DecodeError.InvalidHeader;
    };
    const content = s.next();
    if (content == null) {
        return DecodeError.NoContent;
    }
    const parsed = try json.parseFromSliceLeaky(BaseMessage, allocator, content.?, .{});
    return .{ parsed.method, content_length };
}

test "encodeMessage" {
    const allocator = std.testing.allocator;
    const msg = .{ .testing = "test" };
    const encoded = try encodeMessage(allocator, msg);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("Content-Length: 18\r\n\r\n{\"testing\":\"test\"}", encoded);
}

test "decodeMessage" {
    const allocator = std.testing.allocator;
    const method, const content_length = try decodeMessage(allocator, "Content-Length: 18\r\n\r\n{\"method\":\"testing\"}");
    defer allocator.free(method);
    try std.testing.expectEqualStrings("testing", method);
    try std.testing.expectEqual(18, content_length);
}
