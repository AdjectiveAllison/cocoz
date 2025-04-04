# cocoz Usage Guide

cocoz is a powerful tool for analyzing codebases and generating formatted output suitable for AI context windows.

## Installation

### Prerequisites

- Zig 0.14.0 is required

### Building from Source

```bash
git clone https://github.com/AdjectiveAllison/cocoz.git
cd cocoz
zig build install -Doptimize=ReleaseSafe --prefix ~/.local
```

## Basic Usage

The most basic usage is to process the current directory:

```bash
cocoz
```

This will:
1. Scan the current directory for files
2. Apply default filtering (ignoring binary files, respecting `.gitignore`, etc.)
3. Output an overview of the files found

## Command-Line Options

### Specifying Targets

You can specify one or more directories or files to process:

```bash
cocoz src/               # Process the src directory
cocoz file1.js file2.js  # Process specific files
cocoz src/ docs/ tests/  # Process multiple directories
```

### Output Formats

Control the output format with the `-f` or `--format` option:

```bash
cocoz -f overview    # Human-readable summary (default)
cocoz -f xml         # Structured XML output
cocoz -f json        # Machine-readable JSON format
cocoz -f codeblocks  # Markdown-style code blocks with YAML frontmatter
cocoz -f ctx         # Optimized format for AI context with metadata
```

### Filtering Options

#### File Extensions

Limit to specific file extensions:

```bash
cocoz -e zig -e md          # Include only .zig and .md files (multiple flags)
cocoz -e "zig,md"           # Same as above (comma-separated)
cocoz -e ".zig,.md"         # Same as above with leading dots
```

#### Ignore Patterns

Specify patterns to ignore (in addition to `.gitignore`):

```bash
cocoz -i "*.test.js"        # Ignore JavaScript test files
cocoz -i "tests/,docs/"     # Ignore entire directories
cocoz -i "*.tmp,*.log"      # Ignore multiple patterns (comma-separated)
```

#### Dot Files

Include specific dot files (which are excluded by default):

```bash
cocoz --include-dot-files ".env,.gitignore"
```

#### Configuration Files

Enable filtering of configuration files (disabled by default):

```bash
cocoz --enable-config-filter
```

#### Language Filtering

Include files with unknown types (disabled by default):

```bash
cocoz --disable-language-filter
```

#### Token Anomaly Detection

Disable filtering of files with abnormal token counts:

```bash
cocoz --disable-token-filter
```

### Token Limits

Limit the total number of tokens processed:

```bash
cocoz -m 50000  # Limit to 50,000 tokens
```

### Output Control

Send only the formatted output to stdout (useful for piping):

```bash
cocoz --stdout
```

## Advanced Usage

### Working with Explicit Files

When you specify files directly on the command line, they bypass most filtering rules:

```bash
# Process a directory but include a specific file that would otherwise be ignored
cocoz src/ README.md -i "*.md"
```

### Combining Multiple Options

Options can be combined for powerful filtering:

```bash
cocoz src/ \
  -f json \
  -e "js,ts" \
  -i "*.test.js,*.spec.ts" \
  --enable-config-filter \
  -m 100000
```

### Using with AI Tools

For use with AI assistants:

```bash
# Generate context format and copy to clipboard (on Linux)
cocoz -f ctx | xclip -selection clipboard

# Generate XML format to a file
cocoz -f xml > codebase.xml
```

## Troubleshooting

### Common Issues

- **Token Count Too High**: Use `-m` to limit tokens or target specific directories
- **Missing Files**: Check if they're being filtered by `.gitignore` or other ignore patterns
- **Binary Files**: These are automatically excluded; use other tools for binary analysis

### Getting Help

Show the help message:

```bash
cocoz -h
```