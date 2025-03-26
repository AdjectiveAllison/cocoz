const std = @import("std");
const file_handler = @import("file_handler.zig");
const cli = @import("cli.zig");
const output = @import("output.zig");
const git = @import("git.zig");

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
        .ignore_patterns = blk: {
            if (cli_options.ignore_patterns) |user_patterns| {
                // Combine default and user patterns
                const combined = try allocator.alloc([]const u8, file_handler.default_ignore_patterns.len + user_patterns.len);
                @memcpy(combined[0..file_handler.default_ignore_patterns.len], file_handler.default_ignore_patterns);
                @memcpy(combined[file_handler.default_ignore_patterns.len..], user_patterns);
                break :blk combined;
            }
            break :blk file_handler.default_ignore_patterns;
        },
        .include_dot_files = cli_options.include_dot_files,
        .disable_config_filter = cli_options.disable_config_filter,
        .disable_token_filter = cli_options.disable_token_filter,
        .disable_language_filter = cli_options.disable_language_filter,
        .extensions = cli_options.extensions,
        .max_tokens = cli_options.max_tokens,
    };
    defer if (options.ignore_patterns.ptr != file_handler.default_ignore_patterns.ptr) {
        allocator.free(options.ignore_patterns);
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

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    for (cli_options.targets) |target| {
        if (!cli_options.stdout_only) {
            try stderr.print("Processing target: {s}\n", .{target});
        }

        var result = try file_handler.processTarget(allocator, target, options);
        defer {
            // Clear the arrays before deinit to prevent double-free
            result.included_files = &.{};
            result.excluded_files = &.{};
            result.detected_languages = &.{};
            result.detected_file_types = &.{};
            result.deinit();
        }

        // Transfer ownership of included files
        try all_files.appendSlice(result.included_files);
        allocator.free(result.included_files);
        result.included_files = &.{};

        // Transfer ownership of excluded files
        try all_excluded.appendSlice(result.excluded_files);
        allocator.free(result.excluded_files);
        result.excluded_files = &.{};

        // Combine languages and file types
        for (result.detected_languages) |lang| {
            try unique_languages.put(lang, {});
        }
        allocator.free(result.detected_languages);
        result.detected_languages = &.{};

        for (result.detected_file_types) |file_type| {
            try unique_file_types.put(file_type, {});
        }
        allocator.free(result.detected_file_types);
        result.detected_file_types = &.{};
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

    // Get current directory for project name detection
    const cwd_path_buffer = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd_path_buffer);
    
    // Get project name for ctx format if needed
    const project_name = if (cli_options.format == .ctx) 
        git.getRepoName(allocator, cwd_path_buffer) catch null
    else
        null;
    defer if (project_name) |name| allocator.free(name);

    switch (cli_options.format) {
        .overview => {
            if (!cli_options.stdout_only) {
                // Print detected languages
                if (combined_result.detected_languages.len > 0) {
                    try stderr.print("Detected language{s}: ", .{if (combined_result.detected_languages.len > 1) "s" else ""});
                    for (combined_result.detected_languages, 0..) |lang, i| {
                        if (i > 0) try stderr.writeAll(", ");
                        try stderr.print("{s}", .{@tagName(lang)});
                    }
                    try stderr.writeAll("\n");
                }

                // Print detected file types
                if (combined_result.detected_file_types.len > 0) {
                    try stderr.print("Detected file type{s}: ", .{if (combined_result.detected_file_types.len > 1) "s" else ""});
                    for (combined_result.detected_file_types, 0..) |additional, i| {
                        if (i > 0) try stderr.writeAll(", ");
                        try stderr.print("{s}", .{@tagName(additional)});
                    }
                    try stderr.writeAll("\n");
                }

                // Print excluded files
                if (combined_result.excluded_files.len > 0) {
                    try stderr.writeAll("\nExcluded files:\n");
                    for (combined_result.excluded_files) |excluded| {
                        switch (excluded.reason) {
                            .ignored => |pattern| try stderr.print("- {s} (ignored by pattern: {s})\n", .{ excluded.file.path, pattern }),
                            .configuration => try stderr.print("- {s} (configuration file)\n", .{excluded.file.path}),
                            .token_anomaly => |info| try stderr.print("- {s} (token count {d} exceeds threshold {d}, avg: {d:.2}, std_dev: {d:.2})\n", .{
                                excluded.file.path,
                                info.token_count,
                                info.threshold,
                                info.average,
                                info.std_dev,
                            }),
                            .binary => try stderr.print("- {s} (binary file)\n", .{excluded.file.path}),
                        }
                    }
                    try stderr.writeAll("\n");
                }

                // Print included files
                try stderr.writeAll("Included files after filtering:\n");
                var total_tokens: usize = 0;
                for (combined_result.included_files) |file| {
                    try stderr.print("- {s} ({} tokens)\n", .{ file.path, file.token_count });
                    total_tokens += file.token_count;
                }

                try stderr.print("\nTotal tokens after filtering: {}\n", .{total_tokens});
            }
        },
        .xml => try output.writeXml(stdout, combined_result),
        .json => try output.writeJson(stdout, combined_result),
        .codeblocks => try output.writeCodeblocks(stdout, combined_result),
        .ctx => try output.writeCtx(stdout, combined_result, project_name),
    }
}
