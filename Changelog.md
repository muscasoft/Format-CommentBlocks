# Changelog

## [V1.1] - 2026-09-14

### Added
- `-NoBackup` switch: skip the automatic backup. By default, before writing
  changes, the original is copied to `<file>.bak` (overwriting any existing
  backup); pass `-NoBackup` to disable that. Backups are already skipped
  under `-WhatIf`.
- `-Help` switch: prints help without requiring `-Path`.
- Pester test suite (`Format-CommentBlocks.Tests.ps1`) covering the helper
  functions and end-to-end reflow behavior.
- List items (`- `, `* `, `+ `, `1.`, `1)`) are now wrapped independently and
  never merged with the line before or after them.

### Changed
- `Get-LineDiff` now uses Myers' O(ND) diff algorithm instead of an O(n·m)
  LCS table, so cost scales with the number of differences, not file size.
- File reads now use explicit `-Encoding UTF8`, matching the existing write
  encoding (previously the read encoding was left to the host default).
- Diff output (`Show-ReflowDiff`) is now entirely in English (previously
  mixed English/Dutch).

### Fixed
- `Format-CommentBlocks` silently corrupted any file with exactly one line:
  `Get-Content` returns a scalar string (not an array) for single-line
  files, so indexing it with `[$i]` returned individual *characters*
  instead of lines. Now wrapped in `@(...)` to force array context.

### Documented
- The `-----` (five-dash) code-block marker in `Get-WrappedLines`, and how
  it differs from the `---` (three-dash) paragraph-end marker.
- PSScriptAnalyzer findings (`PSUseSingularNouns` on both function names,
  `PSReviewUnusedParameter` on `-Help`) are now explicitly suppressed with
  justifications rather than left as unexplained warnings — both are
  deliberate design choices, not oversights. (The switch-default-value
  finding no longer applies now that the on-by-default backup is expressed
  as `-NoBackup`, which defaults to `$false` like any other switch.)
