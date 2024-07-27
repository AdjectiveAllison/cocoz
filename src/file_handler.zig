const std = @import("std");
const ArrayList = std.ArrayList;
const fs = std.fs;
const path = std.fs.path;
const Allocator = std.mem.Allocator;

pub const FileInfo = struct {
    path: []const u8,
    content: []const u8,
    token_count: usize,
    line_count: usize,
    file_type: FileType,

    pub fn deinit(self: *FileInfo, allocator: Allocator) void {
        allocator.free(self.path);
        allocator.free(self.content);
    }
};

pub const FileType = union(enum) {
    language: Language,
    additional: AdditionalFileType,
    unknown: void,
};

pub const Language = enum {
    javascript,
    typescript,
    html,
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
    shell,

    pub fn fromExtension(ext: []const u8) ?Language {
        const extensions = [_]struct { []const u8, Language }{
            .{ ".js", .javascript }, .{ ".jsx", .javascript }, .{ ".mjs", .javascript },
            .{ ".ts", .typescript }, .{ ".tsx", .typescript }, .{ ".html", .html },
            .{ ".py", .python },     .{ ".pyw", .python },     .{ ".java", .java },
            .{ ".cs", .csharp },     .{ ".cpp", .cpp },        .{ ".cxx", .cpp },
            .{ ".cc", .cpp },        .{ ".c", .cpp },          .{ ".h", .cpp },
            .{ ".hpp", .cpp },       .{ ".php", .php },        .{ ".rb", .ruby },
            .{ ".go", .go },         .{ ".rs", .rust },        .{ ".swift", .swift },
            .{ ".kt", .kotlin },     .{ ".kts", .kotlin },     .{ ".scala", .scala },
            .{ ".zig", .zig },       .{ ".sh", .shell },
        };
        for (extensions) |entry| {
            if (std.mem.eql(u8, ext, entry[0])) {
                return entry[1];
            }
        }
        return null;
    }
};

// TODO: file types we know we aren't supporting but not sure what to do with yet:
// 1. pdf
// 2. mp3
// TODO: add the following file types when ready
// 1. xml
// 2. ico
// 3. csv
// 4. css/scss (Are these languages?)
pub const AdditionalFileType = enum {
    yaml,
    yml,
    toml,
    ini,
    conf,
    json,
    zon,
    cfg,
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
            .yaml, .yml, .toml, .ini, .conf, .json, .zon, .cfg => .config,
            .md, .rst, .txt => .documentation,
            .png, .jpg, .jpeg, .gif, .svg => .image,
        };
    }

    pub fn fromExtension(ext: []const u8) ?AdditionalFileType {
        if (ext.len < 2) {
            return null;
        }
        inline for (std.meta.fields(AdditionalFileType)) |field| {
            if (std.mem.eql(u8, ext[1..], field.name)) {
                return @field(AdditionalFileType, field.name);
            }
        }
        return null;
    }
};

pub const ProcessResult = struct {
    included_files: []FileInfo,
    excluded_files: struct {
        ignored: []FileInfo,
        configuration: []FileInfo,
        token_anomaly: []FileInfo,
    },
    detected_languages: []Language,
    detected_file_types: []AdditionalFileType,
    allocator: Allocator,

    pub fn deinit(self: *ProcessResult) void {
        for (self.included_files) |*file| {
            file.deinit(self.allocator);
        }
        self.allocator.free(self.included_files);

        for (self.excluded_files.ignored) |*file| {
            file.deinit(self.allocator);
        }
        self.allocator.free(self.excluded_files.ignored);

        for (self.excluded_files.configuration) |*file| {
            file.deinit(self.allocator);
        }
        self.allocator.free(self.excluded_files.configuration);

        for (self.excluded_files.token_anomaly) |*file| {
            file.deinit(self.allocator);
        }
        self.allocator.free(self.excluded_files.token_anomaly);

        self.allocator.free(self.detected_languages);
        self.allocator.free(self.detected_file_types);
    }
};

pub const ProcessOptions = struct {
    ignore_patterns: []const []const u8 = &.{
        // Language-specific ignores
        "package-lock.json", "yarn.lock",
        "npm-debug.log",     "*.tsbuildinfo",
        "Pipfile.lock",      "*.pyc",
        "__pycache__",       "*.class",
        "*.jar",             "target/",
        "bin/",              "obj/",
        "*.o",               "*.obj",
        "*.exe",             "*.dll",
        "*.so",              "*.dylib",
        "vendor/",           "composer.lock",
        "Gemfile.lock",      "*.gem",
        "go.sum",            "Cargo.lock",
        "*.swiftmodule",     "*.swiftdoc",
        "*.kotlin_module",   "build/",
        ".zig-cache",        "node_modules",
        // Build files
        "build.zig",         "Makefile",
        "CMakeLists.txt",
    },
    include_dot_files: ?[]const []const u8 = null,
    disable_config_filter: bool = false,
    disable_token_filter: bool = false,
};

const TokenAnomalyThreshold = 10000;
const TotalTokenThreshold = 50000;

const GitIgnorePattern = struct {
    pattern: []const u8,
    is_negation: bool,
    is_directory_only: bool,
    is_anchored: bool,
};

const GitIgnoreContext = struct {
    patterns: []GitIgnorePattern,
    base_path: []const u8,
    pub fn deinit(self: GitIgnoreContext, allocator: std.mem.Allocator) void {
        allocator.free(self.base_path);
        for (self.patterns) |*pattern| {
            allocator.free(pattern.pattern);
        }
    }
};

fn readAndParseGitignore(allocator: Allocator, directory: []const u8) !GitIgnoreContext {
    const gitignore_path = try path.join(allocator, &.{ directory, ".gitignore" });
    defer allocator.free(gitignore_path);

    const file = std.fs.openFileAbsolute(gitignore_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return GitIgnoreContext{
            .patterns = &[_]GitIgnorePattern{},
            .base_path = try allocator.dupe(u8, directory),
        },
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    const patterns = try parseGitIgnoreFile(allocator, content);
    return GitIgnoreContext{
        .patterns = patterns,
        .base_path = try allocator.dupe(u8, directory),
    };
}

fn parseGitIgnoreFile(allocator: Allocator, content: []const u8) ![]GitIgnorePattern {
    var patterns = std.ArrayList(GitIgnorePattern).init(allocator);
    errdefer {
        for (patterns.items) |pattern| {
            allocator.free(pattern.pattern);
        }
        patterns.deinit();
    }

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        var pattern = GitIgnorePattern{
            .pattern = undefined,
            .is_negation = false,
            .is_directory_only = false,
            .is_anchored = false,
        };

        var pattern_slice = trimmed;

        if (pattern_slice[0] == '!') {
            pattern.is_negation = true;
            pattern_slice = pattern_slice[1..];
        }

        if (pattern_slice[pattern_slice.len - 1] == '/') {
            pattern.is_directory_only = true;
            pattern_slice = pattern_slice[0 .. pattern_slice.len - 1];
        }

        if (pattern_slice[0] == '/') {
            pattern.is_anchored = true;
            pattern_slice = pattern_slice[1..];
        }

        pattern.pattern = try allocator.dupe(u8, pattern_slice);
        try patterns.append(pattern);
    }

    return patterns.toOwnedSlice();
}

fn isIgnored(full_path: []const u8, gitignore_stack: []const GitIgnoreContext) bool {
    var ignored = false;
    for (gitignore_stack) |context| {
        // Check if the full_path is within or at the same level as the gitignore context
        if (!std.mem.startsWith(u8, full_path, context.base_path)) continue;

        // Get the path relative to the current gitignore context
        const rel_to_context = full_path[context.base_path.len..];
        const path_to_check = if (rel_to_context.len > 0 and rel_to_context[0] == path.sep) rel_to_context[1..] else rel_to_context;

        for (context.patterns) |pattern| {
            if (matchPattern(path_to_check, pattern)) {
                ignored = !pattern.is_negation;
            }
        }
    }
    return ignored;
}

fn matchPattern(target_path: []const u8, pattern: GitIgnorePattern) bool {
    if (pattern.is_anchored) {
        if (pattern.is_directory_only) {
            // For anchored directory-only patterns, the target path should start with the pattern
            // and either end with a separator or have a separator right after the pattern
            return std.mem.startsWith(u8, target_path, pattern.pattern) and
                (target_path.len == pattern.pattern.len or
                (target_path.len > pattern.pattern.len and target_path[pattern.pattern.len] == path.sep));
        } else {
            // For anchored file patterns, it should match exactly at the start
            return std.mem.startsWith(u8, target_path, pattern.pattern);
        }
    } else {
        // For non-anchored patterns
        if (pattern.is_directory_only) {
            // Check if any component of the path matches the pattern exactly
            var components = std.mem.splitScalar(u8, target_path, path.sep);
            while (components.next()) |component| {
                if (std.mem.eql(u8, component, pattern.pattern)) {
                    return true;
                }
            }
        } else {
            // Check if any component of the path starts with the pattern
            var components = std.mem.splitScalar(u8, target_path, path.sep);
            while (components.next()) |component| {
                if (std.mem.startsWith(u8, component, pattern.pattern)) {
                    return true;
                }
            }
        }
    }
    return false;
}

pub fn getFileList(allocator: Allocator, directory: []const u8) ![]FileInfo {
    var files = ArrayList(FileInfo).init(allocator);
    errdefer files.deinit();

    var gitignore_stack = ArrayList(GitIgnoreContext).init(allocator);
    defer {
        for (gitignore_stack.items) |context| {
            context.deinit(allocator);
        }
        gitignore_stack.deinit();
    }

    // Read the root .gitignore
    const root_gitignore = try readAndParseGitignore(allocator, directory);
    try gitignore_stack.append(root_gitignore);

    var dir = try fs.openDirAbsolute(directory, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    const hard_coded_ignores = [_][]const u8{ ".git", ".svn", ".hg", ".bzr", "CVS" };

    while (try walker.next()) |entry| {
        const full_path = try path.join(allocator, &.{ directory, entry.path });
        defer allocator.free(full_path);

        const rel_path = try path.relative(allocator, directory, full_path);
        defer allocator.free(rel_path);

        // Check if we've moved up in the directory structure
        while (gitignore_stack.items.len > 1) {
            const top_gitignore_dir = path.dirname(gitignore_stack.items[gitignore_stack.items.len - 1].base_path) orelse "";
            if (std.mem.startsWith(u8, entry.path, top_gitignore_dir)) break;

            const popped = gitignore_stack.pop();
            popped.deinit(allocator);
        }

        // Check if this is a new .gitignore file
        if (std.mem.eql(u8, path.basename(entry.path), ".gitignore")) {
            const gitignore_dir = path.dirname(full_path) orelse directory;
            const new_gitignore = try readAndParseGitignore(allocator, gitignore_dir);
            try gitignore_stack.append(new_gitignore);
            continue;
        }

        if (entry.kind != .file) continue;

        // Check hard-coded ignores
        const should_hard_ignore = for (hard_coded_ignores) |ignore| {
            if (std.mem.indexOf(u8, rel_path, ignore) != null) break true;
        } else false;

        if (should_hard_ignore) continue;

        // Check .gitignore patterns
        const should_ignore = isIgnored(full_path, gitignore_stack.items);

        if (should_ignore) continue;

        const content = fs.cwd().readFileAlloc(allocator, full_path, std.math.maxInt(usize)) catch |err| {
            std.debug.print("Error reading file {s}: {}\n", .{ rel_path, err });
            continue;
        };
        errdefer allocator.free(content);

        const file_type = getFileType(full_path);

        // TODO: Detect if an unknown file type is a text file or binary, and potentially add ability to include the file if desired.
        // Also decide if we want to do something with images as well.
        switch (file_type) {
            .unknown => {
                std.debug.print("Skipping over file {s} because we don't know what type it is.\n", .{rel_path});
                allocator.free(content);
                continue;
            },
            .additional => |additional| {
                if (additional.getInfo() == .image) {
                    std.debug.print("Skipping over image file {s}.\n", .{rel_path});
                    allocator.free(content);
                    continue;
                }
            },
            .language => {},
        }

        try files.append(.{
            .path = try allocator.dupe(u8, rel_path),
            .content = content,
            .token_count = estimateTokenCount(content, file_type),
            .line_count = try countLines(content),
            .file_type = file_type,
        });
    }

    return try files.toOwnedSlice();
}

pub fn estimateTokenCount(content: []const u8, file_type: FileType) usize {
    const base_count = switch (file_type) {
        .language => |lang| estimateLanguageTokens(content, lang),
        .additional => |additional| estimateAdditionalTokens(content, additional),
        .unknown => unreachable, // Handle unknown types before this.,
    };
    return base_count;
}

fn estimateLanguageTokens(content: []const u8, language: Language) usize {
    const char_count = content.len;

    return switch (language) {
        .javascript, .typescript => @intFromFloat(@as(f32, @floatFromInt(char_count)) * 0.35),
        .python => @intFromFloat(@as(f32, @floatFromInt(char_count)) * 0.30),
        .java, .csharp => @intFromFloat(@as(f32, @floatFromInt(char_count)) * 0.28),
        .cpp, .rust, .go => @intFromFloat(@as(f32, @floatFromInt(char_count)) * 0.25),
        .zig => @intFromFloat(@as(f32, @floatFromInt(char_count)) * 0.24),
        else => @intFromFloat(@as(f32, @floatFromInt(char_count)) * 0.25),
    };
}

fn estimateAdditionalTokens(content: []const u8, file_type: AdditionalFileType) usize {
    const char_count = content.len;

    return switch (file_type) {
        .yaml, .yml => @intFromFloat(@as(f32, @floatFromInt(char_count)) * 0.27),
        else => @intFromFloat(@as(f32, @floatFromInt(char_count)) * 0.25),
    };
}

pub fn processFiles(allocator: Allocator, files: []FileInfo, options: ProcessOptions) !ProcessResult {
    var included = std.ArrayList(FileInfo).init(allocator);
    var excluded_ignored = std.ArrayList(FileInfo).init(allocator);
    var excluded_config = std.ArrayList(FileInfo).init(allocator);
    var excluded_token = std.ArrayList(FileInfo).init(allocator);
    var unique_languages = std.AutoHashMap(Language, void).init(allocator);
    var unique_file_types = std.AutoHashMap(AdditionalFileType, void).init(allocator);

    defer {
        unique_languages.deinit();
        unique_file_types.deinit();

        for (included.items) |*file| {
            file.deinit(allocator);
        }
        included.deinit();

        for (excluded_ignored.items) |*file| {
            file.deinit(allocator);
        }
        excluded_ignored.deinit();

        for (excluded_config.items) |*file| {
            file.deinit(allocator);
        }
        excluded_config.deinit();

        for (excluded_token.items) |*file| {
            file.deinit(allocator);
        }
        excluded_token.deinit();
    }

    for (files) |file| {
        var keep = true;

        // Check custom ignore patterns
        for (options.ignore_patterns) |pattern| {
            if (std.mem.indexOf(u8, file.path, pattern) != null) {
                try excluded_ignored.append(file);
                keep = false;
                break;
            }
        }

        if (keep and !options.disable_config_filter) {
            switch (file.file_type) {
                .additional => |additional| {
                    if (additional.getInfo() == .config) {
                        try excluded_config.append(file);
                        keep = false;
                    }
                },
                else => {},
            }
        }

        if (keep) {
            try included.append(file);
            switch (file.file_type) {
                .language => |lang| try unique_languages.put(lang, {}),
                .additional => |additional| try unique_file_types.put(additional, {}),
                else => {},
            }
        }
    }

    if (!options.disable_token_filter) {
        const total_tokens = blk: {
            var sum: usize = 0;
            for (included.items) |file| {
                sum += file.token_count;
            }
            break :blk sum;
        };

        if (total_tokens > TotalTokenThreshold) {
            const token_counts = try allocator.alloc(usize, included.items.len);
            defer allocator.free(token_counts);

            for (included.items, 0..) |file, i| {
                token_counts[i] = file.token_count;
            }

            const average = calculateAverage(token_counts);
            const std_dev = calculateStandardDeviation(token_counts, average);

            var i: usize = 0;
            while (i < included.items.len) {
                if (isTokenCountAnomaly(included.items[i], average, std_dev)) {
                    const file = included.swapRemove(i);
                    try excluded_token.append(file);
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

    var detected_file_types = try allocator.alloc(AdditionalFileType, unique_file_types.count());
    var file_i: usize = 0;
    var file_it = unique_file_types.keyIterator();
    while (file_it.next()) |additional| {
        detected_file_types[file_i] = additional.*;
        file_i += 1;
    }

    return ProcessResult{
        .included_files = try included.toOwnedSlice(),
        .excluded_files = .{
            .ignored = try excluded_ignored.toOwnedSlice(),
            .configuration = try excluded_config.toOwnedSlice(),
            .token_anomaly = try excluded_token.toOwnedSlice(),
        },
        .detected_languages = detected_languages,
        .detected_file_types = detected_file_types,
        .allocator = allocator,
    };
}

pub fn processDirectory(allocator: Allocator, directory: []const u8, options: ProcessOptions) !ProcessResult {
    const file_list = try getFileList(allocator, directory);
    defer allocator.free(file_list);
    return processFiles(allocator, file_list, options);
}

fn getFileType(file_path: []const u8) FileType {
    const ext = path.extension(file_path);
    if (Language.fromExtension(ext)) |language| {
        return FileType{ .language = language };
    }

    if (AdditionalFileType.fromExtension(ext)) |additional| {
        return FileType{ .additional = additional };
    }

    return FileType.unknown;
}

fn countLines(content: []const u8) !usize {
    var line_count: usize = 1;
    for (content) |char| {
        if (char == '\n') line_count += 1;
    }
    return line_count;
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
