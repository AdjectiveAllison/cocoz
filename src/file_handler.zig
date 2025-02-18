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
    c,
    php,
    ruby,
    go,
    rust,
    swift,
    kotlin,
    scala,
    zig,
    shell,
    css,
    scss,
    sql,
    r,
    lua,
    perl,
    haskell,
    elixir,
    dart,
    xml,

    pub fn fromExtension(ext: []const u8) ?Language {
        const extensions = [_]struct { []const u8, Language }{
            .{ ".js", .javascript }, .{ ".jsx", .javascript }, .{ ".mjs", .javascript },
            .{ ".ts", .typescript }, .{ ".tsx", .typescript }, .{ ".html", .html },
            .{ ".py", .python },     .{ ".pyw", .python },     .{ ".java", .java },
            .{ ".cs", .csharp },     .{ ".cpp", .cpp },        .{ ".cxx", .cpp },
            .{ ".cc", .cpp },        .{ ".c", .c },            .{ ".h", .c },
            .{ ".hpp", .cpp },       .{ ".php", .php },        .{ ".rb", .ruby },
            .{ ".go", .go },         .{ ".rs", .rust },        .{ ".swift", .swift },
            .{ ".kt", .kotlin },     .{ ".kts", .kotlin },     .{ ".scala", .scala },
            .{ ".zig", .zig },       .{ ".sh", .shell },       .{ ".bash", .shell },
            .{ ".css", .css },       .{ ".scss", .scss },      .{ ".sql", .sql },
            .{ ".r", .r },           .{ ".lua", .lua },        .{ ".pl", .perl },
            .{ ".pm", .perl },       .{ ".t", .perl },         .{ ".hs", .haskell },
            .{ ".ex", .elixir },     .{ ".exs", .elixir },     .{ ".dart", .dart },
            .{ ".xml", .xml },
        };
        for (extensions) |entry| {
            if (std.ascii.eqlIgnoreCase(ext, entry[0])) {
                return entry[1];
            }
        }
        return null;
    }
};

// TODO: file types we know we aren't supporting but not sure what to do with yet:
// 1. pdf
// 2. mp3
// 3. ttf
// TODO: add the following file types when ready
// 1. xml
// 2. ico
// 3. csv
// 4. css/scss (Are these languages?)
// TODO: What to do with files without extensions?! e.g. LICENSE
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
    csv,
    tsv,
    pdf,
    doc,
    docx,
    xls,
    xlsx,
    ppt,
    pptx,
    // Image types
    png,
    jpg,
    jpeg,
    gif,
    svg,
    ico,
    webp,
    // Audio types
    mp3,
    wav,
    ogg,
    // Font types
    ttf,
    otf,
    woff,
    woff2,
    // Archive types
    zip,
    tar,
    gz,
    bz2,
    // Binary types
    exe,
    dll,
    so,
    dylib,

    pub const FileTypeInfo = union(enum) {
        config: void,
        documentation: void,
        data: void,
        image: void,
        audio: void,
        font: void,
        archive: void,
        binary: void,
    };

    pub fn getInfo(self: AdditionalFileType) FileTypeInfo {
        return switch (self) {
            .yaml, .yml, .toml, .ini, .conf, .json, .zon, .cfg => .config,
            .md, .rst, .txt => .documentation,
            .csv, .tsv => .data,
            .png, .jpg, .jpeg, .gif, .svg, .ico, .webp => .image,
            .mp3, .wav, .ogg => .audio,
            .ttf, .otf, .woff, .woff2 => .font,
            .zip, .tar, .gz, .bz2 => .archive,
            .exe, .dll, .so, .dylib => .binary,
            else => .documentation,
        };
    }

    pub fn fromExtension(ext: []const u8) ?AdditionalFileType {
        if (ext.len < 2) {
            return null;
        }
        inline for (std.meta.fields(AdditionalFileType)) |field| {
            if (std.ascii.eqlIgnoreCase(ext[1..], field.name)) {
                return @field(AdditionalFileType, field.name);
            }
        }
        return null;
    }
};

pub const ExclusionReason = union(enum) {
    ignored: []const u8, // Pattern that caused the ignore
    configuration: void,
    token_anomaly: struct {
        token_count: usize,
        threshold: usize,
        average: f64,
        std_dev: f64,
    },
    binary: void,
};

pub const ExcludedFile = struct {
    file: FileInfo,
    reason: ExclusionReason,

    pub fn deinit(self: *ExcludedFile, allocator: Allocator) void {
        switch (self.reason) {
            .ignored => |pattern| allocator.free(pattern),
            else => {},
        }
        self.file.deinit(allocator);
    }
};

pub const ProcessResult = struct {
    included_files: []FileInfo,
    excluded_files: []ExcludedFile,
    detected_languages: []Language,
    detected_file_types: []AdditionalFileType,
    allocator: Allocator,

    pub fn deinit(self: *ProcessResult) void {
        if (self.included_files.len > 0) {
            for (self.included_files) |*file| {
                file.deinit(self.allocator);
            }
            self.allocator.free(self.included_files);
        }

        if (self.excluded_files.len > 0) {
            for (self.excluded_files) |*excluded| {
                excluded.deinit(self.allocator);
            }
            self.allocator.free(self.excluded_files);
        }

        if (self.detected_languages.len > 0) {
            self.allocator.free(self.detected_languages);
        }

        if (self.detected_file_types.len > 0) {
            self.allocator.free(self.detected_file_types);
        }
    }
};

// Default patterns to ignore
pub const default_ignore_patterns = &[_][]const u8{
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
    "Makefile",          "CMakeLists.txt",
};

pub const ProcessOptions = struct {
    ignore_patterns: []const []const u8 = default_ignore_patterns,
    include_dot_files: ?[]const []const u8 = null,
    disable_config_filter: bool = true,
    disable_token_filter: bool = false,
    disable_language_filter: bool = false,
    extensions: ?[]const []const u8 = null,
    max_tokens: ?usize = null,
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
        allocator.free(self.patterns);
    }
};

const BinaryDetectionConfig = struct {
    sample_size: usize = 8192, // Check first 8KB
    null_byte_threshold: f32 = 0.1, // 10% null bytes indicates binary
    non_printable_threshold: f32 = 0.3, // 30% non-printable chars indicates binary
};

const MagicNumber = struct {
    signature: []const u8,
    offset: usize = 0,
};

const magic_numbers = [_]MagicNumber{
    // Images
    .{ .signature = "\x89PNG\x0D\x0A\x1A\x0A" }, // PNG
    .{ .signature = "GIF87a" }, // GIF
    .{ .signature = "GIF89a" }, // GIF
    .{ .signature = "\xFF\xD8\xFF" }, // JPEG
    // Archives
    .{ .signature = "PK\x03\x04" }, // ZIP
    .{ .signature = "\x1F\x8B\x08" }, // GZIP
    // Executables
    .{ .signature = "MZ" }, // DOS/PE
    .{ .signature = "\x7FELF" }, // ELF
    // PDFs
    .{ .signature = "%PDF-" },
};

fn isBinaryContent(content: []const u8, config: BinaryDetectionConfig) bool {
    // First check magic numbers
    for (magic_numbers) |magic| {
        if (content.len >= magic.offset + magic.signature.len) {
            const slice = content[magic.offset .. magic.offset + magic.signature.len];
            if (std.mem.eql(u8, slice, magic.signature)) {
                return true;
            }
        }
    }

    // Then check for binary content patterns
    const sample_size = @min(content.len, config.sample_size);
    if (sample_size == 0) return false;

    var null_bytes: usize = 0;
    var non_printable: usize = 0;

    for (content[0..sample_size]) |byte| {
        if (byte == 0) {
            null_bytes += 1;
        } else if ((byte < 32 and byte != '\n' and byte != '\r' and byte != '\t') or byte == 127) {
            non_printable += 1;
        }
    }

    const null_ratio = @as(f32, @floatFromInt(null_bytes)) / @as(f32, @floatFromInt(sample_size));
    const non_printable_ratio = @as(f32, @floatFromInt(non_printable)) / @as(f32, @floatFromInt(sample_size));

    return null_ratio > config.null_byte_threshold or non_printable_ratio > config.non_printable_threshold;
}

fn readAndParseGitignore(allocator: Allocator, directory: []const u8) !GitIgnoreContext {
    // First check if the directory exists and is a directory
    const stat = fs.cwd().statFile(directory) catch |err| switch (err) {
        error.FileNotFound => return GitIgnoreContext{
            .patterns = &[_]GitIgnorePattern{},
            .base_path = try allocator.dupe(u8, directory),
        },
        else => return err,
    };

    if (stat.kind != .directory) {
        return GitIgnoreContext{
            .patterns = &[_]GitIgnorePattern{},
            .base_path = try allocator.dupe(u8, directory),
        };
    }

    const gitignore_path = try path.join(allocator, &.{ directory, ".gitignore" });
    defer allocator.free(gitignore_path);

    const file = fs.cwd().openFile(gitignore_path, .{}) catch |err| switch (err) {
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

pub fn processTarget(allocator: Allocator, target_path: []const u8, options: ProcessOptions) !ProcessResult {
    var files = std.ArrayList(FileInfo).init(allocator);
    errdefer {
        for (files.items) |*file| {
            file.deinit(allocator);
        }
        files.deinit();
    }

    var excluded = std.ArrayList(ExcludedFile).init(allocator);
    errdefer {
        for (excluded.items) |*file| {
            file.deinit(allocator);
        }
        excluded.deinit();
    }

    var unique_languages = std.AutoHashMap(Language, void).init(allocator);
    defer unique_languages.deinit();

    var unique_file_types = std.AutoHashMap(AdditionalFileType, void).init(allocator);
    defer unique_file_types.deinit();

    const stat = try fs.cwd().statFile(target_path);
    if (stat.kind == .file) {
        const content = try fs.cwd().readFileAlloc(allocator, target_path, std.math.maxInt(usize));
        errdefer allocator.free(content);

        // Check if file is binary
        if (isBinaryContent(content, .{})) {
            std.debug.print("Skipping binary file: {s}\n", .{target_path});
            allocator.free(content);

            const empty_file = try createEmptyFileInfo(allocator, target_path, .unknown);
            try excluded.append(.{
                .file = empty_file,
                .reason = .binary,
            });

            return ProcessResult{
                .included_files = try files.toOwnedSlice(),
                .excluded_files = try excluded.toOwnedSlice(),
                .detected_languages = &[_]Language{},
                .detected_file_types = &[_]AdditionalFileType{},
                .allocator = allocator,
            };
        }

        const file_type = getFileType(target_path);

        // Skip unknown and image files
        switch (file_type) {
            .unknown => {
                std.debug.print("Skipping over file {s} because we don't know what type it is.\n", .{target_path});
                allocator.free(content);

                const empty_file = try createEmptyFileInfo(allocator, target_path, .unknown);
                try excluded.append(.{
                    .file = empty_file,
                    .reason = .binary,
                });

                return ProcessResult{
                    .included_files = try files.toOwnedSlice(),
                    .excluded_files = try excluded.toOwnedSlice(),
                    .detected_languages = &[_]Language{},
                    .detected_file_types = &[_]AdditionalFileType{},
                    .allocator = allocator,
                };
            },
            .additional => |additional| {
                if (additional.getInfo() == .image) {
                    std.debug.print("Skipping over image file {s}.\n", .{target_path});
                    allocator.free(content);

                    const empty_file = try createEmptyFileInfo(allocator, target_path, file_type);
                    try excluded.append(.{
                        .file = empty_file,
                        .reason = .binary,
                    });

                    return ProcessResult{
                        .included_files = try files.toOwnedSlice(),
                        .excluded_files = try excluded.toOwnedSlice(),
                        .detected_languages = &[_]Language{},
                        .detected_file_types = &[_]AdditionalFileType{},
                        .allocator = allocator,
                    };
                }
                try unique_file_types.put(additional, {});
            },
            .language => |lang| {
                try unique_languages.put(lang, {});
            },
        }

        // Check ignore patterns
        for (options.ignore_patterns) |pattern| {
            if (isPathIgnored(target_path, pattern)) {
                const duped_pattern = try allocator.dupe(u8, pattern);
                errdefer allocator.free(duped_pattern);
                const empty_file = try createEmptyFileInfo(allocator, target_path, .unknown);
                errdefer allocator.free(empty_file.path);
                allocator.free(content);

                try excluded.append(.{
                    .file = empty_file,
                    .reason = .{ .ignored = duped_pattern },
                });

                return ProcessResult{
                    .included_files = try files.toOwnedSlice(),
                    .excluded_files = try excluded.toOwnedSlice(),
                    .detected_languages = &[_]Language{},
                    .detected_file_types = &[_]AdditionalFileType{},
                    .allocator = allocator,
                };
            }
        }

        // Create file info with content
        const duped_path = try allocator.dupe(u8, target_path);
        errdefer allocator.free(duped_path);
        const duped_content = try allocator.dupe(u8, content);
        errdefer allocator.free(duped_content);
        allocator.free(content);

        try files.append(.{
            .path = duped_path,
            .content = duped_content,
            .token_count = estimateTokenCount(duped_content, file_type),
            .line_count = try countLines(duped_content),
            .file_type = file_type,
        });
    } else {
        // Process directory
        var gitignore_stack = ArrayList(GitIgnoreContext).init(allocator);
        defer {
            for (gitignore_stack.items) |context| {
                context.deinit(allocator);
            }
            gitignore_stack.deinit();
        }

        // Read the root .gitignore
        const root_gitignore = try readAndParseGitignore(allocator, target_path);
        try gitignore_stack.append(root_gitignore);

        var dir = try fs.cwd().openDir(target_path, .{ .iterate = true });
        defer dir.close();

        var walker = try dir.walk(allocator);
        defer walker.deinit();

        const hard_coded_ignores = [_][]const u8{ ".git", ".svn", ".hg", ".bzr", "CVS" };

        while (try walker.next()) |entry| {
            const full_path = try path.join(allocator, &.{ target_path, entry.path });
            defer allocator.free(full_path);

            const rel_path = try path.relative(allocator, target_path, full_path);
            defer allocator.free(rel_path);

            const basename = path.basename(entry.path);

            // Check hard-coded ignores first for all files/directories
            const should_hard_ignore = for (hard_coded_ignores) |ignore| {
                if (std.mem.indexOf(u8, rel_path, ignore) != null) break true;
            } else false;

            if (should_hard_ignore) continue;

            // Handle dot files
            if (basename.len > 0 and basename[0] == '.') {
                // Skip dot files unless explicitly included
                if (options.include_dot_files) |dot_files| {
                    const should_include = for (dot_files) |pattern| {
                        if (std.mem.eql(u8, basename, pattern)) break true;
                    } else false;
                    if (!should_include) continue;
                } else {
                    continue;
                }
            }

            // Check if we've moved up in the directory structure
            while (gitignore_stack.items.len > 1) {
                const top_gitignore_dir = path.dirname(gitignore_stack.items[gitignore_stack.items.len - 1].base_path) orelse "";
                if (std.mem.startsWith(u8, entry.path, top_gitignore_dir)) break;

                const popped = gitignore_stack.pop();
                popped.deinit(allocator);
            }

            // Check if this is a new .gitignore file
            if (std.mem.eql(u8, basename, ".gitignore")) {
                const gitignore_dir = path.dirname(full_path) orelse target_path;
                const new_gitignore = try readAndParseGitignore(allocator, gitignore_dir);
                try gitignore_stack.append(new_gitignore);
                continue;
            }

            if (entry.kind != .file) continue;

            // Check .gitignore patterns
            const should_ignore = isIgnored(full_path, gitignore_stack.items);

            if (should_ignore) continue;

            // Check custom ignore patterns
            const should_custom_ignore = for (options.ignore_patterns) |pattern| {
                if (isPathIgnored(rel_path, pattern)) break true;
            } else false;

            if (should_custom_ignore) continue;

            const content = fs.cwd().readFileAlloc(allocator, full_path, std.math.maxInt(usize)) catch |err| {
                std.debug.print("Error reading file {s}: {}\n", .{ rel_path, err });
                continue;
            };
            errdefer allocator.free(content);

            // Check if file is binary
            if (isBinaryContent(content, .{})) {
                std.debug.print("Skipping binary file: {s}\n", .{rel_path});
                allocator.free(content);

                const empty_file = try createEmptyFileInfo(allocator, rel_path, .unknown);
                try excluded.append(.{
                    .file = empty_file,
                    .reason = .binary,
                });

                continue;
            }

            const file_type = getFileType(full_path);

            // Skip unknown and image files
            switch (file_type) {
                .unknown => {
                    std.debug.print("Skipping over file {s} because we don't know what type it is.\n", .{rel_path});
                    allocator.free(content);

                    const empty_file = try createEmptyFileInfo(allocator, rel_path, .unknown);
                    try excluded.append(.{
                        .file = empty_file,
                        .reason = .binary,
                    });

                    continue;
                },
                .additional => |additional| {
                    if (additional.getInfo() == .image) {
                        std.debug.print("Skipping over image file {s}.\n", .{rel_path});
                        allocator.free(content);

                        const empty_file = try createEmptyFileInfo(allocator, rel_path, file_type);
                        try excluded.append(.{
                            .file = empty_file,
                            .reason = .binary,
                        });

                        continue;
                    }
                    try unique_file_types.put(additional, {});
                },
                .language => |lang| {
                    try unique_languages.put(lang, {});
                },
            }

            // Create file info with content
            const duped_path = try allocator.dupe(u8, rel_path);
            errdefer allocator.free(duped_path);
            const duped_content = try allocator.dupe(u8, content);
            errdefer allocator.free(duped_content);
            allocator.free(content);

            try files.append(.{
                .path = duped_path,
                .content = duped_content,
                .token_count = estimateTokenCount(duped_content, file_type),
                .line_count = try countLines(duped_content),
                .file_type = file_type,
            });
        }
    }

    var detected_languages = try allocator.alloc(Language, unique_languages.count());
    errdefer allocator.free(detected_languages);
    var i: usize = 0;
    var it = unique_languages.keyIterator();
    while (it.next()) |lang| {
        detected_languages[i] = lang.*;
        i += 1;
    }

    var detected_file_types = try allocator.alloc(AdditionalFileType, unique_file_types.count());
    errdefer allocator.free(detected_file_types);
    var file_i: usize = 0;
    var file_it = unique_file_types.keyIterator();
    while (file_it.next()) |additional| {
        detected_file_types[file_i] = additional.*;
        file_i += 1;
    }

    const files_slice = try files.toOwnedSlice();
    errdefer {
        for (files_slice) |*file| {
            file.deinit(allocator);
        }
        allocator.free(files_slice);
    }

    const excluded_slice = try excluded.toOwnedSlice();
    errdefer {
        for (excluded_slice) |*file| {
            file.deinit(allocator);
        }
        allocator.free(excluded_slice);
    }

    // Process files with filtering
    var result = try processFiles(allocator, files_slice, options);
    errdefer result.deinit();

    // Update the detected languages and file types
    allocator.free(result.detected_languages);
    allocator.free(result.detected_file_types);
    result.detected_languages = detected_languages;
    result.detected_file_types = detected_file_types;

    // Add excluded files to result
    var all_excluded = std.ArrayList(ExcludedFile).init(allocator);
    errdefer {
        for (all_excluded.items) |*file| {
            file.deinit(allocator);
        }
        all_excluded.deinit();
    }

    // Add excluded files from processFiles
    for (result.excluded_files) |file| {
        try all_excluded.append(file);
    }
    allocator.free(result.excluded_files);

    // Add excluded files from processTarget
    for (excluded_slice) |file| {
        try all_excluded.append(file);
    }
    allocator.free(excluded_slice);

    result.excluded_files = try all_excluded.toOwnedSlice();
    return result;
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
        .cpp, .c, .rust, .go => @intFromFloat(@as(f32, @floatFromInt(char_count)) * 0.25),
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
    var excluded = std.ArrayList(ExcludedFile).init(allocator);
    var unique_languages = std.AutoHashMap(Language, void).init(allocator);
    var unique_file_types = std.AutoHashMap(AdditionalFileType, void).init(allocator);
    var total_tokens: usize = 0;

    defer {
        unique_languages.deinit();
        unique_file_types.deinit();
    }

    errdefer {
        for (included.items) |*file| {
            file.deinit(allocator);
        }
        included.deinit();

        for (excluded.items) |*file| {
            file.deinit(allocator);
        }
        excluded.deinit();
    }

    for (files) |file| {
        var keep = true;
        var exclusion_reason: ?ExclusionReason = null;

        // Check if we've hit the max tokens limit
        if (options.max_tokens) |max_tokens| {
            if (total_tokens + file.token_count > max_tokens) {
                break; // Stop processing more files
            }
        }

        // Check custom ignore patterns
        for (options.ignore_patterns) |pattern| {
            if (isPathIgnored(file.path, pattern)) {
                const duped_pattern = try allocator.dupe(u8, pattern);
                errdefer allocator.free(duped_pattern);
                exclusion_reason = ExclusionReason{ .ignored = duped_pattern };
                keep = false;
                break;
            }
        }

        // Check file extensions if specified
        if (keep and options.extensions != null) {
            const file_ext = std.fs.path.extension(file.path);
            var ext_match = false;
            for (options.extensions.?) |allowed_ext| {
                const normalized_ext = try normalizeExtension(allocator, allowed_ext);
                defer allocator.free(normalized_ext);
                if (std.ascii.eqlIgnoreCase(file_ext, normalized_ext)) {
                    ext_match = true;
                    break;
                }
            }
            if (!ext_match) {
                const duped_pattern = try allocator.dupe(u8, "extension not allowed");
                errdefer allocator.free(duped_pattern);
                exclusion_reason = ExclusionReason{ .ignored = duped_pattern };
                keep = false;
            }
        }

        // Handle unknown file types based on disable_language_filter
        if (keep and file.file_type == .unknown and !options.disable_language_filter) {
            const duped_pattern = try allocator.dupe(u8, "unknown file type");
            errdefer allocator.free(duped_pattern);
            exclusion_reason = ExclusionReason{ .ignored = duped_pattern };
            keep = false;
        }

        if (keep and !options.disable_config_filter) {
            switch (file.file_type) {
                .additional => |additional| {
                    if (additional.getInfo() == .config) {
                        exclusion_reason = .configuration;
                        keep = false;
                    }
                },
                else => {},
            }
        }

        if (keep) {
            const duped_file = try dupeFileInfo(allocator, file);
            try included.append(duped_file);
            total_tokens += file.token_count;

            switch (file.file_type) {
                .language => |lang| try unique_languages.put(lang, {}),
                .additional => |additional| try unique_file_types.put(additional, {}),
                else => {},
            }
        } else if (exclusion_reason) |reason| {
            const duped_file = try dupeFileInfo(allocator, file);
            try excluded.append(.{
                .file = duped_file,
                .reason = reason,
            });
        }
    }

    // Free the input files since we've duplicated them
    for (files) |*file| {
        file.deinit(allocator);
    }
    allocator.free(files);

    if (!options.disable_token_filter) {
        if (total_tokens > TotalTokenThreshold) {
            const token_counts = try allocator.alloc(usize, included.items.len);
            defer allocator.free(token_counts);

            for (included.items, 0..) |file, i| {
                token_counts[i] = file.token_count;
            }

            const average = calculateAverage(token_counts);
            const std_dev = calculateStandardDeviation(token_counts, average);
            const threshold = @as(usize, @intFromFloat(average + 2 * std_dev));

            var i: usize = 0;
            while (i < included.items.len) {
                const file = included.items[i];
                if (file.token_count > threshold and file.token_count > TokenAnomalyThreshold) {
                    const swapped = included.swapRemove(i);
                    try excluded.append(.{
                        .file = swapped,
                        .reason = .{
                            .token_anomaly = .{
                                .token_count = file.token_count,
                                .threshold = threshold,
                                .average = average,
                                .std_dev = std_dev,
                            },
                        },
                    });
                } else {
                    i += 1;
                }
            }
        }
    }

    var detected_languages = try allocator.alloc(Language, unique_languages.count());
    errdefer allocator.free(detected_languages);
    var i: usize = 0;
    var it = unique_languages.keyIterator();
    while (it.next()) |lang| {
        detected_languages[i] = lang.*;
        i += 1;
    }

    var detected_file_types = try allocator.alloc(AdditionalFileType, unique_file_types.count());
    errdefer allocator.free(detected_file_types);
    var file_i: usize = 0;
    var file_it = unique_file_types.keyIterator();
    while (file_it.next()) |additional| {
        detected_file_types[file_i] = additional.*;
        file_i += 1;
    }

    return ProcessResult{
        .included_files = try included.toOwnedSlice(),
        .excluded_files = try excluded.toOwnedSlice(),
        .detected_languages = detected_languages,
        .detected_file_types = detected_file_types,
        .allocator = allocator,
    };
}

pub fn processDirectory(allocator: Allocator, directory: []const u8, options: ProcessOptions) !ProcessResult {
    return processTarget(allocator, directory, options);
}

fn getFileType(file_path: []const u8) FileType {
    const ext = path.extension(file_path);
    if (Language.fromExtension(ext)) |language| {
        return FileType{ .language = language };
    }

    if (AdditionalFileType.fromExtension(ext)) |additional| {
        return FileType{ .additional = additional };
    }

    // Handle files without extensions
    const basename = path.basename(file_path);
    const extensionless_files = [_]struct { []const u8, FileType }{
        .{ "Makefile", .{ .language = .shell } },
        .{ "makefile", .{ .language = .shell } },
        .{ "Dockerfile", .{ .language = .shell } },
        .{ "Jenkinsfile", .{ .language = .shell } },
        .{ "LICENSE", .{ .additional = .txt } },
        .{ "README", .{ .additional = .txt } },
        .{ "CHANGELOG", .{ .additional = .txt } },
        .{ "CONTRIBUTING", .{ .additional = .txt } },
        .{ "AUTHORS", .{ .additional = .txt } },
        .{ "CODEOWNERS", .{ .additional = .txt } },
        .{ ".gitignore", .{ .additional = .conf } },
        .{ ".gitattributes", .{ .additional = .conf } },
        .{ ".editorconfig", .{ .additional = .conf } },
        .{ ".env", .{ .additional = .conf } },
    };

    for (extensionless_files) |entry| {
        if (std.mem.eql(u8, basename, entry[0])) {
            return entry[1];
        }
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
    if (numbers.len <= 1) return 0;
    var sum_squares: f64 = 0;
    for (numbers) |num| {
        const diff = @as(f64, @floatFromInt(num)) - average;
        sum_squares += diff * diff;
    }
    return std.math.sqrt(sum_squares / @as(f64, @floatFromInt(numbers.len - 1)));
}

fn dupeFileInfo(allocator: Allocator, file: FileInfo) !FileInfo {
    const duped_path = try allocator.dupe(u8, file.path);
    errdefer allocator.free(duped_path);
    const duped_content = try allocator.dupe(u8, file.content);
    errdefer allocator.free(duped_content);

    return FileInfo{
        .path = duped_path,
        .content = duped_content,
        .token_count = file.token_count,
        .line_count = file.line_count,
        .file_type = file.file_type,
    };
}

fn createEmptyFileInfo(allocator: Allocator, file_path: []const u8, file_type: FileType) !FileInfo {
    const duped_path = try allocator.dupe(u8, file_path);
    errdefer allocator.free(duped_path);
    const duped_content = try allocator.dupe(u8, "");
    errdefer allocator.free(duped_content);

    return FileInfo{
        .path = duped_path,
        .content = duped_content,
        .token_count = 0,
        .line_count = 0,
        .file_type = file_type,
    };
}

fn isPathIgnored(file_path: []const u8, pattern: []const u8) bool {
    // Split path into components
    const path_components = std.mem.splitScalar(u8, file_path, path.sep);
    var pattern_components = std.mem.splitScalar(u8, pattern, path.sep);

    // If pattern starts with '/', it must match from the root
    const is_anchored = pattern.len > 0 and pattern[0] == path.sep;
    if (is_anchored) {
        _ = pattern_components.next(); // Skip empty component from leading '/'
    }

    // Get all pattern components
    var pattern_parts = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer pattern_parts.deinit();
    while (pattern_components.next()) |comp| {
        pattern_parts.append(comp) catch return false;
    }

    // If pattern ends with '/', it must match a directory
    const requires_dir = pattern.len > 0 and pattern[pattern.len - 1] == path.sep;
    if (requires_dir) {
        _ = pattern_parts.pop();
    }

    // For anchored patterns, we must match all components
    if (is_anchored) {
        var path_iter = path_components;
        for (pattern_parts.items) |pattern_part| {
            const path_part = path_iter.next() orelse return false;
            if (!matchesPattern(path_part, pattern_part)) {
                return false;
            }
        }
        // If we matched all pattern parts, we're good (unless requires_dir)
        return !requires_dir or path_iter.next() != null;
    }

    // For unanchored patterns, try matching at each path component
    var matched_components: usize = 0;
    var path_iter = path_components;
    while (path_iter.next()) |path_part| {
        if (matched_components == 0 and matchesPattern(path_part, pattern_parts.items[0])) {
            matched_components = 1;
            if (pattern_parts.items.len == 1) {
                return !requires_dir or path_iter.next() != null;
            }
        } else if (matched_components > 0) {
            if (matched_components < pattern_parts.items.len and
                matchesPattern(path_part, pattern_parts.items[matched_components]))
            {
                matched_components += 1;
                if (matched_components == pattern_parts.items.len) {
                    return !requires_dir or path_iter.next() != null;
                }
            } else {
                matched_components = 0;
            }
        }
    }

    return false;
}

fn matchesPattern(path_component: []const u8, pattern: []const u8) bool {
    // Handle wildcards
    if (std.mem.eql(u8, pattern, "*")) return true;
    if (std.mem.startsWith(u8, pattern, "*") and std.mem.endsWith(u8, pattern, "*")) {
        const inner = pattern[1 .. pattern.len - 1];
        return std.mem.indexOf(u8, path_component, inner) != null;
    }
    if (std.mem.startsWith(u8, pattern, "*")) {
        const suffix = pattern[1..];
        return std.mem.endsWith(u8, path_component, suffix);
    }
    if (std.mem.endsWith(u8, pattern, "*")) {
        const prefix = pattern[0 .. pattern.len - 1];
        return std.mem.startsWith(u8, path_component, prefix);
    }
    return std.mem.eql(u8, path_component, pattern);
}

fn normalizeExtension(allocator: Allocator, ext: []const u8) ![]const u8 {
    if (ext.len == 0) return allocator.dupe(u8, "");
    if (ext[0] == '.') return allocator.dupe(u8, ext);
    return std.fmt.allocPrint(allocator, ".{s}", .{ext});
}
