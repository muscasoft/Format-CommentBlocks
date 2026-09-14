function Get-WrappedLines {
    # Shared helper: greedy word-wrap of a list of words into lines of at most $MaxLength, each line starts with $Prefix
    # (indent + optional "# ").
    param(
        [string[]]$Words,
        [string]$Prefix,
        [int]$MaxLength
    )
    $current = $Prefix
    $wrapped = [System.Collections.Generic.List[string]]::new()

    foreach ($word in $Words) {
        if ($current -eq $Prefix) {
            $current += $word
        }
        elseif ($word.EndsWith('-----') -or ($current.Length + 1 + $word.Length) -le $MaxLength) {
            # "-----" (five dashes) marks a block of code and must stay on the current line even if that means exceeding
            # $MaxLength. This is unrelated to "---" (three dashes), which is just the paragraph-end marker used in
            # Format-CommentBlocks.
            $current += " $word"
        }
        else {
            $wrapped.Add($current)
            $current = $Prefix + $word
        }
    }
    if ($current -ne $Prefix) { $wrapped.Add($current) }

    return ,$wrapped   # comma prevents unrolling
}

function Get-LineDiff {
    # Computes a line-by-line diff between $Original and $New using Myers' O(ND) diff algorithm - the same technique
    # classic 'diff' tools use. Cost scales with the number of differences (D) between the inputs, not with
    # $Original.Count * $New.Count, so it stays fast even on large files as long as the two inputs are mostly the same -
    # which holds here, since reflowing comments only changes a handful of lines out of the whole file.
    # Returns an ordered list of Equal/Delete/Insert operations.
    param(
        [string[]]$Original,
        [string[]]$New
    )

    $n    = $Original.Count
    $m    = $New.Count
    $maxD = $n + $m

    # v[offset + k] holds the furthest x reached on diagonal k so far. Diagonals run from -maxD to +maxD, so every index
    # is shifted by $offset to fit a 0-based array. The +2 (rather than +1) leaves one extra slot for the d=0 boundary
    # read, notably when both inputs are empty.
    $offset = $maxD
    $v = New-Object 'int[]' (2 * $maxD + 2)
    $v[$offset + 1] = 0

    # One snapshot of $v per value of $d; needed to walk the trace back into an edit script.
    $trace = [System.Collections.Generic.List[int[]]]::new()

    $foundD = -1
    for ($d = 0; $d -le $maxD; $d++) {
        $trace.Add([int[]]$v.Clone())

        for ($k = -$d; $k -le $d; $k += 2) {
            if ($k -eq -$d) {
                $x = $v[$offset + $k + 1]
            }
            elseif ($k -eq $d) {
                $x = $v[$offset + $k - 1] + 1
            }
            elseif ($v[$offset + $k - 1] -lt $v[$offset + $k + 1]) {
                $x = $v[$offset + $k + 1]
            }
            else {
                $x = $v[$offset + $k - 1] + 1
            }
            $y = $x - $k

            while ($x -lt $n -and $y -lt $m -and $Original[$x] -eq $New[$y]) {
                $x++
                $y++
            }

            $v[$offset + $k] = $x

            if ($x -ge $n -and $y -ge $m) {
                $foundD = $d
                break
            }
        }
        if ($foundD -ge 0) { break }
    }

    # Walk the trace backwards from (n, m) to (0, 0) to recover the actual edit script, then reverse it into forward
    # order.
    $result = [System.Collections.Generic.List[object]]::new()
    $x = $n; $y = $m

    for ($d = $trace.Count - 1; $d -ge 0; $d--) {
        $vPrev = $trace[$d]
        $k = $x - $y

        if ($k -eq -$d) {
            $prevK = $k + 1
        }
        elseif ($k -eq $d) {
            $prevK = $k - 1
        }
        elseif ($vPrev[$offset + $k - 1] -lt $vPrev[$offset + $k + 1]) {
            $prevK = $k + 1
        }
        else {
            $prevK = $k - 1
        }

        $prevX = $vPrev[$offset + $prevK]
        $prevY = $prevX - $prevK

        # Every step along the diagonal is an Equal line.
        while ($x -gt $prevX -and $y -gt $prevY) {
            $x--; $y--
            $result.Add([pscustomobject]@{ Type = 'Equal'; Line = $Original[$x]; OldIndex = $x; NewIndex = $y })
        }

        # The single non-diagonal step (if any) is either an Insert or a Delete.
        if ($d -gt 0) {
            if ($x -eq $prevX) {
                $result.Add([pscustomobject]@{ Type = 'Insert'; Line = $New[$prevY]; OldIndex = $null; NewIndex = $prevY })
            }
            else {
                $result.Add([pscustomobject]@{ Type = 'Delete'; Line = $Original[$prevX]; OldIndex = $prevX; NewIndex = $null })
            }
        }

        $x = $prevX; $y = $prevY
    }

    $result.Reverse()
    return ,$result
}

function Show-ReflowDiff {
    # Groups the diff into "hunks": clusters of consecutive changes, with $Context unchanged lines before and after for
    # orientation (like git diff).
    param(
        [string]$FileName,
        [string[]]$Original,
        [string[]]$New,
        [int]$Context = 2
    )

    $diff = Get-LineDiff -Original $Original -New $New

    # Indices (in $diff) of all non-equal lines
    $changeIdx = [System.Collections.Generic.List[int]]::new()
    for ($k = 0; $k -lt $diff.Count; $k++) {
        if ($diff[$k].Type -ne 'Equal') { $changeIdx.Add($k) }
    }

    Write-Host "`n--- Diff: $FileName ---" -ForegroundColor Cyan

    if ($changeIdx.Count -eq 0) {
        Write-Host "(no changes)" -ForegroundColor DarkGray
        return
    }

    # Form clusters: changes that are less than (2 * Context) lines apart are merged into a single hunk.
    $hunks = [System.Collections.Generic.List[object]]::new()
    $hunkStart = $changeIdx[0]
    $hunkEnd   = $changeIdx[0]

    for ($k = 1; $k -lt $changeIdx.Count; $k++) {
        if (($changeIdx[$k] - $hunkEnd) -le (2 * $Context)) {
            $hunkEnd = $changeIdx[$k]
        }
        else {
            $hunks.Add([pscustomobject]@{ Start = $hunkStart; End = $hunkEnd })
            $hunkStart = $changeIdx[$k]
            $hunkEnd   = $changeIdx[$k]
        }
    }
    $hunks.Add([pscustomobject]@{ Start = $hunkStart; End = $hunkEnd })

    foreach ($hunk in $hunks) {
        $rangeStart = [Math]::Max(0, $hunk.Start - $Context)
        $rangeEnd   = [Math]::Min($diff.Count - 1, $hunk.End + $Context)

        # Line numbers (1-based) for the hunk header, based on surrounding Equal lines
        $firstOld = ($diff[$rangeStart..$rangeEnd] | Where-Object OldIndex -ne $null | Select-Object -First 1).OldIndex
        $firstNew = ($diff[$rangeStart..$rangeEnd] | Where-Object NewIndex -ne $null | Select-Object -First 1).NewIndex

        Write-Host "`n@@ line $($firstOld + 1) / $($firstNew + 1) @@" -ForegroundColor DarkCyan

        foreach ($entry in $diff[$rangeStart..$rangeEnd]) {
            switch ($entry.Type) {
                'Delete' { Write-Host "- $($entry.Line)" -ForegroundColor Red }
                'Insert' { Write-Host "+ $($entry.Line)" -ForegroundColor Green }
                'Equal'  { Write-Host "  $($entry.Line)" -ForegroundColor DarkGray }
            }
        }
    }
}

<#
.SYNOPSIS
    Reflows PowerShell line comments to a maximum line length.
.DESCRIPTION
    Reads one or more .ps1 files and reflows their `#` line comments:
    consecutive comment lines are merged into a paragraph until a line
    ends with a period or three dashes ("---"), then re-wrapped so each
    line uses as much of -MaxLength as possible. Long lines are split
    and short lines are padded with words from the next line(s).
    Comment blocks that open with "<#" are always copied over unchanged.
.PARAMETER Path
    One or more .ps1 file paths to process. Accepts pipeline input.
.PARAMETER MaxLength
    Maximum line length for reflowed comments. Default: 100.
.PARAMETER ShowDiff
    Prints a grouped, git-style diff of the changes before writing.
.PARAMETER Backup
    Before writing changes to a file, copies the original to "<file>.bak"
    (overwriting any existing backup). On by default; pass -Backup:$false to
    disable it. Skipped under -WhatIf, since nothing is written in that case
    either.
.PARAMETER Help
    Shows this help text and exits without processing any files. Same as
    running Get-Help Format-CommentBlocks -Full.
.EXAMPLE
    Format-CommentBlocks -Path .\MyScript.ps1 -MaxLength 100 -ShowDiff -WhatIf
.EXAMPLE
    Format-CommentBlocks -Path .\MyScript.ps1 -Backup:$false
#>
function Format-CommentBlocks {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Run')]
    param(
        [Parameter(ParameterSetName = 'Run', Mandatory, ValueFromPipeline)]
        [string[]]$Path,

        [Parameter(ParameterSetName = 'Run')]
        [int]$MaxLength = 100,

        [Parameter(ParameterSetName = 'Run')]
        [switch]$ShowDiff,

        [Parameter(ParameterSetName = 'Run')]
        [switch]$Backup = $true,

        [Parameter(ParameterSetName = 'Help', Mandatory)]
        [switch]$Help
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Help') {
            Get-Help Format-CommentBlocks -Full
            return
        }

        foreach ($file in $Path) {
            $lines  = Get-Content -Path $file -Encoding UTF8
            $output = [System.Collections.Generic.List[string]]::new()

            $linePattern = '^(?<indent>\s*)#(?!region\b|endregion\b|requires\b|!)\s?(?<text>.*)$'

            # Matches "- ", "* ", "+ ", "1. " or "1) " at the start of a comment's text. Lines like this are list items:
            # they are always wrapped on their own, never merged with a preceding or following line, regardless of
            # trailing punctuation.
            $listItemPattern = '^(?:[-*+]\s|\d+[.\)]\s)'

            $i = 0
            while ($i -lt $lines.Count) {

                # --- Block comment <# ... #> : copied over completely unchanged ---
                if ($lines[$i] -match '^\s*<#') {
                    $blockEndIdx = $i
                    while ($blockEndIdx -lt $lines.Count -and $lines[$blockEndIdx] -notmatch '#>\s*$') {
                        $blockEndIdx++
                    }
                    $output.AddRange([string[]]$lines[$i..$blockEndIdx])
                    $i = $blockEndIdx + 1
                    continue
                }

                # --- Line comment # ... ---
                if ($lines[$i] -match $linePattern -and $Matches.text.Trim().Length -gt 0) {

                    $indent = $Matches.indent
                    $blockTexts = [System.Collections.Generic.List[string]]::new()
                    $j = $i

                    while ($true) {
                        $null = $lines[$j] -match $linePattern
                        $text = $Matches.text
                        $blockTexts.Add($text.Trim())

                        # Paragraph ends on a period, on three dashes, or when the line itself is a list item (list
                        # items always stand alone).
                        $endsParagraph = ($text.Trim() -match $listItemPattern) -or ($text.TrimEnd() -match '(\.|---)$')

                        $nextIsPartOfBlock = $false
                        if (($j + 1) -lt $lines.Count -and $lines[$j + 1] -match $linePattern) {
                            $nextText = $Matches.text.Trim()
                            # A following list item never gets pulled into this paragraph either.
                            if ($nextText.Length -gt 0 -and $nextText -notmatch $listItemPattern) {
                                $nextIsPartOfBlock = $true
                            }
                        }

                        if ($endsParagraph -or -not $nextIsPartOfBlock) {
                            break
                        }
                        $j++
                    }

                    $paragraph = ($blockTexts -join ' ') -replace '\s+', ' '
                    $words     = $paragraph -split ' ' | Where-Object { $_.Length -gt 0 }
                    $prefix    = "$indent# "

                    $output.AddRange([string[]](Get-WrappedLines -Words $words -Prefix $prefix -MaxLength $MaxLength))
                    $i = $j + 1
                    continue
                }

                $output.Add($lines[$i])
                $i++
            }

            if ($ShowDiff) {
                Show-ReflowDiff -FileName $file -Original $lines -New $output
            }

            if ($PSCmdlet.ShouldProcess($file, "Reflow comment blocks (max $MaxLength chars)")) {
                if ($Backup) {
                    Copy-Item -Path $file -Destination "$file.bak" -Force
                }
                $output | Set-Content -Path $file -Encoding UTF8
            }
        }
    }
}
