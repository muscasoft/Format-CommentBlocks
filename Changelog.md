# Changelog

## [V1.1] - 2026-09-14

### Added
- `-Backup` switch (default on): backs up the original file to `<file>.bak`
  before writing. Disable with `-Backup:$false`. Skipped under `-WhatIf`.
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

### Documented
- The `-----` (five-dash) code-block marker in `Get-WrappedLines`, and how
  it differs from the `---` (three-dash) paragraph-end marker.
  