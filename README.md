# cocoz

A high-performance code context analyzer written in Zig that processes source code repositories and provides detailed analysis of their content.

## Features

- **Multi-Language Support**: Automatically detects and processes a wide variety of programming languages including JavaScript, TypeScript, Python, Java, C/C++, Rust, Go, and many more.
- **Smart Filtering**: 
  - Configuration files included by default
  - Excludes binary files
  - Handles token count anomalies
  - Respects `.gitignore` patterns
  - Explicit files bypass filters (except max tokens)
- **File Type Detection**: Comprehensive support for various file types including source code, documentation, data files, and more
- **Flexible Output Formats**:
  - Overview (default): Human-readable summary
  - XML: Structured XML output
  - JSON: Machine-readable JSON format
  - Codeblocks: Markdown-style code blocks with YAML frontmatter
  - CTX: Optimized format for AI context with metadata
- **Customizable Processing**:
  - Configurable ignore patterns
  - Optional inclusion of dot files
  - Adjustable token filtering
  - Support for multiple input directories/files

## Installation

### Prerequisites

- Zig 0.14.0 (Required)

### Building from Source

1. Clone the repository:
```bash
git clone https://github.com/AdjectiveAllison/cocoz.git
cd cocoz
```

2. Build and install the project:
```bash
zig build install -Doptimize=ReleaseSafe --prefix ~/.local
```

## Usage

```bash
cocoz [options] [directory|file ...]
```

### Arguments

- `directory|file`: Directory or file to process (default: current directory)
  - Multiple directories/files can be specified

### Options

- `-f, --format <format>`: Output format (overview, xml, json, codeblocks, ctx)
- `-e, --extensions <list>`: File extensions to include (comma-separated or multiple flags, with/without leading dot)
- `-i, --ignore <pattern>`: Pattern to ignore (can be used multiple times or comma-separated)
- `-m, --max-tokens <number>`: Maximum number of tokens to process
- `--stdout`: Only output the formatted content
- `--disable-language-filter`: Include files with unknown extensions/types
- `--enable-config-filter`: Enable configuration file filtering (disabled by default)
- `--disable-token-filter`: Disable token count anomaly filtering
- `--include-dot-files <list>`: Comma-separated list of dot files to include
- `-h, --help`: Show help message

### Examples

```bash
# Process current directory
cocoz

# Process specific directory with JSON output
cocoz -f json src/

# Process specific directory with CTX format (optimized for AI context)
cocoz -f ctx src/

# Process multiple files
cocoz file1.c file2.c

# Ignore patterns using multiple flags
cocoz -i "*.rs" -i "*.md" src/

# Ignore patterns using comma-separated list
cocoz -i "*.test.js,node_modules" src/

# Include specific dot files
cocoz --include-dot-files ".env,.gitignore" .

# Exclude configuration files
cocoz --enable-config-filter src/

# Include files with specific extensions using multiple flags
cocoz -e zig -e txt -e md src/

# Include files with specific extensions using comma-separated list
cocoz -e "zig,txt,md" src/

# Mix both styles (flags and comma-separated)
cocoz -e "zig,txt" -e md src/

# Include files with specific extensions (with dots)
cocoz -e ".zig,.txt,.md" src/

# Process directory with ignore patterns, but include specific files regardless of patterns
cocoz README.md src/main.zig docs/ -i "*.md,*.zig"
```

## Token Counting

Currently, the tool uses a simple character-based estimation algorithm with language-specific multipliers to approximate token counts. This is a temporary solution - future versions will integrate [tiktoken-zig](https://github.com/AdjectiveAllison/tiktoken-zig) for more accurate token counting using the same tokenizer as OpenAI's models.

The current multipliers used:
- JavaScript/TypeScript: 0.35 tokens per character
- Python: 0.30 tokens per character
- Java/C#: 0.28 tokens per character
- C/C++/Rust/Go: 0.25 tokens per character
- Zig: 0.24 tokens per character
- Other languages: 0.25 tokens per character

## File Type Detection

cocoz automatically detects and categorizes files into:

- Programming Languages (JavaScript, Python, Java, CUDA, etc.)
- Configuration Files (YAML, TOML, JSON, etc.)
- Documentation (Markdown, MDX, RST, TXT)
- Data Files (CSV, TSV)
- Binary Files (automatically excluded)
- And more...

## Explicit File Handling

When files are specified directly as command-line arguments, they are treated as "explicit" files and bypass most filtering rules:

- Ignore patterns (including `.gitignore`) do not apply to explicit files
- Extension filters are bypassed
- Configuration file filters are bypassed
- Language filters are bypassed
- Token anomaly detection is bypassed

However, the global `--max-tokens` limit still applies to all files, including explicit ones.

This allows you to process specific files regardless of any filtering rules. For example:

```bash
# Process a directory but ignore markdown files, while still including a specific README
cocoz README.md src/ -i "*.md"

# Include specific config files while filtering out configs in directories
cocoz .env.example src/ --enable-config-filter
```

## Binary File Detection

The tool automatically detects and excludes binary files using a sophisticated detection algorithm that analyzes:
- Null byte frequency
- Non-printable character ratio
- File signatures

This ensures that only text-based files are included in the analysis.

## Documentation

Comprehensive documentation is available in the `docs` directory:

- [Usage Guide](docs/usage_guide.md): Detailed instructions for using cocoz
- [Architecture](docs/architecture.md): Overview of cocoz's architecture and components
- [Output Formats](docs/output_formats.md): Details on the available output formats

### Future Plans

We have some ambitious plans for future development in our [Future Plans](docs/future_plans) directory:

- [Codebase Knowledge System](docs/future_plans/codebase_knowledge_system.md): Vision for evolving cocoz into a comprehensive knowledge system
- [Neovim Integration](docs/future_plans/neovim_integration.md): Plans for deeper Neovim editor integration
- [State Management](docs/future_plans/state_management.md): Design for a file collection and session management system

## License

MIT License. See [LICENSE](LICENSE) for details.