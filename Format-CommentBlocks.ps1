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
    # Computes a line-by-line diff between $Original and $New using Longest Common Subsequence (LCS) - the same approach
    # used by classic 'diff' tools.
    # Returns an ordered list of Equal/Delete/Insert operations.
    param(
        [string[]]$Original,
        [string[]]$New
    )

    $n = $Original.Count
    $m = $New.Count

    # Build the LCS table (backwards, so we can reconstruct forwards)
    $lcs = New-Object 'int[,]' ($n + 1), ($m + 1)
    for ($i = $n - 1; $i -ge 0; $i--) {
        for ($j = $m - 1; $j -ge 0; $j--) {
            if ($Original[$i] -eq $New[$j]) {
                 $lcs[$i, $j] = $lcs[($i + 1), ($j + 1)] + 1
            }
            else {
                $lcs[$i, $j] = [Math]::Max(($lcs[($i + 1), $j]), ($lcs[$i, ($j + 1)]))
            }
        }
    }

    $result = [System.Collections.Generic.List[object]]::new()
    $i = 0; $j = 0

    while ($i -lt $n -and $j -lt $m) {
        if ($Original[$i] -eq $New[$j]) {
            $result.Add([pscustomobject]@{ Type = 'Equal'; Line = $Original[$i]; OldIndex = $i; NewIndex = $j })
            $i++; $j++
        }
        elseif ($lcs[($i + 1), $j] -ge $lcs[$i, ($j + 1)]) {
            $result.Add([pscustomobject]@{ Type = 'Delete'; Line = $Original[$i]; OldIndex = $i; NewIndex = $null })
            $i++
        }
        else {
            $result.Add([pscustomobject]@{ Type = 'Insert'; Line = $New[$j]; OldIndex = $null; NewIndex = $j })
            $j++
        }
    }
    while ($i -lt $n) {
        $result.Add([pscustomobject]@{ Type = 'Delete'; Line = $Original[$i]; OldIndex = $i; NewIndex = $null })
        $i++
    }
    while ($j -lt $m) {
        $result.Add([pscustomobject]@{ Type = 'Insert'; Line = $New[$j]; OldIndex = $null; NewIndex = $j })
        $j++
    }

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
        Write-Host "(geen wijzigingen)" -ForegroundColor DarkGray
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

        Write-Host "`n@@ regel $($firstOld + 1) / $($firstNew + 1) @@" -ForegroundColor DarkCyan

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
.EXAMPLE
    Format-CommentBlocks -Path .\MyScript.ps1 -MaxLength 100 -ShowDiff -WhatIf
#>
function Format-CommentBlocks {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$Path,

        [int]$MaxLength = 100,

        [switch]$ShowDiff
    )

    process {
        foreach ($file in $Path) {
            $lines  = Get-Content -Path $file
            $output = [System.Collections.Generic.List[string]]::new()

            $linePattern = '^(?<indent>\s*)#(?!region\b|endregion\b|requires\b|!)\s?(?<text>.*)$'

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

                        # Paragraph ends on a period OR on three dashes
                        $endsParagraph = $text.TrimEnd() -match '(\.|---)$'

                        $nextIsPartOfBlock = $false
                        if (($j + 1) -lt $lines.Count -and $lines[$j + 1] -match $linePattern) {
                            if ($Matches.text.Trim().Length -gt 0) {
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
                $output | Set-Content -Path $file -Encoding UTF8
            }
        }
    }
}
