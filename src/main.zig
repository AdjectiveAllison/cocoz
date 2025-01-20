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
            error.NoTargetsSpecified => std.debug.print("Error: No target directories or files specified\n", .{}),
            else => std.debug.print("Error: {}\n", .{err}),
        }
        cli.printHelp();
        return err;
    };
    defer cli_options.deinit(allocator);

    const options = file_handler.ProcessOptions{
        .ignore_patterns = cli_options.ignore_patterns orelse &.{"themes/"},
        .include_dot_files = cli_options.include_dot_files,
        .disable_config_filter = cli_options.disable_config_filter,
        .disable_token_filter = cli_options.disable_token_filter,
    };

    // Process each target and combine results
    var all_files = std.ArrayList(file_handler.FileInfo).init(allocator);
    defer {
        for (all_files.items) |*file| {
            file.deinit(allocator);
        }
        all_files.deinit();
    }

    var all_excluded = std.ArrayList(file_handler.ExcludedFile).init(allocator);
    defer {
        for (all_excluded.items) |*file| {
            file.deinit(allocator);
        }
        all_excluded.deinit();
    }

    var unique_languages = std.AutoHashMap(file_handler.Language, void).init(allocator);
    defer unique_languages.deinit();

    var unique_file_types = std.AutoHashMap(file_handler.AdditionalFileType, void).init(allocator);
    defer unique_file_types.deinit();

    for (cli_options.targets) |target| {
        if (!cli_options.stdout_only) {
            std.debug.print("Processing target: {s}\n", .{target});
        }

        var result = try file_handler.processTarget(allocator, target, options);
        defer result.deinit();

        // Combine files
        for (result.included_files) |file| {
            const duped_path = try allocator.dupe(u8, file.path);
            errdefer allocator.free(duped_path);
            const duped_content = try allocator.dupe(u8, file.content);
            errdefer allocator.free(duped_content);

            try all_files.append(.{
                .path = duped_path,
                .content = duped_content,
                .token_count = file.token_count,
                .line_count = file.line_count,
                .file_type = file.file_type,
            });
        }

        // Combine excluded files
        for (result.excluded_files) |excluded| {
            const duped_path = try allocator.dupe(u8, excluded.file.path);
            errdefer allocator.free(duped_path);
            const duped_content = try allocator.dupe(u8, excluded.file.content);
            errdefer allocator.free(duped_content);
            const duped_file = file_handler.FileInfo{
                .path = duped_path,
                .content = duped_content,
                .token_count = excluded.file.token_count,
                .line_count = excluded.file.line_count,
                .file_type = excluded.file.file_type,
            };

            const duped_reason = switch (excluded.reason) {
                .ignored => |pattern| file_handler.ExclusionReason{ .ignored = try allocator.dupe(u8, pattern) },
                .configuration => .configuration,
                .token_anomaly => |info| file_handler.ExclusionReason{
                    .token_anomaly = .{
                        .token_count = info.token_count,
                        .threshold = info.threshold,
                        .average = info.average,
                        .std_dev = info.std_dev,
                    },
                },
                .binary => .binary,
            };

            try all_excluded.append(.{
                .file = duped_file,
                .reason = duped_reason,
            });
        }

        // Combine languages and file types
        for (result.detected_languages) |lang| {
            try unique_languages.put(lang, {});
        }

        for (result.detected_file_types) |file_type| {
            try unique_file_types.put(file_type, {});
        }
    }

    // Create combined result
    var combined_result = file_handler.ProcessResult{
        .included_files = try all_files.toOwnedSlice(),
        .excluded_files = try all_excluded.toOwnedSlice(),
        .detected_languages = blk: {
            var langs = try allocator.alloc(file_handler.Language, unique_languages.count());
            errdefer allocator.free(langs);
            var i: usize = 0;
            var it = unique_languages.keyIterator();
            while (it.next()) |lang| {
                langs[i] = lang.*;
                i += 1;
            }
            break :blk langs;
        },
        .detected_file_types = blk: {
            var types = try allocator.alloc(file_handler.AdditionalFileType, unique_file_types.count());
            errdefer allocator.free(types);
            var i: usize = 0;
            var it = unique_file_types.keyIterator();
            while (it.next()) |file_type| {
                types[i] = file_type.*;
                i += 1;
            }
            break :blk types;
        },
        .allocator = allocator,
    };
    defer combined_result.deinit();

    const stdout = std.io.getStdOut().writer();

    switch (cli_options.format) {
        .overview => {
            if (cli_options.stdout_only) return;

            // Print detected languages
            if (combined_result.detected_languages.len > 0) {
                std.debug.print("Detected language{s}: ", .{if (combined_result.detected_languages.len > 1) "s" else ""});
                for (combined_result.detected_languages, 0..) |lang, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    std.debug.print("{s}", .{@tagName(lang)});
                }
                std.debug.print("\n", .{});
            }

            // Print detected file types
            if (combined_result.detected_file_types.len > 0) {
                std.debug.print("Detected file type{s}: ", .{if (combined_result.detected_file_types.len > 1) "s" else ""});
                for (combined_result.detected_file_types, 0..) |additional, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    std.debug.print("{s}", .{@tagName(additional)});
                }
                std.debug.print("\n", .{});
            }

            // Print excluded files
            if (combined_result.excluded_files.len > 0) {
                std.debug.print("\nExcluded files:\n", .{});
                for (combined_result.excluded_files) |excluded| {
                    switch (excluded.reason) {
                        .ignored => |pattern| std.debug.print("- {s} (ignored by pattern: {s})\n", .{ excluded.file.path, pattern }),
                        .configuration => std.debug.print("- {s} (configuration file)\n", .{excluded.file.path}),
                        .token_anomaly => |info| std.debug.print("- {s} (token count {d} exceeds threshold {d}, avg: {d:.2}, std_dev: {d:.2})\n", .{
                            excluded.file.path,
                            info.token_count,
                            info.threshold,
                            info.average,
                            info.std_dev,
                        }),
                        .binary => std.debug.print("- {s} (binary file)\n", .{excluded.file.path}),
                    }
                }
                std.debug.print("\n", .{});
            }

            // Print included files
            std.debug.print("Included files after filtering:\n", .{});
            var total_tokens: usize = 0;
            for (combined_result.included_files) |file| {
                std.debug.print("- {s} ({} tokens)\n", .{ file.path, file.token_count });
                total_tokens += file.token_count;
            }

            std.debug.print("\nTotal tokens after filtering: {}\n", .{total_tokens});
        },
        .xml => try output.writeXml(stdout, combined_result),
        .json => try output.writeJson(stdout, combined_result),
        .codeblocks => try output.writeCodeblocks(stdout, combined_result),
    }
}
