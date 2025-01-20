const std = @import("std");
const Allocator = std.mem.Allocator;

pub const OutputFormat = enum {
    overview,
    xml,
    json,
    codeblocks,

    pub fn fromString(str: []const u8) !OutputFormat {
        inline for (std.meta.fields(OutputFormat)) |field| {
            if (std.mem.eql(u8, str, field.name)) {
                return @field(OutputFormat, field.name);
            }
        }
        return error.InvalidFormat;
    }
};

pub const Options = struct {
    format: OutputFormat = .overview,
    extensions: ?[]const []const u8 = null,
    ignore_patterns: ?[]const []const u8 = null,
    max_tokens: ?usize = null,
    disable_language_filter: bool = false,
    disable_config_filter: bool = false,
    disable_token_filter: bool = false,
    include_dot_files: ?[]const []const u8 = null,
    stdout_only: bool = false,
    targets: []const []const u8,

    pub fn deinit(self: *Options, allocator: Allocator) void {
        if (self.extensions) |extensions| {
            for (extensions) |ext| {
                allocator.free(ext);
            }
            allocator.free(extensions);
        }
        if (self.ignore_patterns) |patterns| {
            for (patterns) |pattern| {
                allocator.free(pattern);
            }
            allocator.free(patterns);
        }
        if (self.include_dot_files) |dot_files| {
            for (dot_files) |file| {
                allocator.free(file);
            }
            allocator.free(dot_files);
        }
        for (self.targets) |target| {
            allocator.free(target);
        }
        allocator.free(self.targets);
    }
};

const ParseError = error{
    InvalidFormat,
    InvalidArgument,
    MissingValue,
    OutOfMemory,
    NoTargetsSpecified,
};

pub fn parseArgs(allocator: Allocator, args: []const []const u8) !Options {
    if (args.len <= 1) return error.NoTargetsSpecified;

    var options = Options{
        .targets = undefined,
    };
    var targets = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (targets.items) |target| {
            allocator.free(target);
        }
        targets.deinit();
    }

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.eql(u8, arg, "--stdout")) {
                options.stdout_only = true;
            } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--format")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                options.format = try OutputFormat.fromString(args[i]);
            } else if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--extensions")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                const extensions = try parseList(allocator, args[i]);
                options.extensions = extensions;
            } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--ignore")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                const patterns = try parseList(allocator, args[i]);
                options.ignore_patterns = patterns;
            } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--max-tokens")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                options.max_tokens = try std.fmt.parseInt(usize, args[i], 10);
            } else if (std.mem.eql(u8, arg, "--disable-language-filter")) {
                options.disable_language_filter = true;
            } else if (std.mem.eql(u8, arg, "--disable-config-filter")) {
                options.disable_config_filter = true;
            } else if (std.mem.eql(u8, arg, "--disable-token-filter")) {
                options.disable_token_filter = true;
            } else if (std.mem.eql(u8, arg, "--include-dot-files")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                const dot_files = try parseList(allocator, args[i]);
                options.include_dot_files = dot_files;
            } else {
                return error.InvalidArgument;
            }
        } else {
            // Non-flag argument is treated as a target directory/file
            const duped = try allocator.dupe(u8, arg);
            try targets.append(duped);
        }
    }

    if (targets.items.len == 0) {
        // If no targets specified, use current directory
        const duped = try allocator.dupe(u8, ".");
        try targets.append(duped);
    }

    options.targets = try targets.toOwnedSlice();
    return options;
}

fn parseList(allocator: Allocator, input: []const u8) ![]const []const u8 {
    var list = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (list.items) |item| {
            allocator.free(item);
        }
        list.deinit();
    }

    var it = std.mem.split(u8, input, ",");
    while (it.next()) |item| {
        const trimmed = std.mem.trim(u8, item, " ");
        if (trimmed.len == 0) continue;
        const duped = try allocator.dupe(u8, trimmed);
        try list.append(duped);
    }

    return try list.toOwnedSlice();
}

pub fn printHelp() void {
    const help_text =
        \\Usage: code-contextor-zig [options] [directory|file ...]
        \\
        \\Arguments:
        \\  directory|file          Directory or file to process (default: current directory)
        \\                         Multiple directories/files can be specified
        \\
        \\Options:
        \\  -f, --format <format>       Output format (overview, xml, json, codeblocks)
        \\  -e, --extensions <list>     Comma-separated list of file extensions to include
        \\  -i, --ignore <list>         Comma-separated list of patterns to ignore
        \\  -m, --max-tokens <number>   Maximum number of tokens to process
        \\  --stdout                    Only output the formatted content
        \\  --disable-language-filter   Disable language-based filtering
        \\  --disable-config-filter     Disable configuration file filtering
        \\  --disable-token-filter      Disable token count anomaly filtering
        \\  --include-dot-files <list>  Comma-separated list of dot files to include
        \\  -h, --help                  Show this help message
        \\
        \\Examples:
        \\  code-contextor-zig                     # Process current directory
        \\  code-contextor-zig src/                # Process src directory
        \\  code-contextor-zig file1.c file2.c     # Process specific files
        \\  code-contextor-zig -f json src/        # Output JSON format
        \\
    ;
    std.debug.print("{s}", .{help_text});
}
