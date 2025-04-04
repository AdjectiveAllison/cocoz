# Cocoz Neovim Integration

This document outlines potential approaches for integrating cocoz more directly with Neovim to improve the workflow for context gathering.

## Current Challenges

- Path translation between Neovim/Claude Code and web-based LLM calls
- Manual file selection through command line arguments is cumbersome
- Need faster way to gather context from files you're working with

## Potential Integration Approaches

### 1. Neovim Plugin

Create a dedicated Neovim plugin for cocoz that would:

- Allow selecting files directly from Neovim's buffer list
- Support visual selection to pick files in directory structure
- Automatically use paths of currently open buffers for context
- Handle path translation between Neovim and cocoz

Example usage:
```lua
-- Select current buffer
:CocozBuffer

-- Select multiple buffers
:CocozBuffers

-- Select files from visual selection in a directory listing
:'<,'>CocozFiles

-- Generate context with custom format
:CocozBuffer -f ctx
```

### 2. Socket/RPC Interface

Add a JSON-RPC or socket-based API to cocoz that Neovim can communicate with:

- Launch cocoz as a background service
- Send file paths from Neovim to cocoz via socket
- Receive processed context back to Neovim
- Allow dynamic addition/removal of files from context

Implementation options:
- Unix domain sockets for local communication
- TCP sockets for potential remote usage
- JSON-RPC protocol for structured communication

### 3. Special Neovim Output Format

Create a Neovim-specific output format:

- Generate context specifically for use within Neovim
- Optimize for copy/paste into web LLM interfaces
- Include metadata about where files came from
- Support for incremental updates to context

### 4. Path Handling Improvements

Enhance cocoz to better handle relative paths:

- Add path translation functions
- Support for Neovim's working directory conventions
- Smart path resolution relative to project roots
- Integration with Neovim's file path representation

### 5. File Selection Interface

Create a TUI (terminal UI) for file selection:

- Interactive file browser
- Fuzzy finding capabilities
- Save/restore file selection sets
- Integration with Neovim's quickfix lists

## Implementation Plan

1. **Phase 1: Path Handling Improvements**
   - Add relative path support to cocoz
   - Implement path translation functions
   - Ensure correct handling of Neovim-style paths

2. **Phase 2: Basic Neovim Plugin**
   - Simple command to process current buffer
   - Support for multiple buffer selection
   - Basic integration with Neovim commands

3. **Phase 3: Advanced Features**
   - Socket/RPC interface for dynamic communication
   - Custom UI elements for file selection
   - Integration with Neovim's file navigation

## Technical Requirements

- Lua knowledge for Neovim plugin development
- Zig extensions for socket/RPC communication
- Path handling libraries compatible with both systems
- Error handling for different environments

## Next Steps

1. Evaluate which approach best fits the workflow
2. Prototype the path handling improvements
3. Test with sample Neovim configurations
4. Gather feedback from users on most valuable features