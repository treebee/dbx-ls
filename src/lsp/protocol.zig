const std = @import("std");
const rpc = @import("../rpc.zig");

pub const LSPHeader = struct {
    content_length: usize,

    pub const max_header_length: usize = 1024;

    /// Parses a message received via stdout into a `LSPHeader`
    /// which contains the `content_length`
    pub fn parse(reader: std.io.AnyReader) !LSPHeader {
        var content_length: usize = undefined;

        outer: while (true) {
            var buf: [max_header_length]u8 = undefined;
            var buf_index: usize = 0;
            var maybe_colon_index: ?usize = null;

            while (true) {
                const byte = try reader.readByte();
                switch (byte) {
                    '\n' => {
                        return error.InvalidHeaderField;
                    },
                    '\r' => {
                        if (try reader.readByte() != '\n') {
                            return error.InvalidHeaderField;
                        }
                        if (buf_index == 0) {
                            break :outer;
                        }
                        break;
                    },
                    ':' => {
                        if (try reader.readByte() != ' ') return error.InvalidHeaderField;
                        if (maybe_colon_index != null) return error.InvalidHeaderField;
                        maybe_colon_index = buf_index;
                    },
                    else => {
                        if (buf_index >= max_header_length) return error.OversizedHeader;
                        buf[buf_index] = byte;
                        buf_index += 1;
                    },
                }
            }
            const colon_index = maybe_colon_index orelse return error.InvalidHEaderField;
            const header = buf[0..buf_index];
            const header_name = header[0..colon_index];
            const header_value = header[colon_index..];
            if (!std.ascii.eqlIgnoreCase(header_name, "content-length")) return error.InvalidHeaderField;
            content_length = try std.fmt.parseUnsigned(usize, header_value, 10);
        }
        return LSPHeader{ .content_length = content_length };
    }
};

test "headerParse" {
    var fbs = std.io.fixedBufferStream("Content-Length: 22\r\n\r\n{\"method\":\"testing\"}");
    const header = try LSPHeader.parse(fbs.reader().any());
    try std.testing.expectEqual(22, header.content_length);
    const json_message = try std.testing.allocator.alloc(u8, header.content_length);
    defer std.testing.allocator.free(json_message);
    try fbs.reader().readNoEof(json_message);
    const method = try rpc.parseMethod(std.testing.allocator, json_message);
    defer std.testing.allocator.free(method);
    try std.testing.expectEqualStrings("testing", method);
}
