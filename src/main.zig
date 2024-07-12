const std = @import("std");
const file_handler = @import("file_handler.zig");

fn fileTypeToString(file_type: file_handler.FileType) []const u8 {
    return switch (file_type) {
        .language => |lang| @tagName(lang),
        .additional => |add| @tagName(add),
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const current_dir = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(current_dir);

    std.debug.print("Processing directory: {s}\n", .{current_dir});

    const options = file_handler.ProcessOptions{};

    var result = try file_handler.processDirectory(allocator, current_dir, options);
    defer result.deinit();

    const total_files = result.included_files.len +
        result.excluded_files.ignored.len +
        result.excluded_files.configuration.len +
        result.excluded_files.token_anomaly.len;

    std.debug.print("Found {} files\n", .{total_files});

    std.debug.print("\nIncluded files:\n", .{});
    for (result.included_files, 0..) |file, i| {
        std.debug.print("Debug: Processing file index: {}\n", .{i});

        std.debug.print("Debug: File path length: {}\n", .{file.path.len});

        std.debug.print("Debug: File path characters: ", .{});
        for (file.path) |char| {
            std.debug.print("{c}", .{char});
        }
        std.debug.print("\n", .{});

        // Try writing to stderr instead
        try std.io.getStdErr().writer().print("Debug: File path (stderr): {s}\n", .{file.path});

        std.debug.print("Debug: Getting file type string\n", .{});
        const file_type_str = fileTypeToString(file.file_type);
        std.debug.print("Debug: File type string: {s}\n", .{file_type_str});

        std.debug.print("Debug: Line count: {}\n", .{file.line_count});

        std.debug.print("File: {s}, Type: {s}, Lines: {}\n", .{ file.path, file_type_str, file.line_count });
    }

    std.debug.print("\nAfter processing:\n", .{});
    std.debug.print("Included files: {}\n", .{result.included_files.len});
    std.debug.print("Excluded ignored files: {}\n", .{result.excluded_files.ignored.len});
    std.debug.print("Excluded configuration files: {}\n", .{result.excluded_files.configuration.len});
    std.debug.print("Excluded token anomaly files: {}\n", .{result.excluded_files.token_anomaly.len});

    std.debug.print("\nDetected languages:\n", .{});
    for (result.detected_languages) |lang| {
        std.debug.print("- {s}\n", .{@tagName(lang)});
    }
}
