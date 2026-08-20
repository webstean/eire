## New-Item -Path $PROFILE -ItemType File -Force
## Notepad $profile  

<#
    DataBox / NAS Robocopy Manifest Module
    ---------------------------------------
    Consolidated from prior mirror/delta/compliance functions.

    Unicode handling summary (why each piece exists):
      - .NET strings are UTF-16 internally, so [System.IO.Directory]::EnumerateFiles
        and friends already handle non-English *filenames* correctly without any
        extra work — the actual risk areas are:
          1. Robocopy's own console/log output (OEM code page by default -> gibberish)
          2. Robocopy silently skipping items with malformed/invalid UTF-16 names
             (unpaired surrogates) with NO error reported
          3. JSON manifest round-tripping (functionally fine, but worth being explicit
             about encoding so nothing downstream re-mangles it)
          4. Path-length checks using .Length (UTF-16 code units) mis-counting
             surrogate-pair characters (emoji, rare CJK) as 2 instead of 1
      - Each fix is called out inline below at the point it matters.
#>

# ----------------------------------------------------------------------------
# Path compliance check (Data Box / Azure Storage naming rules)
# ----------------------------------------------------------------------------
function Test-DataBoxNFSPathCompliance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,          # full relative path from NFS mount root

        [Parameter(Mandatory)]
        [System.Collections.Generic.HashSet[string]]$SeenLowerPaths  # case-collision tracking across the whole tree
    )

    $reservedNames = @(
        'CON','PRN','AUX','NUL','CLOCK$',
        'COM1','COM2','COM3','COM4','COM5','COM6','COM7','COM8','COM9',
        'LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9'
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $segments = $Path -split '/' | Where-Object { $_ -ne '' }

    foreach ($segment in $segments) {

        # Reserved device names (case-insensitive, ignoring extension)
        $baseName = $segment -replace '\.[^.]*$', ''
        if ($reservedNames -contains $baseName.ToUpperInvariant()) {
            $issues.Add("Reserved name '$segment' in path: $Path")
        }

        # Disallowed characters (ASCII-range reserved chars — unaffected by non-English content)
        if ($segment -match '["\\:|<>*?]') {
            $issues.Add("Disallowed character in segment '$segment': $Path")
        }

        # Control characters (0x00-0x1F) and \u0081
        if ($segment -match '[\x00-\x1F\u0081]') {
            $issues.Add("Control character in segment '$segment': $Path")
        }

        # Trailing dot or space on a component
        if ($segment -match '[. ]$') {
            $issues.Add("Trailing dot/space in segment '$segment': $Path")
        }

        # Component length — use Unicode TEXT ELEMENTS (code points / grapheme-aware),
        # not raw .Length. .Length counts UTF-16 code units, so a single emoji or a rare
        # CJK Extension-B character (outside the Basic Multilingual Plane) is stored as a
        # surrogate PAIR and would be double-counted by .Length, giving a false positive
        # on the 255-char limit for perfectly legal names.
        $stringInfo = [System.Globalization.StringInfo]::new($segment)
        if ($stringInfo.LengthInTextElements -gt 255) {
            $issues.Add("Segment exceeds 255 text elements: $segment")
        }

        # Detect unpaired (invalid) surrogates — the specific pattern that causes
        # robocopy to silently DROP an item with no error at all. Catching it here,
        # before the copy even runs, is far better than discovering it via a missing
        # file after the fact.
        for ($i = 0; $i -lt $segment.Length; $i++) {
            if ([char]::IsHighSurrogate($segment[$i])) {
                if ($i + 1 -ge $segment.Length -or -not [char]::IsLowSurrogate($segment[$i + 1])) {
                    $issues.Add("Unpaired high surrogate (invalid UTF-16) in segment '$segment': $Path")
                }
                $i++  # skip the low surrogate, it's part of the pair we just validated
            }
            elseif ([char]::IsLowSurrogate($segment[$i])) {
                $issues.Add("Unpaired low surrogate (invalid UTF-16) in segment '$segment': $Path")
            }
        }
    }

    # Full path length (code-point aware, same reasoning as above)
    $pathStringInfo = [System.Globalization.StringInfo]::new($Path)
    if ($pathStringInfo.LengthInTextElements -gt 2048) {
        $issues.Add("Full path exceeds 2048 text elements: $Path")
    }

    # Subdirectory depth (250 max)
    if (($segments.Count - 1) -gt 250) {
        $issues.Add("Path depth exceeds 250 subdirectories: $Path")
    }

    # Case-collision detection (cross-file, needs shared hashset across the manifest run).
    # NB: ToLowerInvariant() is culture-invariant casing, important since some casing rules
    # differ by locale (e.g. Turkish 'I') and we want consistent collision detection
    # regardless of the machine's regional settings.
    $lowerPath = $Path.ToLowerInvariant()
    if (-not $SeenLowerPaths.Add($lowerPath)) {
        $issues.Add("Case-collision with another path already seen: $Path")
    }

    return $issues
}

# ----------------------------------------------------------------------------
# Elevation check
# ----------------------------------------------------------------------------
function Assert-LocalAdmin {
    [CmdletBinding()]
    param()
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This must be run from an elevated (Run as Administrator) PowerShell session. Current user: $($identity.Name)"
    }
}

# ----------------------------------------------------------------------------
# Console/Unicode setup helper — call before any robocopy invocation, restore after
# ----------------------------------------------------------------------------
function Enter-UnicodeConsoleContext {
    [CmdletBinding()]
    param()
    $previous = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    return $previous
}

function Exit-UnicodeConsoleContext {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Text.Encoding]$PreviousEncoding)
    [Console]::OutputEncoding = $PreviousEncoding
}

# ----------------------------------------------------------------------------
# Manifest data collection
# ----------------------------------------------------------------------------
function Get-SourceManifestData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source
    )

    # \\?\ extended-length path prefix: Windows PowerShell 5.1 / .NET Framework enforces
    # the legacy 260-char MAX_PATH unless the path is prefixed this way. Non-English deep
    # trees (long descriptive names in the source language) hit this ceiling far more
    # often than short ASCII names would, so this is directly relevant here — without it,
    # deep/long non-English paths silently fail to enumerate rather than erroring clearly.
    $sourceFull = (Resolve-Path -LiteralPath $Source).ProviderPath.TrimEnd('\')
    $enumRoot = if ($sourceFull.StartsWith('\\?\') -or $sourceFull.StartsWith('\\')) {
        $sourceFull  # UNC paths and already-prefixed paths pass through untouched
    } else {
        "\\?\$sourceFull"
    }

    $enumOptions = [System.IO.EnumerationOptions]@{
        RecurseSubdirectories = $true
        IgnoreInaccessible    = $true
        AttributesToSkip      = [System.IO.FileAttributes]::ReparsePoint
    }

    foreach ($path in [System.IO.Directory]::EnumerateFiles($enumRoot, '*', $enumOptions)) {
        $fi = [System.IO.FileInfo]::new($path)
        [PSCustomObject]@{
            RelativePath   = $path.Substring($enumRoot.Length).TrimStart('\')
            Length         = $fi.Length
            LastWriteTicks = $fi.LastWriteTimeUtc.Ticks
        }
    }
}

# ----------------------------------------------------------------------------
# Manifest persistence — explicit UTF-8 without BOM for consistent round-tripping
# ----------------------------------------------------------------------------
function Save-Manifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Data
    )
    $manifestDir = Split-Path -Parent $ManifestPath
    if ($manifestDir -and -not (Test-Path -LiteralPath $manifestDir)) {
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
    }

    # -Depth generous enough for the flat object array; ConvertTo-Json in Windows
    # PowerShell 5.1 escapes non-ASCII as \uXXXX by default — this is cosmetically
    # different from raw UTF-8 text but round-trips through ConvertFrom-Json perfectly,
    # so no functional data loss for any non-English filename.
    $json = $Data | ConvertTo-Json -Depth 3

    # Explicit UTF-8 WITHOUT BOM via .NET, avoiding Set-Content's BOM-adding behavior
    # in Windows PowerShell 5.1 (PS7's -Encoding utf8 is BOM-less by default, 5.1 is not).
    # A stray BOM in a JSON file is usually harmless but some downstream JSON parsers choke on it.
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($ManifestPath, $json, $utf8NoBom)
}

function Backup-Manifest {
    <#
        Archives the current manifest file (if it exists) into a
        ManifestHistory subfolder before it gets overwritten, so the
        metadata trail across runs isn't lost.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManifestPath
    )
    if (-not (Test-Path -LiteralPath $ManifestPath)) { return }

    $manifestDir  = Split-Path -Parent $ManifestPath
    $manifestName = Split-Path -Leaf $ManifestPath
    $historyDir   = Join-Path $manifestDir "ManifestHistory"

    if (-not (Test-Path -LiteralPath $historyDir)) {
        New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
    }

    $stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
    $archive = Join-Path $historyDir "$stamp.$manifestName"
    Copy-Item -LiteralPath $ManifestPath -Destination $archive -Force
    Write-Verbose "Archived previous manifest to $archive"
}

# ----------------------------------------------------------------------------
# Post-copy verification for robocopy's silent Unicode failure mode.
# Robocopy can drop items with invalid/unpaired-surrogate names and report
# success with NO error and NO log entry — this is the only reliable catch.
# ----------------------------------------------------------------------------
function Test-MirrorCompleteness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $sourceFull = (Resolve-Path -LiteralPath $Source).ProviderPath.TrimEnd('\')
    $destFull   = (Resolve-Path -LiteralPath $Destination).ProviderPath.TrimEnd('\')

    $enumOptions = [System.IO.EnumerationOptions]@{
        RecurseSubdirectories = $true
        IgnoreInaccessible    = $true
    }

    $sourceCount = 0
    $destSet = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($p in [System.IO.Directory]::EnumerateFileSystemEntries($destFull, '*', $enumOptions)) {
        [void]$destSet.Add($p.Substring($destFull.Length).TrimStart('\'))
    }

    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($p in [System.IO.Directory]::EnumerateFileSystemEntries($sourceFull, '*', $enumOptions)) {
        $sourceCount++
        $rel = $p.Substring($sourceFull.Length).TrimStart('\')
        if (-not $destSet.Contains($rel)) {
            $missing.Add($rel)
        }
    }

    [PSCustomObject]@{
        SourceItemCount = $sourceCount
        DestItemCount   = $destSet.Count
        MissingItems    = @($missing)
        IsComplete      = ($missing.Count -eq 0)
    }
}

# ----------------------------------------------------------------------------
# Base mirror (first full copy) — establishes the manifest baseline
# ----------------------------------------------------------------------------
function Invoke-RobocopyMirror {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [string]$LogPath = "C:\Logs\Robocopy-Mirror.log",

        [string]$ManifestPath,

        [int]$Retries = 5,

        [int]$WaitSeconds = 10,

        [ValidateRange(1,128)]
        [int]$Threads = 64,

        [switch]$VerifyAfterCopy
    )

    $Source      = $Source.TrimEnd('\')
    $Destination = $Destination.TrimEnd('\')
    if (-not $ManifestPath) { $ManifestPath = "$LogPath.manifest.json" }

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source path does not exist: $Source"
    }
    $logDir = Split-Path -Parent $LogPath
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    $robocopyArgs = @(
        "`"$Source`""
        "`"$Destination`""
        "/MIR"
        "/ZB"
        "/COPY:DAT"
        "/DCOPY:DAT"
        "/R:$Retries"
        "/W:$WaitSeconds"
        "/MT:$Threads"
        "/FFT"
        "/XJ"
        "/NP"
        "/UNICODE"                # forces robocopy's own console/output stream to Unicode
        "/UNILOG+:`"$LogPath`""   # Unicode-encoded log — plain /LOG renders non-English names as gibberish
        # /TEE dropped for unattended runs; add back explicitly if running interactively.
    )

    Write-Host "Starting robocopy mirror (base copy)..."
    Write-Host "Source:      $Source"
    Write-Host "Destination: $Destination"
    Write-Host "Log:         $LogPath"
    Write-Host "Manifest:    $ManifestPath"

    $prevEncoding = Enter-UnicodeConsoleContext
    try {
        $process  = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
        $exitCode = $process.ExitCode
    }
    finally {
        Exit-UnicodeConsoleContext -PreviousEncoding $prevEncoding
    }

    if ($exitCode -ge 8) {
        throw "Robocopy failed with exit code $exitCode. Check log: $LogPath"
    }

    Write-Host "Robocopy mirror completed. Exit code: $exitCode"

    $verification = $null
    if ($VerifyAfterCopy) {
        Write-Host "Verifying mirror completeness (catches robocopy's silent Unicode-drop failure mode)..."
        $verification = Test-MirrorCompleteness -Source $Source -Destination $Destination
        if (-not $verification.IsComplete) {
            Write-Warning "$($verification.MissingItems.Count) item(s) present in source but missing from destination. See returned MissingItems."
        }
    }

    Write-Host "Snapshotting source tree to manifest..."
    Backup-Manifest -ManifestPath $ManifestPath
    $manifestData = Get-SourceManifestData -Source $Source
    Save-Manifest -ManifestPath $ManifestPath -Data $manifestData

    Write-Host "Manifest saved: $ManifestPath ($($manifestData.Count) files)"

    [PSCustomObject]@{
        ExitCode     = $exitCode
        FileCount    = $manifestData.Count
        ManifestPath = $ManifestPath
        Verification = $verification
    }
}

# ----------------------------------------------------------------------------
# Delta copy (subsequent runs) — copies only changed files per manifest diff
# ----------------------------------------------------------------------------
function Invoke-RobocopyDelta {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter(Mandatory)]
        [string]$ManifestPath,

        [string]$LogPath = "C:\Logs\Robocopy-Delta.log",

        [int]$Retries = 5,

        [int]$WaitSeconds = 10,

        [ValidateRange(1,128)]
        [int]$Threads = 64,

        [int]$ThrottleLimit = 8,

        [string]$DeltaLogDir,

        [switch]$VerifyAfterCopy
    )

    $Source      = $Source.TrimEnd('\')
    $Destination = $Destination.TrimEnd('\')

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source path does not exist: $Source"
    }
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "Manifest not found at $ManifestPath. Run Invoke-RobocopyMirror first to establish a baseline."
    }

    $logDir = Split-Path -Parent $LogPath
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    if (-not $DeltaLogDir) {
        $DeltaLogDir = Join-Path (Split-Path -Parent $ManifestPath) "DeltaRuns"
    }
    if (-not (Test-Path -LiteralPath $DeltaLogDir)) {
        New-Item -ItemType Directory -Path $DeltaLogDir -Force | Out-Null
    }

    Write-Host "Loading manifest: $ManifestPath"
    # Read manifest as UTF-8 explicitly — Get-Content -Raw alone relies on BOM/encoding
    # detection which can misfire on a BOM-less UTF-8 file in Windows PowerShell 5.1.
    $manifestBytes = [System.IO.File]::ReadAllBytes($ManifestPath)
    $manifestText  = [System.Text.Encoding]::UTF8.GetString($manifestBytes)
    $manifestData  = $manifestText | ConvertFrom-Json

    $previous = @{}
    foreach ($item in $manifestData) {
        $previous[$item.RelativePath] = $item
    }

    Write-Host "Scanning current source tree: $Source"
    $current = Get-SourceManifestData -Source $Source

    $toCopy = [System.Collections.Generic.List[object]]::new()
    $currentPaths = @{}

    foreach ($file in $current) {
        $currentPaths[$file.RelativePath] = $true
        $prev = $previous[$file.RelativePath]
        if (-not $prev -or $prev.Length -ne $file.Length -or $prev.LastWriteTicks -ne $file.LastWriteTicks) {
            $toCopy.Add($file)
        }
    }

    $removed = $previous.Keys | Where-Object { -not $currentPaths.ContainsKey($_) }

    Write-Host "Files to copy: $($toCopy.Count)  |  Unchanged (skipped): $($current.Count - $toCopy.Count)  |  Removed from source since last manifest: $($removed.Count)"

    $runStamp   = Get-Date -Format "yyyyMMdd-HHmmss"
    $copiedList = [System.Collections.Generic.List[object]]::new()

    if ($toCopy.Count -eq 0) {
        Write-Host "Nothing to copy."
    }
    else {
        $byDir = $toCopy | Group-Object { Split-Path $_.RelativePath -Parent }

        Write-Host "Copying across $($byDir.Count) directories (throttle: $ThrottleLimit, /MT:$Threads per call)..."

        $prevEncoding = Enter-UnicodeConsoleContext
        try {
            $results = $byDir | ForEach-Object -Parallel {
                $group    = $_
                $srcRoot  = $using:Source
                $dstRoot  = $using:Destination
                $retries  = $using:Retries
                $wait     = $using:WaitSeconds
                $threads  = $using:Threads
                $logPath  = $using:LogPath

                $relDir = $group.Name
                $srcDir = if ($relDir) { Join-Path $srcRoot $relDir } else { $srcRoot }
                $dstDir = if ($relDir) { Join-Path $dstRoot $relDir } else { $dstRoot }

                # File list passed as an IF file — robocopy's file-list argument parsing
                # via a plain array can mis-tokenize names containing spaces or certain
                # Unicode punctuation when invoked through the pipeline/call operator.
                # A temp IF-file (one filename per line, UTF-8) is unambiguous regardless
                # of what characters the names contain.
                $fileNames = $group.Group | ForEach-Object { Split-Path $_.RelativePath -Leaf }
                $ifFile = [System.IO.Path]::GetTempFileName()
                [System.IO.File]::WriteAllLines($ifFile, $fileNames, [System.Text.UTF8Encoding]::new($false))

                try {
                    $roboArgs = @(
                        "`"$srcDir`""
                        "`"$dstDir`""
                        "/IF"
                        "@`"$ifFile`""
                        "/R:$retries"
                        "/W:$wait"
                        "/MT:$threads"
                        "/NP"
                        "/NDL"
                        "/NJH"
                        "/UNICODE"
                        "/UNILOG+:`"$logPath`""
                    )

                    $proc = Start-Process -FilePath "robocopy.exe" -ArgumentList $roboArgs -NoNewWindow -Wait -PassThru
                    $exitCode = $proc.ExitCode
                }
                finally {
                    Remove-Item -LiteralPath $ifFile -Force -ErrorAction SilentlyContinue
                }

                [PSCustomObject]@{
                    Directory = $relDir
                    ExitCode  = $exitCode
                    Files     = $group.Group
                    Success   = $exitCode -lt 8
                }
            } -ThrottleLimit $ThrottleLimit
        }
        finally {
            Exit-UnicodeConsoleContext -PreviousEncoding $prevEncoding
        }

        foreach ($r in $results) {
            if (-not $r.Success) {
                Write-Warning "Robocopy failed for directory '$($r.Directory)' (exit code $($r.ExitCode)). See $LogPath"
            }
            else {
                foreach ($f in $r.Files) { $copiedList.Add($f) }
            }
        }
    }

    $verification = $null
    if ($VerifyAfterCopy) {
        Write-Host "Verifying mirror completeness (catches robocopy's silent Unicode-drop failure mode)..."
        $verification = Test-MirrorCompleteness -Source $Source -Destination $Destination
        if (-not $verification.IsComplete) {
            Write-Warning "$($verification.MissingItems.Count) item(s) present in source but missing from destination. See returned MissingItems."
        }
    }

    # Per-run delta audit trail — what was copied THIS run, distinct from the
    # full current-state manifest (which only ever shows end-state).
    $deltaRunManifest = Join-Path $DeltaLogDir "$runStamp.delta.json"
    $deltaJson = [PSCustomObject]@{
        RunTimestampUtc   = (Get-Date).ToUniversalTime().ToString("o")
        Source            = $Source
        Destination       = $Destination
        CopiedCount       = $copiedList.Count
        RemovedCount      = @($removed).Count
        Copied            = $copiedList
        RemovedFromSource = @($removed)
    } | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($deltaRunManifest, $deltaJson, [System.Text.UTF8Encoding]::new($false))

    Write-Host "Per-run delta record saved: $deltaRunManifest"

    Backup-Manifest -ManifestPath $ManifestPath
    Save-Manifest -ManifestPath $ManifestPath -Data $current

    if ($removed.Count -gt 0) {
        Write-Host "Note: $($removed.Count) file(s) present in prior manifest are no longer in source. This function does not delete from destination — use /MIR semantics deliberately if that's intended."
    }

    Write-Host "Delta copy complete."

    [PSCustomObject]@{
        CopiedCount  = $copiedList.Count
        RemovedCount = @($removed).Count
        DeltaLog     = $deltaRunManifest
        Verification = $verification
    }
}

Function Get-Robocopyinfo {
    Write-Host "+========================================================="
    Write-Host "RoboCopy Info:"
    (Get-Item "$env:SystemRoot\System32\Robocopy.exe").VersionInfo.FileVersion
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $type = if ($os.ProductType -eq 1) { "Client" } else { "Server" }
    Write-Host "$type - $($os.Caption) (Build $($os.BuildNumber))"
    Write-Host "+========================================================="
}    

Write-Output "Ready for DataBox copies (Unicode-safe: /UNILOG, /UNICODE console handling, surrogate-pair-aware path checks, UTF-8-no-BOM manifest I/O)."
Write-Output "Functions defined: Invoke-RobocopyMirror, Invoke-RobocopyDelta, Test-DataBoxNFSPathCompliance"
Get-Robocopyinfo

