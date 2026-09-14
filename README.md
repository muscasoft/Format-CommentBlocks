# Format-CommentBlocks

A PowerShell utility that reflows `#` line comments and reports changes as a
grouped, git-style diff. Block comments (`<# ... #>`) are always left
untouched.

## What it does

- Scans a `.ps1` file line by line.
- **Block comments** (`<# ... #>`) are copied over completely unchanged.
- **Line comments** (`# ...`) are grouped into paragraphs: consecutive
  comment lines are merged into one paragraph until a line ends with a
  period (`.`) or three dashes (`---`), the line is a list item, the next
  line is a list item, or the next line is not a comment.
- **List items** — lines starting with `- `, `* `, `+ `, `1. `, or `1) ` —
  are always wrapped on their own, never merged with the line before or
  after them, even without a trailing period or dashes.
- Each paragraph is re-wrapped (greedy word-wrap) into lines of at most
  `-MaxLength` characters, so long lines are split and short lines are
  padded with words from the following line(s). A "word" ending in five
  dashes (`-----`) marks a block of code and is always kept on the current
  line, even past `-MaxLength` — unrelated to the three-dash (`---`)
  paragraph-end marker above.
- Regular code lines, `#region` / `#endregion` / `#requires` / shebang
  lines, and inline comments after code are left as-is.
- Files are read and written as UTF-8.

## Functions

| Function | Purpose |
|---|---|
| `Format-CommentBlocks` | Main entry point: reads a file, reflows its line comments, optionally shows a diff, and writes the result back (backing up the original by default). |
| `Get-WrappedLines` | Greedy word-wrap helper: packs a list of words into lines of at most `$MaxLength`, each prefixed with `$Prefix`. |
| `Get-LineDiff` | Computes a line-by-line diff between two string arrays using Myers' O(ND) diff algorithm — the same technique classic `diff` tools use. Cost scales with the number of differences between the inputs, not with the size of the files. |
| `Show-ReflowDiff` | Groups the diff into "hunks" (clusters of consecutive changes with surrounding context) and prints them in color, similar to `git diff`. |

## Usage

```powershell
# Preview only — nothing is written to disk
Format-CommentBlocks -Path .\MyScript.ps1 -MaxLength 100 -WhatIf

# Show a diff of what would change, without writing
Format-CommentBlocks -Path .\MyScript.ps1 -MaxLength 100 -ShowDiff -WhatIf

# Show a diff and apply the changes (backs up the original to MyScript.ps1.bak)
Format-CommentBlocks -Path .\MyScript.ps1 -MaxLength 100 -ShowDiff

# Apply without creating a backup
Format-CommentBlocks -Path .\MyScript.ps1 -Backup:$false

# Apply to multiple files via the pipeline
Get-ChildItem -Path .\src -Filter *.ps1 -Recurse |
    Select-Object -ExpandProperty FullName |
    Format-CommentBlocks -MaxLength 100 -ShowDiff

# Show help
Format-CommentBlocks -Help
```

### Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Path` | `string[]` (mandatory, pipeline) | — | One or more `.ps1` file paths to process. |
| `-MaxLength` | `int` | `100` | Maximum line length for reflowed comments. |
| `-ShowDiff` | `switch` | off | Print a grouped diff of the changes before (optionally) writing the file. |
| `-Backup` | `switch` | **on** | Copy the original file to `<file>.bak` before writing (overwrites any existing backup). Pass `-Backup:$false` to disable. Skipped under `-WhatIf`. |
| `-Help` | `switch` | off | Print help and exit, without needing `-Path`. Equivalent to `Get-Help Format-CommentBlocks -Full`. |
| `-WhatIf` | `switch` (from `SupportsShouldProcess`) | off | Preview the operation without writing anything to disk. |
| `-Confirm` | `switch` (from `SupportsShouldProcess`) | off | Prompt for confirmation before writing each file. |

## Testing

`Format-CommentBlocks.Tests.ps1` is a Pester 5 suite covering the helper
functions and the end-to-end behavior above. With both files in the same
folder:

```powershell
Invoke-Pester -Path .\Format-CommentBlocks.Tests.ps1
```

## Notes / limitations

- Only pure `#` comment lines are reflowed — inline comments after code
  (`$x = 1 # note`) are never touched.
- `<# ... #>` blocks (including comment-based help) are always skipped and
  copied verbatim.
- `#region`, `#endregion`, `#requires`, and shebang (`#!`) lines are treated
  as directives, not documentation text, and are left unchanged.
- A list item that spans multiple source lines without repeating its marker
  (e.g. a bullet wrapped onto a second `#` line in the original file) is
  **not** reattached to the bullet — the continuation line is treated as
  its own separate paragraph.
- `-WhatIf` alone only prints the generic "Performing the operation..."
  message; combine it with `-ShowDiff` to actually preview the content
  changes.
- The diff (`Get-LineDiff`) is a plain line diff, not a semantic one — a
  paragraph reflowed from 3 lines into 2 will show as 3 deletions and 2
  insertions, even where the wording overlaps.
  