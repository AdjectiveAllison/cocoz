const std = @import("std");
const file_handler = @import("file_handler.zig");
const Allocator = std.mem.Allocator;

pub const OutputError = error{
    WriterError,
    OutOfMemory,
};

pub fn writeXml(writer: anytype, result: file_handler.ProcessResult) !void {
    try writer.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    try writer.writeAll("<code-context>\n");

    // Write metadata section
    try writer.writeAll("  <metadata>\n");
    try writer.print("    <total-files>{d}</total-files>\n", .{result.included_files.len});
    try writer.print("    <total-tokens>{d}</total-tokens>\n", .{blk: {
        var sum: usize = 0;
        for (result.included_files) |file| {
            sum += file.token_count;
        }
        break :blk sum;
    }});

    // Write detected languages
    try writer.writeAll("    <languages>\n");
    for (result.detected_languages) |lang| {
        try writer.print("      <language>{s}</language>\n", .{@tagName(lang)});
    }
    try writer.writeAll("    </languages>\n");

    // Write detected file types
    try writer.writeAll("    <file-types>\n");
    for (result.detected_file_types) |file_type| {
        try writer.print("      <file-type>{s}</file-type>\n", .{@tagName(file_type)});
    }
    try writer.writeAll("    </file-types>\n");
    try writer.writeAll("  </metadata>\n");

    // Write files section
    try writer.writeAll("  <files>\n");
    for (result.included_files) |file| {
        try writer.print("    <file path=\"{s}\" tokens=\"{d}\" lines=\"{d}\" type=\"{s}\">\n", .{
            file.path,
            file.token_count,
            file.line_count,
            switch (file.file_type) {
                .language => |lang| @tagName(lang),
                .additional => |add| @tagName(add),
                .unknown => "unknown",
            },
        });
        try writer.writeAll("      <![CDATA[\n");
        try writer.writeAll(file.content);
        try writer.writeAll("\n      ]]>\n");
        try writer.writeAll("    </file>\n");
    }
    try writer.writeAll("  </files>\n");

    try writer.writeAll("</code-context>\n");
}

pub fn writeJson(writer: anytype, result: file_handler.ProcessResult) !void {
    try writer.writeAll("{\n");

    // Write metadata
    try writer.writeAll("  \"metadata\": {\n");
    try writer.print("    \"totalFiles\": {d},\n", .{result.included_files.len});
    try writer.print("    \"totalTokens\": {d},\n", .{blk: {
        var sum: usize = 0;
        for (result.included_files) |file| {
            sum += file.token_count;
        }
        break :blk sum;
    }});

    // Write languages
    try writer.writeAll("    \"languages\": [");
    for (result.detected_languages, 0..) |lang, i| {
        if (i > 0) try writer.writeAll(", ");
        try writer.print("\"{s}\"", .{@tagName(lang)});
    }
    try writer.writeAll("],\n");

    // Write file types
    try writer.writeAll("    \"fileTypes\": [");
    for (result.detected_file_types, 0..) |file_type, i| {
        if (i > 0) try writer.writeAll(", ");
        try writer.print("\"{s}\"", .{@tagName(file_type)});
    }
    try writer.writeAll("]\n  },\n");

    // Write files
    try writer.writeAll("  \"files\": [\n");
    for (result.included_files, 0..) |file, i| {
        if (i > 0) try writer.writeAll(",\n");
        try writer.writeAll("    {\n");
        try writer.print("      \"path\": \"{s}\",\n", .{file.path});
        try writer.print("      \"tokens\": {d},\n", .{file.token_count});
        try writer.print("      \"lines\": {d},\n", .{file.line_count});
        try writer.print("      \"type\": \"{s}\",\n", .{switch (file.file_type) {
            .language => |lang| @tagName(lang),
            .additional => |add| @tagName(add),
            .unknown => "unknown",
        }});
        try writer.writeAll("      \"content\": ");
        try writeJsonString(writer, file.content);
        try writer.writeAll("\n    }");
    }
    try writer.writeAll("\n  ]\n}\n");
}

pub fn writeCodeblocks(writer: anytype, result: file_handler.ProcessResult) !void {
    // Write metadata as YAML frontmatter
    try writer.writeAll("---\n");
    try writer.print("total_files: {d}\n", .{result.included_files.len});
    try writer.print("total_tokens: {d}\n", .{blk: {
        var sum: usize = 0;
        for (result.included_files) |file| {
            sum += file.token_count;
        }
        break :blk sum;
    }});

    try writer.writeAll("languages:\n");
    for (result.detected_languages) |lang| {
        try writer.print("  - {s}\n", .{@tagName(lang)});
    }

    try writer.writeAll("file_types:\n");
    for (result.detected_file_types) |file_type| {
        try writer.print("  - {s}\n", .{@tagName(file_type)});
    }
    try writer.writeAll("---\n\n");

    // Write files as markdown code blocks
    for (result.included_files) |file| {
        const lang_str = switch (file.file_type) {
            .language => |lang| @tagName(lang),
            .additional => |add| @tagName(add),
            .unknown => "",
        };

        try writer.print("## {s}\n", .{file.path});
        try writer.print("```{s}\n", .{lang_str});
        try writer.writeAll(file.content);
        try writer.writeAll("\n```\n\n");
    }
}

fn writeJsonString(writer: anytype, string: []const u8) !void {
    try writer.writeAll("\"");
    for (string) |c| {
        if (c == '"' or c == '\\') {
            try writer.writeByte('\\');
            try writer.writeByte(c);
        } else if (c == '\n') {
            try writer.writeAll("\\n");
        } else if (c == '\r') {
            try writer.writeAll("\\r");
        } else if (c == '\t') {
            try writer.writeAll("\\t");
        } else if (c < 0x20) {
            try writer.print("\\u{x:0>4}", .{c});
        } else {
            try writer.writeByte(c);
        }
    }
    try writer.writeAll("\"");
}
