# cocoz Architecture

This document provides an overview of cocoz's architecture and components.

## High-Level Overview

cocoz is written in Zig and consists of several components that work together to process and analyze code repositories:

```
               ┌────────────────┐
               │      CLI       │
               │   (cli.zig)    │
               └───────┬────────┘
                       │
                       ▼
┌─────────────────────────────────────────┐
│              Main Logic                 │
│             (main.zig)                  │
└──┬───────────────┬──────────────┬───────┘
   │               │              │
   ▼               ▼              ▼
┌─────────┐  ┌───────────┐  ┌──────────┐
│   File  │  │  Output   │  │   Git    │
│ Handler │  │ Formatter │  │ Utilities│
└─────────┘  └───────────┘  └──────────┘
```

## Core Components

### CLI (cli.zig)

The CLI component is responsible for:
- Parsing command-line arguments and options
- Converting user input into internal options
- Handling help text and usage information
- Validating user input

Key data structures:
- `OutputFormat`: Enum for the supported output formats
- `Options`: Structure containing all the parsed command-line options
- `parseArgs()`: Main function for processing arguments

### Main Logic (main.zig)

The main module orchestrates the overall process:
- Initializes the general purpose allocator
- Processes command-line arguments
- Calls the file handler to process targets
- Manages the output process based on the selected format
- Handles error reporting

### File Handler (file_handler.zig)

This component is the core of cocoz, responsible for:
- Traversing directories and processing files
- Filtering files based on various criteria
- Detecting file types and languages
- Respecting .gitignore patterns
- Detecting binary files
- Estimating token counts

Key data structures:
- `FileInfo`: Information about processed files
- `FileType`: Union of language and additional file types
- `Language`: Enum of supported programming languages
- `AdditionalFileType`: Enum of non-programming file types
- `ExcludedFile`: Information about files excluded from processing
- `ProcessOptions`: Configuration for the processing pipeline
- `ProcessResult`: Results of the processing operation

### Output Formatter (output.zig)

Handles the generation of various output formats:
- Overview: Human-readable summary
- XML: Structured XML format
- JSON: Machine-readable JSON format
- Codeblocks: Markdown code blocks with YAML frontmatter
- CTX: Special format optimized for AI context

Key functions:
- `writeXml()`: Generates XML output
- `writeJson()`: Generates JSON output
- `writeCodeblocks()`: Generates markdown code blocks
- `writeCtx()`: Generates the ctx format

### Git Utilities (git.zig)

Simple utilities for Git integration:
- Detecting Git repositories
- Getting repository names

## Processing Flow

1. **Argument Parsing**: CLI options are parsed and validated
2. **Target Selection**: Directories/files specified by the user are identified
3. **File Processing**:
   - Directory traversal (if targets are directories)
   - File reading and content extraction
   - Binary file detection and filtering
   - File type detection
   - Token count estimation
4. **Filtering**:
   - Apply `.gitignore` patterns
   - Apply user-specified ignore patterns
   - Filter by file extensions (if specified)
   - Filter unknown file types (if enabled)
   - Filter configuration files (if enabled)
   - Filter token count anomalies (if enabled)
5. **Output Generation**:
   - Format the results according to the specified output format
   - Write to stdout or analyze for the overview

## File Type Detection

cocoz uses several mechanisms to detect file types:
1. File extension matching for known languages
2. File extension matching for additional file types
3. Filename matching for files without extensions (e.g., "Makefile")
4. Binary file detection using:
   - Magic number detection for common formats
   - Null byte frequency analysis
   - Non-printable character ratio

## Memory Management

cocoz uses Zig's manual memory management with several key patterns:
- General purpose allocator for most allocations
- Careful tracking of ownership with clear deallocation points
- Extensive use of `defer` blocks for cleanup
- Consistent error handling with proper resource cleanup

## Error Handling

The application uses Zig's error handling mechanisms:
- Error union types (`!Type`) for functions that can fail
- Clear error propagation through the call stack
- User-friendly error messages for common issues