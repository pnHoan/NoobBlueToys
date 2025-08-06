# ExtractPowerShellScripts.ps1
# Description: Extracts and reconstructs PowerShell scripts from an EVTX file or all EVTX files in a directory (Microsoft-Windows-PowerShell/Operational) using event IDs 4103, 4104, and 4105, and saves them as .ps1 or .txt files in a specified folder (defaults to 'out' in the input directory).
# Usage: .\ExtractPowerShellScripts.ps1 -EvtxPath <path_to_evtx_file_or_directory> [-OutputFolder <output_directory>] [-SaveAsPS1]

param (
    [Parameter(Mandatory=$true, HelpMessage="Path to an EVTX file or a directory containing EVTX files")]
    [Alias("f")]
    [string]$EvtxPath,
    [Parameter(Mandatory=$false, HelpMessage="Path to the output folder for scripts (defaults to 'out' in EVTX directory)")]
    [Alias("o")]
    [string]$OutputFolder,
    [Parameter(HelpMessage="Save extracted scripts as .ps1 files (default is .txt)")]
    [switch]$SaveAsPS1
)

# Function to process a single EVTX file
function ProcessEvtxFile {
    param (
        [string]$FilePath,
        [string]$OutputFolder,
        [switch]$SaveAsPS1
    )

    # Validate EVTX file existence
    if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
        Write-Host "Error: EVTX file does not exist at $FilePath" -ForegroundColor Red
        return
    }

    # Get events with IDs 4103, 4104, and 4105 from the EVTX file
    Write-Host "Reading events from $FilePath..."
    try {
        $events = Get-WinEvent -FilterHashtable @{
            Path = $FilePath
            ProviderName = "Microsoft-Windows-PowerShell"
            Id = 4103, 4104, 4105
        } -ErrorAction Stop
    }
    catch {
        Write-Host "Error: Failed to read events from $FilePath. $_" -ForegroundColor Red
        return
    }

    if (-not $events) {
        Write-Host "No PowerShell script-related events (IDs 4103, 4104, 4105) found in $FilePath." -ForegroundColor Yellow
        return
    }

    # Group events by ScriptBlock ID
    $scriptBlocks = @{}
    foreach ($evtxEvent in $events) {
        $eventId = $evtxEvent.Id
        $scriptBlockId = $null
        $scriptContent = $null
        $sequenceNumber = $null
        $totalFragments = $null
        $scriptName = $null
        $contextInfo = $null
        $startTime = $null

        if ($eventId -eq 4104) {
            # Script Block Logging
            $scriptBlockId = $evtxEvent.Properties[3].Value
            $scriptContent = $evtxEvent.Properties[2].Value
            $sequenceNumber = $evtxEvent.Properties[0].Value
            $totalFragments = $evtxEvent.Properties[1].Value
            $scriptName = if ($evtxEvent.Properties[4].Value) { Split-Path -Path $evtxEvent.Properties[4].Value -Leaf } else { "Script_$scriptBlockId" }
        }
        elseif ($eventId -eq 4103) {
            # Module Logging (Command Invocation)
            $scriptBlockId = $evtxEvent.Properties[2].Value
            $contextInfo = $evtxEvent.Properties[1].Value
        }
        elseif ($eventId -eq 4105) {
            # Script Block Start
            $scriptBlockId = $evtxEvent.Properties[3].Value
            $startTime = $evtxEvent.TimeCreated
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
                    Write-Host "Warning: ScriptBlock ID $scriptBlockId is missing fragment $i of $totalFragments in $FilePath." -ForegroundColor Yellow
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
            Write-Host "Warning: No script content or context for ScriptBlock ID $scriptBlockId in $FilePath." -ForegroundColor Yellow
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
}

# Set default output folder to 'out' in the same directory as the EVTX file or directory
if (-not $OutputFolder) {
    # $evtxDir = Split-Path -Path $EvtxPath -Parent
    $OutputFolder = Join-Path -Path $EvtxPath -ChildPath "out"
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

# Check if EvtxPath is a directory or a single file
if (Test-Path -Path $EvtxPath -PathType Container) {
    # Process all .evtx files in the directory
    $evtxFiles = Get-ChildItem -Path $EvtxPath -Filter "*.evtx" -File
    if ($evtxFiles.Count -eq 0) {
        Write-Host "No .evtx files found in directory '$EvtxPath'." -ForegroundColor Yellow
        exit 0
    }

    foreach ($file in $evtxFiles) {
        Write-Host "Processing EVTX file: $($file.FullName)"
        ProcessEvtxFile -FilePath $file.FullName -OutputFolder $OutputFolder -SaveAsPS1:$SaveAsPS1
    }
}
else {
    # Process a single EVTX file
    if ($EvtxPath -notmatch "\.evtx$") {
        Write-Host "Error: Specified path '$EvtxPath' is not an EVTX file." -ForegroundColor Red
        exit 1
    }
    ProcessEvtxFile -FilePath $EvtxPath -OutputFolder $OutputFolder -SaveAsPS1:$SaveAsPS1
}

Write-Host "Script extraction complete. Files saved to $OutputFolder" -ForegroundColor Green