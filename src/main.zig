const std = @import("std");
const file_handler = @import("file_handler.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const current_dir = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(current_dir);

    std.debug.print("Processing directory: {s}\n", .{current_dir});

    const options = file_handler.FileProcessorOptions{
        // .disable_config_filter = true,
        // You can customize these options as needed
        // .extensions = &.{ ".zig", ".txt", ".md", ".json" },
    };

    const files = try file_handler.processDirectory(allocator, current_dir, options);
    defer {
        for (files) |file| {
            allocator.free(file.path);
            allocator.free(file.content);
        }
        allocator.free(files);
    }

    std.debug.print("Found {} files\n", .{files.len});

    for (files) |file| {
        std.debug.print("File: {s}, Language: {}, Lines: {}\n", .{ file.path, file.language, file.line_count });
    }

    const filtered_result = try file_handler.filterFiles(allocator, files, options);
    defer {
        allocator.free(filtered_result.filtered_files);
        allocator.free(filtered_result.removed_files.ignored);
        allocator.free(filtered_result.removed_files.configuration_files);
        allocator.free(filtered_result.removed_files.token_anomaly);
        allocator.free(filtered_result.detected_languages);
    }

    std.debug.print("\nAfter filtering:\n", .{});
    std.debug.print("Filtered files: {}\n", .{filtered_result.filtered_files.len});
    std.debug.print("Removed ignored files: {}\n", .{filtered_result.removed_files.ignored.len});
    std.debug.print("Removed configuration files: {}\n", .{filtered_result.removed_files.configuration_files.len});
    std.debug.print("Removed token anomaly files: {}\n", .{filtered_result.removed_files.token_anomaly.len});

    std.debug.print("\nDetected languages:\n", .{});
    for (filtered_result.detected_languages) |lang| {
        std.debug.print("- {}\n", .{lang});
    }
}
