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

    // Print detected languages
    if (result.detected_languages.len > 0) {
        std.debug.print("Detected language{s}: ", .{if (result.detected_languages.len > 1) "s" else ""});
        for (result.detected_languages, 0..) |lang, i| {
            if (i > 0) std.debug.print(", ", .{});
            std.debug.print("{s}", .{@tagName(lang)});
        }
        std.debug.print("\n", .{});
    }

    // Print detected languages
    if (result.detected_file_types.len > 0) {
        std.debug.print("Detected file type{s}: ", .{if (result.detected_file_types.len > 1) "s" else ""});
        for (result.detected_file_types, 0..) |additional, i| {
            if (i > 0) std.debug.print(", ", .{});
            std.debug.print("{s}", .{@tagName(additional)});
        }
        std.debug.print("\n", .{});
    }

    // Print configuration files removed
    if (result.excluded_files.configuration.len > 0) {
        std.debug.print("Configuration files removed:\n", .{});
        for (result.excluded_files.configuration) |file| {
            std.debug.print("- {s} ({} tokens)\n", .{ file.path, file.token_count });
        }
    }

    // Print token anomaly information
    if (result.excluded_files.token_anomaly.len > 0) {
        std.debug.print("Files excluded due to token count anomaly:\n", .{});
        for (result.excluded_files.token_anomaly) |file| {
            std.debug.print("- {s} ({} tokens)\n", .{ file.path, file.token_count });
        }
    } else {
        std.debug.print("Token count anomaly filter was not applied due to low total token count.\n", .{});
    }

    // Print included files
    std.debug.print("Included files after filtering:\n", .{});
    var total_tokens: usize = 0;
    for (result.included_files) |file| {
        std.debug.print("- {s} ({} tokens)\n", .{ file.path, file.token_count });
        total_tokens += file.token_count;
    }

    std.debug.print("Total tokens after filtering: {}\n", .{total_tokens});
}
