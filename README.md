# Format-CommentBlocks

A PowerShell utility that reflows `#` line comments and reports changes as a
grouped, git-style diff. Block comments (`<# ... #>`) are always left
untouched.

## What it does

- Scans a `.ps1` file line by line.
- **Block comments** (`<# ... #>`) are copied over completely unchanged.
- **Line comments** (`# ...`) are grouped into paragraphs: consecutive
  comment lines are merged into one paragraph until a line ends with a
  period (`.`) or three dashes (`---`), or the next line is not a comment.
- Each paragraph is re-wrapped (greedy word-wrap) into lines of at most
  `-MaxLength` characters, so long lines are split and short lines are
  padded with words from the following line(s).
- Regular code lines, `#region` / `#endregion` / `#requires` / shebang
  lines, and inline comments after code are left as-is.

## Functions

| Function | Purpose |
|---|---|
| `Format-CommentBlocks` | Main entry point: reads a file, reflows its line comments, optionally shows a diff, and writes the result back. |
| `Get-WrappedLines` | Greedy word-wrap helper: packs a list of words into lines of at most `$MaxLength`, each prefixed with `$Prefix`. |
| `Get-LineDiff` | Computes a line-by-line diff between two string arrays using Longest Common Subsequence (LCS) — the same technique classic `diff` tools use. |
| `Show-ReflowDiff` | Groups the diff into "hunks" (clusters of consecutive changes with surrounding context) and prints them in color, similar to `git diff`. |

## Usage

```powershell
# Preview only — nothing is written to disk
Format-CommentBlocks -Path .\MyScript.ps1 -MaxLength 100 -WhatIf

# Show a diff of what would change, without writing
Format-CommentBlocks -Path .\MyScript.ps1 -MaxLength 100 -ShowDiff -WhatIf

# Show a diff and apply the changes
Format-CommentBlocks -Path .\MyScript.ps1 -MaxLength 100 -ShowDiff

# Apply to multiple files via the pipeline
Get-ChildItem -Path .\src -Filter *.ps1 -Recurse |
    Select-Object -ExpandProperty FullName |
    Format-CommentBlocks -MaxLength 100 -ShowDiff
```

### Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Path` | `string[]` (mandatory, pipeline) | — | One or more `.ps1` file paths to process. |
| `-MaxLength` | `int` | `100` | Maximum line length for reflowed comments. |
| `-ShowDiff` | `switch` | off | Print a grouped diff of the changes before (optionally) writing the file. |
| `-WhatIf` | `switch` (from `SupportsShouldProcess`) | off | Preview the operation without writing anything to disk. |
| `-Confirm` | `switch` (from `SupportsShouldProcess`) | off | Prompt for confirmation before writing each file. |

## Notes / limitations

- Only pure `#` comment lines are reflowed — inline comments after code
  (`$x = 1 # note`) are never touched.
- `<# ... #>` blocks (including comment-based help) are always skipped and
  copied verbatim.
- `#region`, `#endregion`, `#requires`, and shebang (`#!`) lines are treated
  as directives, not documentation text, and are left unchanged.
- `-WhatIf` alone only prints the generic "Performing the operation..."
  message; combine it with `-ShowDiff` to actually preview the content
  changes.
- The diff (`Get-LineDiff`) is a plain LCS diff, not a semantic one — a
  paragraph reflowed from 3 lines into 2 will show as 3 deletions and 2
  insertions, even where the wording overlaps.