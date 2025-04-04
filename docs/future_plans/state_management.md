# Cocoz State Management System

This document outlines an approach for implementing state management in cocoz, allowing users to save, organize, and reuse file selections.

## Core Concepts

### Collections

**Collections** are named groups of files that can be saved and loaded. Examples:

- `auth-system` - Files related to authentication functionality
- `api-endpoints` - Core API endpoint files
- `config-files` - Configuration files across the project
- `current-task` - Files related to what you're currently working on

### Tags

**Tags** are labels that can be applied to individual files or entire collections:

- `#backend`
- `#frontend`
- `#tests`
- `#config`
- `#core`

### Sessions

**Sessions** represent a workspace state, potentially containing multiple collections and temporary selections.

## Storage Format

The state could be stored in a JSON file structure like this:

```json
{
  "collections": {
    "auth-system": {
      "files": [
        {"path": "src/auth/login.js", "tags": ["frontend", "core"]},
        {"path": "src/auth/auth_service.js", "tags": ["backend"]},
        {"path": "src/components/LoginForm.js", "tags": ["frontend", "ui"]}
      ],
      "description": "Authentication system components",
      "last_used": "2025-03-24T15:30:00Z",
      "tags": ["auth", "security"]
    },
    "api-endpoints": {
      "files": [...],
      "description": "Core API endpoints",
      "last_used": "2025-03-23T10:15:00Z",
      "tags": ["api", "backend"]
    }
  },
  "recent_files": [
    {"path": "src/main.js", "last_used": "2025-03-25T09:45:00Z"},
    {"path": "src/config.js", "last_used": "2025-03-25T09:40:00Z"}
  ],
  "current_session": {
    "name": "feature-x-development",
    "collections": ["auth-system", "api-endpoints"],
    "temp_files": [
      {"path": "docs/feature-x.md", "added": "2025-03-25T08:30:00Z"}
    ]
  }
}
```

## Storage Location

- Primary config: `~/.config/cocoz/state.json`
- Project-specific: `.cocoz/state.json` in project root

## Command Line Interface

```bash
# Create a new collection
cocoz collection create auth-system --desc "Authentication system components"

# Add files to a collection
cocoz collection add auth-system src/auth/*.js src/components/LoginForm.js

# Add tags to files in a collection
cocoz collection tag auth-system src/auth/login.js frontend core

# List all collections
cocoz collections list

# Use a collection for context generation
cocoz -c auth-system -f ctx

# Combine multiple collections
cocoz -c auth-system -c api-endpoints -f ctx

# Show collection contents
cocoz collection show auth-system

# Remove files from a collection
cocoz collection remove auth-system src/auth/old_file.js

# Create a session
cocoz session create feature-x-development

# Add collections to a session
cocoz session add feature-x-development auth-system api-endpoints

# Load a session
cocoz session load feature-x-development
```

## Neovim Integration

```lua
-- Create a new collection from open buffers
:CocozCollectionFromBuffers auth-system

-- Add current buffer to collection
:CocozCollectionAddBuffer auth-system

-- Show collection in a floating window
:CocozCollectionShow auth-system

-- Generate context using collection
:CocozContextFromCollection auth-system

-- Interactive collection management
:CocozCollections

-- Quick switch between collections
:CocozCollectionSelect

-- Tag management
:CocozCollectionTag auth-system

-- Session management
:CocozSessions
```

## Implementation Approach

### 1. Core State Management

- Define state data structures in Zig
- Create functions for reading/writing state to disk
- Implement operations for managing collections, tags, and sessions

### 2. CLI Extensions

- Add collection/session subcommands
- Support for filtering and querying state
- Import/export functionality

### 3. Neovim Integration

- Buffer integration for quick file selection
- Interactive UI for collection management
- State visualization (what's selected, in what collections)
- Telescope/fzf integration for fuzzy finding within collections

## Advanced Features

### Automatic Collection Suggestions

- Analyze file access patterns to suggest collections
- Group related files based on imports/references
- Integrate with git commit history to suggest task-based collections

### Collection Sharing

- Export/import collections for team sharing
- Version control friendly formats
- Template collections for common tasks

### Smart Updates

- Auto-update collections when files move/rename
- Track file changes to keep collections current
- Integration with git for tracking file path changes

### Visualization

- Graph visualization of file relationships in collections
- Heatmaps of file usage across collections
- Collection overlap analysis

## User Experience Considerations

1. **Minimal friction** - Adding files to collections should be quick and intuitive
2. **Progressive disclosure** - Basic features easy to use, advanced features available when needed
3. **Discoverability** - Clear commands and UI for finding saved collections
4. **Minimal configuration** - Sensible defaults with easy customization
5. **Feedback** - Clear indication of current state and selection status

## Next Steps

1. Implement core state management functionality
2. Create basic CLI for collection management
3. Develop simple Neovim commands for collection interaction
4. Test with real-world workflow
5. Iterate based on usage patterns