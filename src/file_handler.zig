const std = @import("std");
const fs = std.fs;
const path = std.fs.path;
const Allocator = std.mem.Allocator;

pub const FileInfo = struct {
    path: []const u8,
    content: []const u8,
    token_count: usize,
    line_count: usize,
    language: Language,
};

pub const FileType = union(enum) {
    language: Language,
    additional: AdditionalFileType,
};

pub const RemovedFiles = struct {
    ignored: []FileInfo,
    configuration_files: []FileInfo,
    token_anomaly: []FileInfo,
};

pub const FilterResult = struct {
    filtered_files: []FileInfo,
    removed_files: RemovedFiles,
    detected_languages: []Language,
};

pub const Language = enum {
    javascript,
    typescript,
    python,
    java,
    csharp,
    cpp,
    php,
    ruby,
    go,
    rust,
    swift,
    kotlin,
    scala,
    zig,
    unknown,

    pub fn fromExtension(ext: []const u8) Language {
        const extensions = [_]struct { []const u8, Language }{
            .{ ".js", .javascript }, .{ ".jsx", .javascript }, .{ ".mjs", .javascript },
            .{ ".ts", .typescript }, .{ ".tsx", .typescript }, .{ ".py", .python },
            .{ ".pyw", .python },    .{ ".java", .java },      .{ ".cs", .csharp },
            .{ ".cpp", .cpp },       .{ ".cxx", .cpp },        .{ ".cc", .cpp },
            .{ ".c", .cpp },         .{ ".h", .cpp },          .{ ".hpp", .cpp },
            .{ ".php", .php },       .{ ".rb", .ruby },        .{ ".go", .go },
            .{ ".rs", .rust },       .{ ".swift", .swift },    .{ ".kt", .kotlin },
            .{ ".kts", .kotlin },    .{ ".scala", .scala },    .{ ".zig", .zig },
        };
        for (extensions) |entry| {
            if (std.mem.eql(u8, ext, entry[0])) {
                return entry[1];
            }
        }
        return .unknown;
    }
};

pub const AdditionalFileType = enum {
    yaml,
    yml,
    toml,
    ini,
    conf,
    json,
    zon,
    md,
    rst,
    txt,
    png,
    jpg,
    jpeg,
    gif,
    svg,

    pub const FileTypeInfo = union(enum) {
        config: void,
        documentation: void,
        image: void,
    };

    pub fn getInfo(self: AdditionalFileType) FileTypeInfo {
        return switch (self) {
            .yaml, .yml, .toml, .ini, .conf, .json, .zon => .config,
            .md, .rst, .txt => .documentation,
            .png, .jpg, .jpeg, .gif, .svg => .image,
        };
    }

    pub fn getDisplayName(self: AdditionalFileType) []const u8 {
        return switch (self) {
            .yaml, .yml => "YAML",
            .toml => "TOML",
            .ini => "INI",
            .conf => "Config",
            .json => "JSON",
            .md => "Markdown",
            .rst => "reStructuredText",
            .txt => "Plain Text",
            .png, .jpg, .jpeg => "Image",
            .gif => "GIF",
            .svg => "SVG",
        };
    }

    pub fn fromExtension(ext: []const u8) ?AdditionalFileType {
        inline for (std.meta.fields(AdditionalFileType)) |field| {
            if (std.mem.eql(u8, ext[1..], field.name)) {
                return @field(AdditionalFileType, field.name);
            }
        }
        return null;
    }
};

pub const TokenAnomalyThreshold = 10000;
pub const TotalTokenThreshold = 50000;

pub const FileProcessorOptions = struct {
    output_file: ?[]const u8 = null,
    ignore_patterns: []const []const u8 = &.{
        // Default ignores
        ".git",           ".svn",           ".hg",           ".bzr",              "CVS",
        ".gitignore",     ".gitattributes", ".gitmodules",
        // Language-specific ignores
          "package-lock.json", "yarn.lock",
        "npm-debug.log",  "*.tsbuildinfo",  "Pipfile.lock",  "*.pyc",             "__pycache__",
        "*.class",        "*.jar",          "target/",       "bin/",              "obj/",
        "*.o",            "*.obj",          "*.exe",         "*.dll",             "*.so",
        "*.dylib",        "vendor/",        "composer.lock", "Gemfile.lock",      "*.gem",
        "go.sum",         "Cargo.lock",     "*.swiftmodule", "*.swiftdoc",        "*.kotlin_module",
        "build/",         ".zig-cache",     "node_modules",
        // Build files
         "build.zig",         "Makefile",
        "CMakeLists.txt",
    },
    include_dot_files: ?[]const []const u8 = null,
    extensions: ?[]const []const u8 = null,
    disable_ignore_filter: bool = false,
    disable_config_filter: bool = false,
    disable_token_filter: bool = false,
};

fn readGitignore(allocator: Allocator, directory: []const u8) ![]const []const u8 {
    const gitignore_path = try path.join(allocator, &.{ directory, ".gitignore" });
    defer allocator.free(gitignore_path);

    const file = std.fs.openFileAbsolute(gitignore_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    var patterns = std.ArrayList([]const u8).init(allocator);
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "#")) {
            try patterns.append(try allocator.dupe(u8, trimmed));
        }
    }

    return patterns.toOwnedSlice();
}

pub fn processDirectory(allocator: Allocator, directory: []const u8, options: FileProcessorOptions) ![]FileInfo {
    const gitignore_patterns = try readGitignore(allocator, directory);
    defer {
        for (gitignore_patterns) |pattern| {
            allocator.free(pattern);
        }
        allocator.free(gitignore_patterns);
    }

    var combined_ignore_patterns = try std.ArrayList([]const u8).initCapacity(allocator, options.ignore_patterns.len + gitignore_patterns.len);
    defer combined_ignore_patterns.deinit();
    try combined_ignore_patterns.appendSlice(options.ignore_patterns);
    try combined_ignore_patterns.appendSlice(gitignore_patterns);

    var modified_options = options;
    modified_options.ignore_patterns = combined_ignore_patterns.items;

    var files = std.ArrayList(FileInfo).init(allocator);
    defer files.deinit();

    var dir = try std.fs.openDirAbsolute(directory, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;

        const rel_path = try path.relative(allocator, directory, entry.path);
        defer allocator.free(rel_path);

        const file_path = try path.join(allocator, &.{ directory, entry.path });
        defer allocator.free(file_path);

        if (options.extensions) |exts| {
            const file_ext = path.extension(entry.path);
            var extension_match = false;
            for (exts) |ext| {
                if (std.mem.eql(u8, file_ext, ext)) {
                    extension_match = true;
                    break;
                }
            }
            if (!extension_match) continue;
        }

        const content = try fs.cwd().readFileAlloc(allocator, file_path, std.math.maxInt(usize));

        const file_type = getFileType(file_path);
        const language = switch (file_type) {
            .language => |lang| lang,
            .additional => .unknown,
        };

        try files.append(.{
            .path = try allocator.dupe(u8, rel_path),
            .content = content,
            .token_count = 0, // Will be set by JavaScript later
            .line_count = try countLines(content),
            .language = language,
        });
    }

    return files.toOwnedSlice();
}

fn shouldIgnore(file_path: []const u8, options: FileProcessorOptions) bool {
    if (options.disable_ignore_filter) return false;

    for (options.ignore_patterns) |pattern| {
        if (std.mem.indexOf(u8, file_path, pattern) != null) return true;
    }

    const base_name = path.basename(file_path);
    if (base_name.len > 0 and base_name[0] == '.' and options.include_dot_files == null) return true;

    if (options.include_dot_files) |dot_files| {
        for (dot_files) |pattern| {
            if (std.mem.indexOf(u8, base_name, pattern) != null) return false;
        }
    }

    if (options.output_file) |output| {
        if (std.mem.eql(u8, file_path, output)) return true;
    }

    return false;
}

fn countLines(content: []const u8) !usize {
    var line_count: usize = 1;
    for (content) |char| {
        if (char == '\n') line_count += 1;
    }
    return line_count;
}

pub fn filterFiles(allocator: Allocator, files: []FileInfo, options: FileProcessorOptions) !FilterResult {
    var filtered = std.ArrayList(FileInfo).init(allocator);
    var removed_ignored = std.ArrayList(FileInfo).init(allocator);
    var removed_config = std.ArrayList(FileInfo).init(allocator);
    var removed_token = std.ArrayList(FileInfo).init(allocator);
    var unique_languages = std.AutoHashMap(Language, void).init(allocator);
    defer unique_languages.deinit();

    for (files) |file| {
        var keep = true;

        if (!options.disable_ignore_filter) {
            if (shouldIgnore(file.path, options)) {
                try removed_ignored.append(file);
                keep = false;
                continue;
            }
        }

        if (keep and !options.disable_config_filter) {
            const file_type = getFileType(file.path);
            if (file_type == .additional) {
                const additional = file_type.additional;
                if (additional.getInfo() == .config) {
                    try removed_config.append(file);
                    keep = false;
                }
            }
        }

        if (keep) {
            try filtered.append(file);
            try unique_languages.put(file.language, {});
        }
    }

    if (!options.disable_token_filter) {
        const total_tokens = blk: {
            var sum: usize = 0;
            for (filtered.items) |file| {
                sum += file.token_count;
            }
            break :blk sum;
        };

        if (total_tokens > TotalTokenThreshold) {
            const token_counts = try allocator.alloc(usize, filtered.items.len);
            defer allocator.free(token_counts);

            for (filtered.items, 0..) |file, i| {
                token_counts[i] = file.token_count;
            }

            const average = calculateAverage(token_counts);
            const std_dev = calculateStandardDeviation(token_counts, average);

            var i: usize = 0;
            while (i < filtered.items.len) {
                if (isTokenCountAnomaly(filtered.items[i], average, std_dev)) {
                    const file = filtered.swapRemove(i);
                    try removed_token.append(file);
                } else {
                    i += 1;
                }
            }
        }
    }

    var detected_languages = try allocator.alloc(Language, unique_languages.count());
    var i: usize = 0;
    var it = unique_languages.keyIterator();
    while (it.next()) |lang| {
        detected_languages[i] = lang.*;
        i += 1;
    }

    return FilterResult{
        .filtered_files = try filtered.toOwnedSlice(),
        .removed_files = RemovedFiles{
            .ignored = try removed_ignored.toOwnedSlice(),
            .configuration_files = try removed_config.toOwnedSlice(),
            .token_anomaly = try removed_token.toOwnedSlice(),
        },
        .detected_languages = detected_languages,
    };
}

fn getFileType(file_path: []const u8) FileType {
    const ext = path.extension(file_path);
    if (AdditionalFileType.fromExtension(ext)) |additional| {
        return FileType{ .additional = additional };
    } else {
        return FileType{ .language = Language.fromExtension(ext) };
    }
}

fn calculateAverage(numbers: []const usize) f64 {
    var sum: f64 = 0;
    for (numbers) |num| {
        sum += @floatFromInt(num);
    }
    return sum / @as(f64, @floatFromInt(numbers.len));
}

fn calculateStandardDeviation(numbers: []const usize, average: f64) f64 {
    var sum_squares: f64 = 0;
    for (numbers) |num| {
        const diff = @as(f64, @floatFromInt(num)) - average;
        sum_squares += diff * diff;
    }
    return std.math.sqrt(sum_squares / @as(f64, @floatFromInt(numbers.len)));
}

fn isTokenCountAnomaly(file: FileInfo, average: f64, std_dev: f64) bool {
    const threshold = average + 2 * std_dev;
    return @as(f64, @floatFromInt(file.token_count)) > threshold and file.token_count > TokenAnomalyThreshold;
}
