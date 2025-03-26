const std = @import("std");
const file_handler = @import("file_handler.zig");
const git = @import("git.zig");
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

    // Write excluded files section
    try writer.writeAll("  <excluded-files>\n");
    for (result.excluded_files) |excluded| {
        try writer.print("    <file path=\"{s}\" tokens=\"{d}\" lines=\"{d}\" type=\"{s}\">\n", .{
            escapeXmlAttr(excluded.file.path),
            excluded.file.token_count,
            excluded.file.line_count,
            switch (excluded.file.file_type) {
                .language => |lang| @tagName(lang),
                .additional => |add| @tagName(add),
                .unknown => "unknown",
            },
        });
        try writer.writeAll("      <reason>");
        switch (excluded.reason) {
            .ignored => |pattern| try writer.print("ignored by pattern: {s}", .{escapeXmlText(pattern)}),
            .configuration => try writer.writeAll("configuration file"),
            .token_anomaly => |info| try writer.print("token count {d} exceeds threshold {d} (avg: {d:.2}, std_dev: {d:.2})", .{
                info.token_count,
                info.threshold,
                info.average,
                info.std_dev,
            }),
            .binary => try writer.writeAll("binary file"),
        }
        try writer.writeAll("</reason>\n");
        try writer.writeAll("    </file>\n");
    }
    try writer.writeAll("  </excluded-files>\n");

    // Write included files section
    try writer.writeAll("  <included-files>\n");
    for (result.included_files) |file| {
        try writer.print("    <file path=\"{s}\" tokens=\"{d}\" lines=\"{d}\" type=\"{s}\">\n", .{
            escapeXmlAttr(file.path),
            file.token_count,
            file.line_count,
            switch (file.file_type) {
                .language => |lang| @tagName(lang),
                .additional => |add| @tagName(add),
                .unknown => "unknown",
            },
        });
        try writer.writeAll("      ");
        try writeXmlEscapedCData(writer, file.content);
        try writer.writeAll("\n    </file>\n");
    }
    try writer.writeAll("  </included-files>\n");

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

    // Write excluded files
    try writer.writeAll("  \"excludedFiles\": [\n");
    for (result.excluded_files, 0..) |excluded, i| {
        if (i > 0) try writer.writeAll(",\n");
        try writer.writeAll("    {\n");
        try writer.print("      \"path\": \"{s}\",\n", .{excluded.file.path});
        try writer.print("      \"tokens\": {d},\n", .{excluded.file.token_count});
        try writer.print("      \"lines\": {d},\n", .{excluded.file.line_count});
        try writer.print("      \"type\": \"{s}\",\n", .{switch (excluded.file.file_type) {
            .language => |lang| @tagName(lang),
            .additional => |add| @tagName(add),
            .unknown => "unknown",
        }});
        try writer.writeAll("      \"reason\": ");
        switch (excluded.reason) {
            .ignored => |pattern| try writer.print("\"ignored by pattern: {s}\"", .{pattern}),
            .configuration => try writer.writeAll("\"configuration file\""),
            .token_anomaly => |info| try writer.print("\"token count {d} exceeds threshold {d} (avg: {d:.2}, std_dev: {d:.2})\"", .{
                info.token_count,
                info.threshold,
                info.average,
                info.std_dev,
            }),
            .binary => try writer.writeAll("\"binary file\""),
        }
        try writer.writeAll("\n    }");
    }
    try writer.writeAll("\n  ],\n");

    // Write included files
    try writer.writeAll("  \"includedFiles\": [\n");
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

    try writer.writeAll("\nexcluded_files:\n");
    for (result.excluded_files) |excluded| {
        try writer.print("  - path: {s}\n", .{excluded.file.path});
        try writer.print("    tokens: {d}\n", .{excluded.file.token_count});
        try writer.print("    lines: {d}\n", .{excluded.file.line_count});
        try writer.print("    type: {s}\n", .{switch (excluded.file.file_type) {
            .language => |lang| @tagName(lang),
            .additional => |add| @tagName(add),
            .unknown => "unknown",
        }});
        try writer.writeAll("    reason: ");
        switch (excluded.reason) {
            .ignored => |pattern| try writer.print("ignored by pattern: {s}\n", .{pattern}),
            .configuration => try writer.writeAll("configuration file\n"),
            .token_anomaly => |info| try writer.print("token count {d} exceeds threshold {d} (avg: {d:.2}, std_dev: {d:.2})\n", .{
                info.token_count,
                info.threshold,
                info.average,
                info.std_dev,
            }),
            .binary => try writer.writeAll("binary file\n"),
        }
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

pub fn writeCtx(writer: anytype, result: file_handler.ProcessResult, project_name: ?[]const u8) !void {
    // Calculate total tokens
    var total_tokens: usize = 0;
    for (result.included_files) |file| {
        total_tokens += file.token_count;
    }

    // Write header
    try writer.writeAll("/// code context ///\n");
    try writer.writeAll("|| METADATA\n");
    
    // Project name (if available)
    if (project_name) |name| {
        try writer.print("project::{s}\n", .{name});
    }
    
    // Files and tokens counts
    try writer.print("files::{d}\n", .{result.included_files.len});
    try writer.print("tokens::{d}\n", .{total_tokens});
    
    // All detected languages
    if (result.detected_languages.len > 0) {
        try writer.writeAll("languages::");
        for (result.detected_languages, 0..) |lang, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("{s}", .{@tagName(lang)});
        }
        try writer.writeAll("\n");
    }
    
    // All detected file types
    if (result.detected_file_types.len > 0) {
        try writer.writeAll("file_types::");
        for (result.detected_file_types, 0..) |file_type, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("{s}", .{@tagName(file_type)});
        }
        try writer.writeAll("\n");
    }
    
    try writer.writeAll("||\n\n");

    // Write each included file
    for (result.included_files) |file| {
        // Write file header with horizontal rule
        try writer.writeAll("────────────────<< FILE >>────────────────\n");
        try writer.print("path::{s}\n", .{file.path});
        try writer.print("tokens::{d}\n", .{file.token_count});
        try writer.print("lines::{d}\n", .{file.line_count});
        
        // Start content section
        try writer.writeAll("────────────────<< START >>────────────────\n");
        try writer.writeAll(file.content);
        try writer.writeAll("\n────────────────<< END >>────────────────\n\n");
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

fn writeXmlEscapedCData(writer: anytype, content: []const u8) !void {
    var start: usize = 0;
    var i: usize = 0;
    try writer.writeAll("<![CDATA[");
    while (i < content.len) : (i += 1) {
        if (i + 2 < content.len and std.mem.eql(u8, content[i .. i + 3], "]]>")) {
            // Write content up to this point
            try writer.writeAll(content[start..i]);
            // Close current CDATA and start a new one
            try writer.writeAll("]]]]><![CDATA[>");
            i += 2; // Skip over the "]]>" since we've handled it
            start = i + 1;
        }
    }
    // Write remaining content
    try writer.writeAll(content[start..]);
    try writer.writeAll("]]>");
}

fn escapeXmlText(text: []const u8) []const u8 {
    // For now, just return the text unescaped
    // TODO: Implement proper XML text escaping
    return text;
}

fn escapeXmlAttr(text: []const u8) []const u8 {
    // For now, just return the text unescaped
    // TODO: Implement proper XML attribute escaping
    return text;
}