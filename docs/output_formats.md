# cocoz Output Formats

cocoz supports several output formats, each designed for specific use cases.

## Overview Format

The default format provides a human-readable summary of the processing results.

Example:
```
Detected languages: javascript, typescript, python
Detected file types: json, md, yml

Excluded files:
- node_modules/express/package.json (ignored by pattern: node_modules)
- src/large_file.js (token count 15000 exceeds threshold 10000, avg: 2500.00, std_dev: 3000.00)
- img/logo.png (binary file)

Included files after filtering:
- src/main.js (1250 tokens)
- src/utils.js (2100 tokens)
- src/components/Button.tsx (1800 tokens)
- config.json (350 tokens)

Total tokens after filtering: 5500
```

This format is intended for human consumption and provides a quick summary of what was included and excluded.

## XML Format

An XML representation of the processed files and metadata.

Example:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<code-context>
  <metadata>
    <total-files>4</total-files>
    <total-tokens>5500</total-tokens>
    <languages>
      <language>javascript</language>
      <language>typescript</language>
    </languages>
    <file-types>
      <file-type>json</file-type>
    </file-types>
  </metadata>
  <excluded-files>
    <file path="node_modules/express/package.json" tokens="0" lines="0" type="json">
      <reason>ignored by pattern: node_modules</reason>
    </file>
    <!-- More excluded files -->
  </excluded-files>
  <included-files>
    <file path="src/main.js" tokens="1250" lines="120" type="javascript">
      <![CDATA[
      // File content here
      const express = require('express');
      const app = express();
      // Rest of the file...
      ]]>
    </file>
    <!-- More included files -->
  </included-files>
</code-context>
```

The XML format is suitable for:
- Parsing with standard XML tools
- Structured programmatic access
- Integration with systems that expect XML

## JSON Format

A JSON representation of the processed files and metadata.

Example:
```json
{
  "metadata": {
    "totalFiles": 4,
    "totalTokens": 5500,
    "languages": ["javascript", "typescript"],
    "fileTypes": ["json"]
  },
  "excludedFiles": [
    {
      "path": "node_modules/express/package.json",
      "tokens": 0,
      "lines": 0,
      "type": "json",
      "reason": "ignored by pattern: node_modules"
    }
    // More excluded files...
  ],
  "includedFiles": [
    {
      "path": "src/main.js",
      "tokens": 1250,
      "lines": 120,
      "type": "javascript",
      "content": "// File content here\nconst express = require('express');\nconst app = express();\n// Rest of the file..."
    }
    // More included files...
  ]
}
```

The JSON format is suitable for:
- Programmatic consumption
- Web APIs
- Integration with JavaScript/TypeScript applications

## Codeblocks Format

A Markdown format with code blocks and YAML frontmatter.

Example:
```markdown
---
total_files: 4
total_tokens: 5500
languages:
  - javascript
  - typescript
file_types:
  - json

excluded_files:
  - path: node_modules/express/package.json
    tokens: 0
    lines: 0
    type: json
    reason: ignored by pattern: node_modules
---

## src/main.js
```javascript
// File content here
const express = require('express');
const app = express();
// Rest of the file...
```

## src/utils.js
```javascript
// Utility functions
function formatDate(date) {
  // Implementation...
}
// More utilities...
```
```

The Codeblocks format is suitable for:
- Human reading in Markdown viewers
- GitHub comments and documentation
- Embedding in documentation

## CTX Format (Context)

A specialized format optimized for AI context windows.

Example:
```
/// code context ///
|| METADATA
project::my-project
files::4
tokens::5500
languages::javascript,typescript
file_types::json
||

────────────────<< FILE >>────────────────
path::src/main.js
tokens::1250
lines::120
────────────────<< START >>────────────────
// File content here
const express = require('express');
const app = express();
// Rest of the file...
────────────────<< END >>────────────────

────────────────<< FILE >>────────────────
path::src/utils.js
tokens::2100
lines::180
────────────────<< START >>────────────────
// Utility functions
function formatDate(date) {
  // Implementation...
}
// More utilities...
────────────────<< END >>────────────────
```

The CTX format is designed specifically for:
- Efficient use of AI context windows
- Clear delimitation between files
- Easy parsing by AI models
- Including essential metadata
- Optimizing token usage

## Best Practices for Format Selection

- **Overview**: Use when exploring a new codebase
- **XML**: Use for integration with systems expecting XML
- **JSON**: Use for programmatic analysis or web APIs
- **Codeblocks**: Use for sharing in documentation or GitHub issues
- **CTX**: Use for AI interactions like ChatGPT or Claude