const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

pub fn isGitRepo(directory: []const u8) bool {
    const git_dir_path = std.fmt.allocPrint(
        std.heap.page_allocator,
        "{s}/.git",
        .{directory},
    ) catch return false;
    defer std.heap.page_allocator.free(git_dir_path);

    fs.accessAbsolute(git_dir_path, .{}) catch return false;
    return true;
}

pub fn getRepoName(allocator: Allocator, directory: []const u8) !?[]const u8 {
    // Check if .git directory exists
    if (isGitRepo(directory)) {
        // Extract repo name from directory name
        const dir_basename = fs.path.basename(directory);
        if (dir_basename.len > 0) {
            return try allocator.dupe(u8, dir_basename);
        }
    }

    return null;
}