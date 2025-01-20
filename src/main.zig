const std = @import("std");
const file_handler = @import("file_handler.zig");
const cli = @import("cli.zig");
const output = @import("output.zig");

fn fileTypeToString(file_type: file_handler.FileType) []const u8 {
    return switch (file_type) {
        .language => |lang| @tagName(lang),
        .additional => |add| @tagName(add),
        .unknown => "unknown",
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Handle help flag first
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            cli.printHelp();
            return;
        }
    }

    var cli_options = cli.parseArgs(allocator, args) catch |err| {
        switch (err) {
            error.InvalidFormat => std.debug.print("Error: Invalid format specified\n", .{}),
            error.InvalidArgument => std.debug.print("Error: Invalid argument\n", .{}),
            error.MissingValue => std.debug.print("Error: Missing value for argument\n", .{}),
            error.OutOfMemory => std.debug.print("Error: Out of memory\n", .{}),
            else => std.debug.print("Error: {}\n", .{err}),
        }
        cli.printHelp();
        return err;
    };
    defer cli_options.deinit(allocator);

    const current_dir = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(current_dir);

    if (!cli_options.stdout_only) {
        std.debug.print("Processing directory: {s}\n", .{current_dir});
    }

    const options = file_handler.ProcessOptions{
        .ignore_patterns = cli_options.ignore_patterns orelse &.{"themes/"},
        .include_dot_files = cli_options.include_dot_files,
        .disable_config_filter = cli_options.disable_config_filter,
        .disable_token_filter = cli_options.disable_token_filter,
    };

    var result = try file_handler.processDirectory(allocator, current_dir, options);
    defer result.deinit();

    const stdout = std.io.getStdOut().writer();

    switch (cli_options.format) {
        .overview => {
            if (cli_options.stdout_only) return;

            // Print detected languages
            if (result.detected_languages.len > 0) {
                std.debug.print("Detected language{s}: ", .{if (result.detected_languages.len > 1) "s" else ""});
                for (result.detected_languages, 0..) |lang, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    std.debug.print("{s}", .{@tagName(lang)});
                }
                std.debug.print("\n", .{});
            }

            // Print detected file types
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
        },
        .xml => try output.writeXml(stdout, result),
        .json => try output.writeJson(stdout, result),
        .codeblocks => try output.writeCodeblocks(stdout, result),
    }
}
