# Codebase Knowledge System

This document outlines a vision for evolving cocoz into a comprehensive codebase knowledge system that serves both human developers and AI agents through a shared interface.

## Core Vision

Create a unified system that:

1. Manages file collections for context
2. Stores external annotations about code
3. Provides advanced search capabilities
4. Offers consistent interfaces for both humans and AI agents

## System Components

### 1. File Collections & Context Management

Building on the state management system, collections of files can be:
- Saved, named, and categorized
- Tagged with metadata
- Shared between projects
- Organized into sessions or workspaces
- Automatically suggested based on task/history

### 2. External Annotation System

A parallel system of annotations that exist alongside but separate from code:

```json
{
  "annotations": {
    "src/auth/login.js": [
      {
        "id": "anno-123",
        "range": {"start": {"line": 15, "character": 2}, "end": {"line": 25, "character": 10}},
        "content": "This function has a subtle bug with null user objects. They should be checked earlier.",
        "type": "warning",
        "author": "allison",
        "created": "2025-03-20T14:30:00Z",
        "tags": ["bug", "security"],
        "ai_generated": false
      },
      {
        "id": "anno-124",
        "range": {"start": {"line": 30, "character": 0}, "end": {"line": 45, "character": 2}},
        "content": "This authentication flow follows OAuth2 standards with additional custom claims.",
        "type": "info",
        "author": "claude",
        "created": "2025-03-22T09:15:00Z",
        "tags": ["auth", "protocol"],
        "ai_generated": true,
        "confidence": 0.92
      }
    ]
  }
}
```

Annotation types could include:
- **Notes**: General observations or reminders
- **Explanations**: Detailed descriptions of how complex code works
- **Warnings**: Potential issues or edge cases
- **TODOs**: Future work items
- **Links**: Connections to other files/resources
- **Metadata**: Semantic information about the code
- **History**: Context about why certain decisions were made
- **Questions**: Areas that need clarification
- **AI Analysis**: Generated insights about code patterns or behaviors

### 3. Advanced Search Engine

A sophisticated search system combining multiple approaches:

#### Text-Based Search
- Full-text search with code syntax awareness
- Regular expression support
- Filename/path pattern matching
- Symbol search (functions, classes, variables)

#### Vector-Based Search
- Embeddings for code snippets
- Semantic similarity searching
- "Find code like this" functionality
- Natural language queries to find relevant code

#### Metadata & Annotation Search
- Search within annotations
- Filter by annotation author, type, or tags
- Find files with specific metadata attributes
- Temporal search (recently modified, commented on)

#### Hybrid Search
- Combine text, vector, and metadata queries
- Weighted relevance scoring
- Context-aware results (understanding project structure)
- Results grouped by related functionality

### 4. Shared Human-AI Interface

Common access patterns for both humans and AI agents:

#### API Layer
- RESTful or GraphQL API for data access
- WebSocket interface for real-time updates
- Command line interface for scripting
- Neovim integration points

#### Data Structures
- Consistent JSON schemas for collections and annotations
- Strongly typed interfaces in multiple languages
- Versioned schemas for forward compatibility

#### Access Patterns
- CRUD operations for collections and annotations
- Search query interfaces with both simple and advanced modes
- Streaming updates for real-time collaboration
- Batch operations for efficiency

## User Experience Flows

### Developer Workflow Example

1. Open a new codebase and run initial indexing
2. Search for "authentication" functionality
3. Create a collection of relevant files
4. Add annotations explaining key components
5. Share collection with AI assistant
6. AI adds additional annotations and insights
7. Developer searches annotations to understand authentication flow
8. Create new task-based collection for authentication enhancement
9. Add implementation notes as annotations
10. Export context for LLM coding session

### AI Agent Workflow Example

1. Receive collection of files to analyze
2. Add annotations about code structure and patterns
3. Identify related files that should be included
4. Search for similar patterns across codebase
5. Create annotations explaining complex logic
6. Generate collection of files that might need similar changes
7. Add metadata annotations about dependencies and relationships
8. Search annotations from other AI runs to avoid duplicating work
9. Export comprehensive context for generating implementation plan

## Implementation Architecture

### Core Components

```
┌────────────────────────────────┐
│         Shared Storage         │
├────────────────┬───────────────┤
│  Collections   │  Annotations  │
└────────────────┴───────────────┘
          │              │
          ▼              ▼
┌────────────────────────────────┐
│         Search Engine          │
├────────────┬──────────┬────────┤
│ Text Index │ Vectors  │Metadata│
└────────────┴──────────┴────────┘
          │              │
          ▼              ▼
┌────────────────────────────────┐
│           API Layer            │
└────────────────────────────────┘
          │              │
┌─────────┘              └────────┐
▼                                 ▼
┌────────────────┐     ┌───────────────┐
│ Human Interface│     │  AI Interface  │
├────────────────┤     ├───────────────┤
│ CLI  │ Neovim  │     │ API │ Webhooks│
└────────────────┘     └───────────────┘
```

### Storage Options

1. **File-based**: JSON files in `.cocoz` directory
   - Simple, git-friendly
   - Works well for smaller codebases
   - Slower for large-scale search

2. **SQLite**: Embedded database
   - Better performance for larger codebases
   - Single file for portability
   - Support for complex queries

3. **Vector DB**: Specialized for embeddings
   - Efficient semantic search
   - Can be combined with other storage options
   - Examples: FAISS, Chroma, Qdrant

4. **Hybrid**: Combine file-based + SQLite + Vector DB
   - Files for config and collections
   - SQLite for annotations and metadata
   - Vector DB for embeddings and semantic search

### Indexing Pipeline

1. Code parsing and AST generation
2. Text indexing for full-text search
3. Symbol extraction (functions, classes, etc.)
4. Embedding generation for vector search
5. Annotation indexing
6. Relationship mapping between files
7. Metadata extraction and indexing

## Feature Roadmap

### Phase 1: Collection Management
- Basic collection functionality
- Persistent storage of collections
- Neovim integration for collection creation

### Phase 2: Annotation System
- Create, read, update, delete annotations
- Annotation storage and retrieval
- Annotation visualization in Neovim

### Phase 3: Basic Search
- Text-based search across files
- Search within annotations
- Simple filtering and sorting

### Phase 4: Advanced Search
- Vector embeddings for semantic search
- Hybrid search across text and annotations
- Natural language queries

### Phase 5: AI Integration
- API for AI agent access
- Annotation creation by AI agents
- Shared context between human and AI

### Phase 6: Advanced Features
- Automatic collection generation
- Intelligent annotation suggestions
- Codebase insights and visualization

## Technical Challenges

### Search Performance
- Efficient indexing of large codebases
- Balancing search quality and speed
- Incremental updates to search indices

### Annotation Synchronization
- Handling code changes that affect annotations
- Moving annotations when code is refactored
- Merging annotations from multiple sources

### Embedding Quality
- Choosing appropriate embedding models
- Domain-specific fine-tuning for code
- Balancing embedding size and quality

### User Experience
- Making complex functionality accessible
- Balancing CLI, TUI, and GUI interfaces
- Effective visualization of annotations and relationships

## Benefits

### For Human Developers
- Faster codebase comprehension
- Persistent knowledge capture
- Powerful search capabilities
- Better collaboration with AI assistants

### For AI Agents
- Richer context about code
- Storage for analysis and reasoning
- Persistent memory about codebases
- More efficient interaction with developers

## Next Steps

1. Create basic data models for collections and annotations
2. Implement storage layer for persistence
3. Develop simple CLI for managing collections
4. Create Neovim plugin for basic functionality
5. Add annotation creation and visualization
6. Implement text search functionality
7. Explore vector search implementation options