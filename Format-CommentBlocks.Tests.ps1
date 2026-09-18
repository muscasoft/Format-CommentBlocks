<#
.SYNOPSIS
    Pester tests for Format-CommentBlocks.ps1.
.DESCRIPTION
    Covers the pure helper functions (Get-WrappedLines, Get-LineDiff) directly, and exercises
    Format-CommentBlocks itself against temp files for paragraph/list/region handling and the
    -NoBackup, -WhatIf and -Help behavior. Requires Pester 5+.
.EXAMPLE
    Invoke-Pester -Path .\Format-CommentBlocks.Tests.ps1
#>

BeforeAll {
    . "$PSScriptRoot\Format-CommentBlocks.ps1"
}

Describe 'Get-WrappedLines' {

    It 'wraps words so every line stays within MaxLength' {
        $words  = 'the', 'quick', 'brown', 'fox', 'jumps', 'over', 'the', 'lazy', 'dog'
        $result = Get-WrappedLines -Words $words -Prefix '# ' -MaxLength 15
        foreach ($line in $result) { $line.Length | Should -BeLessOrEqual 15 }
    }

    It 'always places the first word on a line, even if it alone exceeds MaxLength' {
        $result = Get-WrappedLines -Words @('way-too-long-for-the-line') -Prefix '# ' -MaxLength 10
        $result.Count | Should -Be 1
        $result[0] | Should -Be '# way-too-long-for-the-line'
    }

    It 'keeps a word ending in ----- on the current line even past MaxLength' {
        $result = Get-WrappedLines -Words @('foo', 'bar-----') -Prefix '# ' -MaxLength 5
        $result.Count | Should -Be 1
        $result[0] | Should -Be '# foo bar-----'
    }

    It 'starts a new line for an ordinary word that would exceed MaxLength' {
        $result = Get-WrappedLines -Words @('foo', 'barbaz') -Prefix '# ' -MaxLength 6
        $result.Count | Should -Be 2
        $result[0] | Should -Be '# foo'
        $result[1] | Should -Be '# barbaz'
    }

    It 'returns an empty list for an empty word list' {
        $result = Get-WrappedLines -Words @() -Prefix '# ' -MaxLength 10
        $result.Count | Should -Be 0
    }
}

Describe 'Get-LineDiff' {

    It 'returns no operations for two empty arrays' {
        (Get-LineDiff -Original @() -New @()).Count | Should -Be 0
    }

    It 'marks identical arrays as fully Equal' {
        $lines  = 'a', 'b', 'c'
        $result = Get-LineDiff -Original $lines -New $lines
        $result.Count | Should -Be 3
        ($result | Where-Object Type -ne 'Equal').Count | Should -Be 0
    }

    It 'detects a single insert' {
        $result = Get-LineDiff -Original @('a', 'b') -New @('a', 'x', 'b')
        ($result | Where-Object Type -eq 'Insert').Line | Should -Be 'x'
    }

    It 'detects a single delete' {
        $result = Get-LineDiff -Original @('a', 'b', 'c') -New @('a', 'c')
        ($result | Where-Object Type -eq 'Delete').Line | Should -Be 'b'
    }

    It 'reconstructs New from the Equal/Insert lines, in order' {
        $orig    = 'a', 'b', 'c', 'd', 'e'
        $new     = 'a', 'z', 'c', 'd', 'y', 'e'
        $result  = Get-LineDiff -Original $orig -New $new
        $rebuilt = @($result | Where-Object { $_.Type -in 'Equal', 'Insert' } | ForEach-Object Line)
        Should -ActualValue $rebuilt -Be $new
    }

    It 'reconstructs Original from the Equal/Delete lines, in order' {
        $orig    = 'a', 'b', 'c', 'd', 'e'
        $new     = 'a', 'z', 'c', 'd', 'y', 'e'
        $result  = Get-LineDiff -Original $orig -New $new
        $oldSide = @($result | Where-Object { $_.Type -in 'Equal', 'Delete' } | ForEach-Object Line)
        Should -ActualValue $oldSide -Be $orig
    }

    It 'handles fully different arrays with no common lines' {
        $result = Get-LineDiff -Original @('a', 'b') -New @('x', 'y')
        ($result | Where-Object Type -eq 'Equal').Count | Should -Be 0
        $result.Count | Should -Be 4
    }
}

Describe 'Format-CommentBlocks' {

    BeforeEach {
        $script:testFile = Join-Path $TestDrive 'Test.ps1'
        Remove-Item -Path "$testFile.bak" -ErrorAction SilentlyContinue
    }

    It 'reflows a long comment paragraph to fit MaxLength' {
        '# This is a fairly long comment that should get wrapped once it is reflowed by the tool because it runs well past the limit.' |
            Set-Content -Path $testFile -Encoding UTF8

        Format-CommentBlocks -Path $testFile -MaxLength 40 -Confirm:$false

        $result = Get-Content -Path $testFile -Encoding UTF8
        $result.Count | Should -BeGreaterThan 1
        foreach ($line in $result) { $line.Length | Should -BeLessOrEqual 40 }
    }

    It 'starts a new paragraph after a line ending in a period' {
        @(
            '# First sentence.'
            '# Second sentence that continues the thought without a marker'
        ) | Set-Content -Path $testFile -Encoding UTF8

        Format-CommentBlocks -Path $testFile -MaxLength 100 -Confirm:$false

        $result = Get-Content -Path $testFile -Encoding UTF8
        $result.Count | Should -Be 2
        $result[0] | Should -Be '# First sentence.'
    }

    It 'leaves block comments untouched' {
        @(
            '<#'
            '.SYNOPSIS'
            '    Some help text that is not touched by reflowing at all.'
            '#>'
        ) | Set-Content -Path $testFile -Encoding UTF8

        $before = Get-Content -Path $testFile -Encoding UTF8
        Format-CommentBlocks -Path $testFile -MaxLength 20 -Confirm:$false
        $after = Get-Content -Path $testFile -Encoding UTF8

        Should -ActualValue $after -Be $before
    }

    It 'leaves #region, #endregion, #requires and shebang lines untouched' {
        @(
            '#region Setup'
            '#requires -Version 5.1'
            '#!/usr/bin/env pwsh'
            '#endregion'
        ) | Set-Content -Path $testFile -Encoding UTF8

        $before = Get-Content -Path $testFile -Encoding UTF8
        Format-CommentBlocks -Path $testFile -MaxLength 10 -Confirm:$false
        $after = Get-Content -Path $testFile -Encoding UTF8

        Should -ActualValue $after -Be $before
    }

    It 'wraps consecutive list items independently, never merging them' {
        @(
            '# - First bullet point'
            '# - Second bullet point'
            '# - Third bullet point'
        ) | Set-Content -Path $testFile -Encoding UTF8

        Format-CommentBlocks -Path $testFile -MaxLength 100 -Confirm:$false

        $result = Get-Content -Path $testFile -Encoding UTF8
        $result.Count | Should -Be 3
        $result[0] | Should -Be '# - First bullet point'
        $result[1] | Should -Be '# - Second bullet point'
        $result[2] | Should -Be '# - Third bullet point'
    }

    It 'makes no changes to the file under -WhatIf' {
        '# a comment that is definitely going to get reflowed by the tool right here' |
            Set-Content -Path $testFile -Encoding UTF8
        $before = Get-Content -Path $testFile -Raw -Encoding UTF8

        Format-CommentBlocks -Path $testFile -MaxLength 20 -WhatIf

        (Get-Content -Path $testFile -Raw -Encoding UTF8) | Should -Be $before
        Test-Path "$testFile.bak" | Should -BeFalse
    }

    It 'backs up the original file by default, without needing a flag' {
        $original = '# a comment that is definitely going to get reflowed by the tool right here'
        $original | Set-Content -Path $testFile -Encoding UTF8

        Format-CommentBlocks -Path $testFile -MaxLength 20 -Confirm:$false

        $backupPath = "$testFile.bak"
        Test-Path $backupPath | Should -BeTrue
        (Get-Content -Path $backupPath -Raw -Encoding UTF8).Trim() | Should -Be $original
    }

    It 'skips the backup when -NoBackup is passed' {
        '# a comment that is definitely going to get reflowed by the tool right here' |
            Set-Content -Path $testFile -Encoding UTF8

        Format-CommentBlocks -Path $testFile -MaxLength 20 -NoBackup -Confirm:$false

        Test-Path "$testFile.bak" | Should -BeFalse
    }

    It 'does not create a .bak file under -WhatIf even with the default backup on' {
        '# some comment line here that is long enough to reflow if it were applied' |
            Set-Content -Path $testFile -Encoding UTF8

        Format-CommentBlocks -Path $testFile -MaxLength 20 -WhatIf

        Test-Path "$testFile.bak" | Should -BeFalse
    }

    It 'preserves non-ASCII characters through the UTF8 read/write round trip' {
        '# commentaar met accenten: café, één, groente' | Set-Content -Path $testFile -Encoding UTF8

        Format-CommentBlocks -Path $testFile -MaxLength 200 -Confirm:$false

        (Get-Content -Path $testFile -Encoding UTF8) | Should -Be '# commentaar met accenten: café, één, groente'
    }

    It '-Help prints help and does not require -Path' {
        { Format-CommentBlocks -Help } | Should -Not -Throw
    }
}
