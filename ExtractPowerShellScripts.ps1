# ExtractPowerShellScripts.ps1
# Description: Extracts and reconstructs PowerShell scripts from an EVTX file (Microsoft-Windows-PowerShell/Operational) using event IDs 4103, 4104, and 4105, and saves them as .ps1 or .txt files in a specified folder (defaults to 'out' in the EVTX file's directory).
# Usage: .\ExtractPowerShellScripts.ps1 -EvtxPath <path_to_evtx_file> [-OutputFolder <output_directory>] [-SaveAsPS1]

param (
    [Parameter(Mandatory=$true, HelpMessage="Path to the EVTX file")]
    [ValidatePattern("\.evtx$")]
    [Alias("f")]
    [string]$EvtxPath,
    [Parameter(Mandatory=$false, HelpMessage="Path to the output folder for scripts (defaults to 'out' in EVTX directory)")]
    [Alias("o")]
    [string]$OutputFolder,
    [Parameter(HelpMessage="Save extracted scripts as .ps1 files (default is .txt)")]
    [switch]$SaveAsPS1
)

# Set default output folder to 'out' in the same directory as the EVTX file
if (-not $OutputFolder) {
    $evtxDir = Split-Path -Path $EvtxPath -Parent
    $OutputFolder = Join-Path -Path $evtxDir -ChildPath "out"
}

# Validate EVTX file existence
if (-not (Test-Path -Path $EvtxPath -PathType Leaf)) {
    Write-Host "Error: EVTX file does not exist at $EvtxPath" -ForegroundColor Red
    exit 1
}

# Validate and create output folder
try {
    if (-not (Test-Path -Path $OutputFolder)) {
        New-Item -Path $OutputFolder -ItemType Directory -ErrorAction Stop | Out-Null
        Write-Host "Created output folder at $OutputFolder" -ForegroundColor Green
    }
}
catch {
    Write-Host "Error: Failed to create output folder at $OutputFolder. $_" -ForegroundColor Red
    exit 1
}

# Get events with IDs 4103, 4104, and 4105 from the EVTX file
Write-Host "Reading events from $EvtxPath..."
try {
    $events = Get-WinEvent -FilterHashtable @{
        Path = $EvtxPath
        ProviderName = "Microsoft-Windows-PowerShell"
        Id = 4103, 4104, 4105
    } -ErrorAction Stop
}
catch {
    Write-Host "Error: Failed to read events from $EvtxPath. $_" -ForegroundColor Red
    exit 1
}

if (-not $events) {
    Write-Host "No PowerShell script-related events (IDs 4103, 4104, 4105) found in the EVTX file." -ForegroundColor Yellow
    exit 0
}

# Group events by ScriptBlock ID
$scriptBlocks = @{}
foreach ($event in $events) {
    $eventId = $event.Id
    $scriptBlockId = $null
    $scriptContent = $null
    $sequenceNumber = $null
    $totalFragments = $null
    $scriptName = $null
    $contextInfo = $null
    $startTime = $null

    if ($eventId -eq 4104) {
        # Script Block Logging
        $scriptBlockId = $event.Properties[3].Value
        $scriptContent = $event.Properties[2].Value
        $sequenceNumber = $event.Properties[0].Value
        $totalFragments = $event.Properties[1].Value
        $scriptName = if ($event.Properties[4].Value) { Split-Path -Path $event.Properties[4].Value -Leaf } else { "Script_$scriptBlockId" }
    }
    elseif ($eventId -eq 4103) {
        # Module Logging (Command Invocation)
        $scriptBlockId = $event.Properties[2].Value
        $contextInfo = $event.Properties[1].Value
    }
    elseif ($eventId -eq 4105) {
        # Script Block Start
        $scriptBlockId = $event.Properties[3].Value
        $startTime = $event.TimeCreated
    }

    if ($scriptBlockId) {
        if (-not $scriptBlocks.ContainsKey($scriptBlockId)) {
            $scriptBlocks[$scriptBlockId] = @{
                Fragments = @{}
                TotalFragments = 0
                ScriptName = "Script_$scriptBlockId"
                ContextInfo = $null
                StartTime = $null
            }
        }

        if ($eventId -eq 4104) {
            $scriptBlocks[$scriptBlockId].Fragments[$sequenceNumber] = $scriptContent
            $scriptBlocks[$scriptBlockId].TotalFragments = $totalFragments
            $scriptBlocks[$scriptBlockId].ScriptName = $scriptName
        }
        elseif ($eventId -eq 4103) {
            $scriptBlocks[$scriptBlockId].ContextInfo = $contextInfo
        }
        elseif ($eventId -eq 4105) {
            $scriptBlocks[$scriptBlockId].StartTime = $startTime
        }
    }
}

# Reconstruct and save each script
foreach ($scriptBlockId in $scriptBlocks.Keys) {
    $block = $scriptBlocks[$scriptBlockId]
    $fragments = $block.Fragments
    $totalFragments = $block.TotalFragments
    $scriptName = $block.ScriptName
    $contextInfo = $block.ContextInfo
    $startTime = $block.StartTime

    # Check if all fragments are present (for 4104 events)
    $allFragmentsPresent = $true
    if ($totalFragments -gt 0) {
        for ($i = 1; $i -le $totalFragments; $i++) {
            if (-not $fragments.ContainsKey($i)) {
                $allFragmentsPresent = $false
                Write-Host "Warning: ScriptBlock ID $scriptBlockId is missing fragment $i of $totalFragments." -ForegroundColor Yellow
                break
            }
        }
    }

    # Construct header with context and metadata
    $header = "# ScriptBlock ID: $scriptBlockId`n"
    if ($startTime) {
        $header += "# Execution Start Time: $startTime`n"
    }
    if ($contextInfo) {
        $header += "# Context Info: $contextInfo`n"
    }
    if (-not $allFragmentsPresent -and $totalFragments -gt 0) {
        $header += "# Warning: Incomplete script due to missing fragments`n"
    }
    if ($SaveAsPS1) {
        $header += "# WARNING: This script was extracted from an EVTX file and may contain malicious code. Review carefully before execution.`n"
    }

    # Reconstruct the script (if 4104 events exist)
    $scriptContent = ""
    if ($totalFragments -gt 0) {
        $sortedFragments = $fragments.GetEnumerator() | Sort-Object { [int]$_.Key }
        $scriptContent = -join ($sortedFragments | ForEach-Object { $_.Value })
    }
    elseif ($contextInfo) {
        $scriptContent = "# No script content found; only context information available.`n$contextInfo"
    }
    else {
        Write-Host "Warning: No script content or context for ScriptBlock ID $scriptBlockId." -ForegroundColor Yellow
        continue
    }

    # Combine header and content
    $scriptContent = $header + $scriptContent

    # Determine file extension based on SaveAsPS1 flag
    $fileExtension = if ($SaveAsPS1) { ".ps1" } else { ".txt" }
    
    # Handle duplicate filenames
    $baseOutputFileName = "${scriptBlockId}_${scriptName}"
    $outputFileName = $baseOutputFileName + $fileExtension
    $outputPath = Join-Path -Path $OutputFolder -ChildPath $outputFileName
    $counter = 1
    while (Test-Path $outputPath) {
        $outputFileName = "${baseOutputFileName}_${counter}${fileExtension}"
        $outputPath = Join-Path -Path $OutputFolder -ChildPath $outputFileName
        $counter++
    }

    # Save to file
    try {
        $scriptContent | Out-File -FilePath $outputPath -Encoding UTF8 -ErrorAction Stop
        Write-Host "Saved script to $outputPath" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: Failed to save script to $outputPath. $_" -ForegroundColor Red
        continue
    }
}

Write-Host "Script extraction complete. Files saved to $OutputFolder" -ForegroundColor Green