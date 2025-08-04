# ParseEvtxLogs.ps1
# Script to parse .evtx log files using Eric Zimmerman's EvtxECmd tool
# Requires one input parameter for the folder containing .evtx logs
# Creates parsed_csv and parsed_json folders for output in the same directory
# Output files retain the same name as the input .evtx files

param (
    [Parameter(Mandatory=$true, HelpMessage="Path to folder containing .evtx log files")]
    [Alias("p")]
    [string]$LogFolder
    [Parameter(Mandatory=$false, HelpMessage="Path to EvtxECmd executable")]
    [Alias("e")]
    [string]$EvtxCmdPath = $env:EVXTECMD_PATH
)

# If EvtxCmdPath is not provided via parameter or environment variable, try config.json
if (-not $EvtxCmdPath) {
    $configPath = Join-Path -Path $PSScriptRoot -ChildPath "config.json"
    if (Test-Path -Path $configPath -PathType Leaf) {
        try {
            $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
            $EvtxCmdPath = $config.EvtxCmdPath
        }
        catch {
            Write-Error "Failed to read or parse config.json: $_"
            exit 1
        }
    }
}

# Check if EvtxECmd path is valid
if (-not $EvtxCmdPath -or -not (Test-Path -Path $EvtxCmdPath -PathType Leaf)) {
    Write-Error "EvtxECmd.exe not found. Please provide a valid path using -e, set the EVXTECMD_PATH environment variable, or ensure a valid config.json exists."
    exit 1
}

# Validate input folder
if (-not (Test-Path -Path $LogFolder -PathType Container)) {
    Write-Error "The specified log folder '$LogFolder' does not exist."
    exit 1
}

# Create output directories
$csvOutputFolder = Join-Path -Path $LogFolder -ChildPath "parsed_csv"
$jsonOutputFolder = Join-Path -Path $LogFolder -ChildPath "parsed_json"

try {
    if (-not (Test-Path -Path $csvOutputFolder)) {
        New-Item -Path $csvOutputFolder -ItemType Directory | Out-Null
        Write-Host "Created output directory: $csvOutputFolder"
    }
    if (-not (Test-Path -Path $jsonOutputFolder)) {
        New-Item -Path $jsonOutputFolder -ItemType Directory | Out-Null
        Write-Host "Created output directory: $jsonOutputFolder"
    }
}
catch {
    Write-Error "Failed to create output directories: $_"
    exit 1
}

# Get all .evtx files in the specified folder
$evtxFiles = Get-ChildItem -Path $LogFolder -Filter "*.evtx" -File

if ($evtxFiles.Count -eq 0) {
    Write-Warning "No .evtx files found in '$LogFolder'."
    exit 0
}

# Process each .evtx file
foreach ($file in $evtxFiles) {
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $csvOutputFile = Join-Path -Path $csvOutputFolder -ChildPath "$fileName.csv"
    $jsonOutputFile = Join-Path -Path $jsonOutputFolder -ChildPath "$fileName.json"

    Write-Host "Processing file: $($file.FullName)"
    
    # Run EvtxECmd for CSV output
    try {
        $csvCommand = "& '$evtxCmdPath' -f '$($file.FullName)' --csv '$csvOutputFolder' --csvf '$csvOutputFile'"
        Invoke-Expression $csvCommand
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully created CSV: $csvOutputFile"
        } else {
            Write-Warning "EvtxECmd failed to process '$($file.FullName)' to CSV. Exit code: $LASTEXITCODE"
        }
    }
    catch {
        Write-Warning "Error processing '$($file.FullName)' to CSV: $_"
    }

    # Run EvtxECmd for JSON output
    try {
        $jsonCommand = "& '$evtxCmdPath' -f '$($file.FullName)' --json '$jsonOutputFolder' --jsonf '$jsonOutputFile'"
        Invoke-Expression $jsonCommand
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully created JSON: $jsonOutputFile"
        } else {
            Write-Warning "EvtxECmd failed to process '$($file.FullName)' to JSON. Exit code: $LASTEXITCODE"
        }
    }
    catch {
        Write-Warning "Error processing '$($file.FullName)' to JSON: $_"
    }
}

Write-Host "Processing complete. Parsed files are located in '$csvOutputFolder' and '$jsonOutputFolder'."