
## New-Item -Path $PROFILE -ItemType File -Force
## Notepad $profile  


## Invoke-RobocopyMirrorforNAS 'J:\_NAS移行用\@_lowcapacity\' 'N:\Data Migration POC'

## DIR J:\_NAS移行用\@_lowcapacity\
## DIR 'N:\Data Migration POC'


function Invoke-RobocopyMirrorforNAS {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,
        [Parameter(Mandatory)]
        [string]$Destination,
        [int]$Threads = 16,
        [string]$LogDirectory = $env:TEMP,
        [switch]$VerifyAfterCopy
    )

    (Get-Item "$env:SystemRoot\System32\Robocopy.exe").VersionInfo.FileVersion
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $type = if ($os.ProductType -eq 1) { "Client" } else { "Server" }
    Write-Host "$type - $($os.Caption) (Build $($os.BuildNumber))"

    # Ensure console/session can render non-English output correctly (cosmetic, but prevents
    # garbled display if anything gets written to host during the run)
    $originalOutputEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    $logPath = Join-Path -Path $LogDirectory -ChildPath "robocopy-mirror-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

    $robocopyArgs = @(
        "`"$Source`"",
        "`"$Destination`"",
        "/MIR",
        "/COPY:DAT",
        "/DCOPY:DAT",
        "/MT:$Threads",
        "/R:1",
        "/W:1",
        "/NP",
        "/NDL",
        "/UNILOG:`"$logPath`"",   # Unicode-encoded log so non-English filenames render correctly (plain /LOG produces gibberish)
        "/UNICODE",                # forces Unicode console/output stream from robocopy itself
        "/TEE"
    )

    try {
        $process = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -NoNewWindow -PassThru

        if ($process.ExitCode -ge 8) {
            throw "Robocopy failed with exit code $($process.ExitCode). See log: $logPath"
        }

        $result = [PSCustomObject]@{
            Source            = $Source
            Destination       = $Destination
            ExitCode          = $process.ExitCode
            LogPath           = $logPath
            Success           = $true
            VerificationRun   = $false
            MissingItems      = @()
        }

        # Robocopy can silently fail to copy items with malformed/invalid UTF-16 names
        # (unpaired surrogates) and reports success with no error. This step catches that
        # by independently comparing recursive item counts/paths, not relying on robocopy's own reporting.
        if ($VerifyAfterCopy) {
            Write-Verbose "Running post-copy verification for silent Unicode failures..."

            $sourceItems = [System.Collections.Generic.HashSet[string]]::new()
            $destItems   = [System.Collections.Generic.HashSet[string]]::new()

            foreach ($path in [System.IO.Directory]::EnumerateFileSystemEntries($Source, '*', 'AllDirectories')) {
                [void]$sourceItems.Add($path.Substring($Source.Length).TrimStart('\'))
            }
            foreach ($path in [System.IO.Directory]::EnumerateFileSystemEntries($Destination, '*', 'AllDirectories')) {
                [void]$destItems.Add($path.Substring($Destination.Length).TrimStart('\'))
            }

            $missing = $sourceItems | Where-Object { -not $destItems.Contains($_) }

            $result.VerificationRun = $true
            $result.MissingItems = @($missing)

            if ($missing.Count -gt 0) {
                Write-Warning "$($missing.Count) item(s) present in source but missing from destination — possible malformed Unicode names. See MissingItems on the returned object."
            }
        }

        return $result
    }
    finally {
        [Console]::OutputEncoding = $originalOutputEncoding
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

Write-Output "Ready for NAS copies
Write-Output "Functions defined: Invoke-RobocopyMirrorforNAS
Get-Robocopyinfo



