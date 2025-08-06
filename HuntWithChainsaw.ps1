# HuntWithChainsaw.ps1
# Description: Automates threat hunting using the Chainsaw tool on .evtx log files with default Sigma and Chainsaw rules.
# Requires a folder containing .evtx logs as input.
# Creates a 'chainsaw_txt' output folder for results saved as .txt files.
# Displays results in the console and saves them to .txt files.
# Uses a config.json file for Chainsaw executable path or accepts it via parameter/environment variable.

param (
    [Parameter(Mandatory=$true, HelpMessage="Path to folder containing .evtx log files")]
    [Alias("d")]
    [string]$LogFolder,
    [Parameter(Mandatory=$false, HelpMessage="Path to Chainsaw executable")]
    [Alias("c")]
    [string]$ChainsawPath = $env:CHAINSAW_PATH,
    [Parameter(Mandatory=$false, HelpMessage="Path to folder containing Sigma rules (defaults to 'sigma/rules' in Chainsaw directory)")]
    [Alias("sigma")]
    [string]$SigmaRulesPath,
    [Parameter(Mandatory=$false, HelpMessage="Path to folder containing Chainsaw rules (defaults to 'rules' in Chainsaw directory)")]
    [Alias("rule")]
    [string]$ChainsawRulesPath,
    [Parameter(Mandatory=$false, HelpMessage="Path to Sigma mapping file (defaults to 'mappings/sigma-event-logs-all.yml' in Chainsaw directory)")]
    [Alias("mapping")]
    [string]$MappingPath,
    [Parameter(Mandatory=$false, HelpMessage="Filter rules by severity level (e.g., informational, low, medium, high, critical)")]
    [ValidateSet("informational", "low", "medium", "high", "critical")]
    [string]$SeverityLevel
)

# If ChainsawPath is not provided via parameter or environment variable, try config.json
if (-not $ChainsawPath) {
    $configPath = Join-Path -Path $PSScriptRoot -ChildPath "config.json"
    if (Test-Path -Path $configPath -PathType Leaf) {
        try {
            $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
            $ChainsawPath = $config.ChainsawPath
        }
        catch {
            Write-Error "Failed to read or parse config.json: $_"
            exit 1
        }
    }
}

# Check if Chainsaw path is valid
if (-not $ChainsawPath -or -not (Test-Path -Path $ChainsawPath -PathType Leaf)) {
    Write-Error "Chainsaw executable not found. Please provide a valid path using -c, set the CHAINSAW_PATH environment variable, or ensure a valid config.json exists."
    exit 1
}

# Set default paths for Sigma rules, Chainsaw rules, and mapping file if not provided
$chainsawDir = Split-Path -Path $ChainsawPath -Parent
if (-not $SigmaRulesPath) {
    $SigmaRulesPath = Join-Path -Path $chainsawDir -ChildPath "sigma\rules"
}
if (-not $ChainsawRulesPath) {
    $ChainsawRulesPath = Join-Path -Path $chainsawDir -ChildPath "rules"
}
if (-not $MappingPath) {
    $MappingPath = Join-Path -Path $chainsawDir -ChildPath "mappings\sigma-event-logs-all.yml"
}

# Validate input folder
if (-not (Test-Path -Path $LogFolder -PathType Container)) {
    Write-Error "The specified log folder '$LogFolder' does not exist."
    exit 1
}

# Validate rules and mapping paths
if (-not (Test-Path -Path $SigmaRulesPath -PathType Container)) {
    Write-Error "Sigma rules folder '$SigmaRulesPath' does not exist."
    exit 1
}
if (-not (Test-Path -Path $ChainsawRulesPath -PathType Container)) {
    Write-Error "Chainsaw rules folder '$ChainsawRulesPath' does not exist."
    exit 1
}
if (-not (Test-Path -Path $MappingPath -PathType Leaf)) {
    Write-Error "Sigma mapping file '$MappingPath' does not exist."
    exit 1
}

# Create output directory for text files
$txtOutputFolder = Join-Path -Path $LogFolder -ChildPath "chainsaw"

try {
    if (-not (Test-Path -Path $txtOutputFolder)) {
        New-Item -Path $txtOutputFolder -ItemType Directory | Out-Null
        Write-Host "Created output directory: $txtOutputFolder"
    }
}
catch {
    Write-Error "Failed to create output directory: $_"
    exit 1
}

# Generate a timestamp for the output file name
$txtOutputFile = Join-Path -Path $txtOutputFolder -ChildPath "chainsaw_hunt.txt"

Write-Host "Processing log files in folder: $LogFolder with Chainsaw"

# Build Chainsaw hunt command for the entire folder
$command = "& '$ChainsawPath' hunt '$LogFolder' -s '$SigmaRulesPath' -r '$ChainsawRulesPath' --mapping '$MappingPath'"
$command_log = "& '$ChainsawPath' hunt '$LogFolder' -s '$SigmaRulesPath' -r '$ChainsawRulesPath' --mapping '$MappingPath'  --output '$txtOutputFile' -q"
$command_csv = "& '$ChainsawPath' hunt '$LogFolder' -s '$SigmaRulesPath' -r '$ChainsawRulesPath' --mapping '$MappingPath' --csv --output '$txtOutputFolder' -q"


# Add severity level filter if specified
if ($SeverityLevel) {
    $command += " --level '$SeverityLevel'"
}

# Run Chainsaw and capture output for display and saving to text file
try {
    Write-Host "Chainsaw Output for folder: $LogFolder"
    Write-Host "----------------------------------------"
    Invoke-Expression $command 
    Invoke-Expression $command_log
    Invoke-Expression $command_csv
    if ($LASTEXITCODE -eq 0) {
        Write-Host "----------------------------------------"
        Write-Host "Successfully saved output to: $txtOutputFile"
    } else {
        Write-Warning "Chainsaw failed to process logs in '$LogFolder'. Exit code: $LASTEXITCODE"
    }
}
catch {
    Write-Warning "Error processing logs in '$LogFolder' with Chainsaw: $_"
}

Write-Host "Chainsaw hunting complete. Results saved to '$txtOutputFile'."