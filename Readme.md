# Blue Toys

## CAUTION

- **I vibe coded this project. Use at your own risk**

## Overview

Blue Toys is a collection of custom PowerShell scripts designed to automate and streamline Blue Team tasks, focusing on the analysis and extraction of data from Windows Event Log (.evtx) files. These scripts assist security analysts in incident response, log parsing, and PowerShell script reconstruction, particularly for investigating PowerShell-related activities.

### Included Scripts

- **ParseEvtxLogs.ps1**: Parses .evtx files using `EvtxECmd` to produce CSV and JSON outputs in separate folders.
- **ExtractPowerShellScripts.ps1**: Extracts and reconstructs PowerShell scripts from event IDs 4103, 4104, and 4105, with options to save as .ps1 or .txt and include context metadata.
- **run.bat**: A batch file to simplify running the PowerShell scripts with `EvtxECmd` path configuration.

## Prerequisites

- Eric Zimmerman's Tools
- PowerShell 5.1 or later
- Administrative Privileges

## Installation

1. **Clone or Download the Repository**:
2. **Install EvtxECmd**:
   - Download Eric Zimmerman's Tools
   - Update the `config.json` file with the path to `EvtxECmd.exe`, or set the `EVXTECMD_PATH` environment variable.

## Usage

### ParseEvtxLogs.ps1

Parses .evtx files into CSV and JSON formats using `EvtxECmd`.

```powershell
.\ParseEvtxLogs.ps1 -LogFolder <path_to_folder_with_evtx_files> [-EvtxCmdPath <path_to_EvtxECmd.exe>]
```

- **Output**: Creates `parsed_csv` and `parsed_json` folders in the specified log folder, containing CSV and JSON files for each .evtx file.
- **Example**:

  ```powershell
  .\ParseEvtxLogs.ps1 -LogFolder "C:\Logs" -EvtxCmdPath "D:\Tool\EZ\net9\EvtxeCmd\EvtxECmd.exe"
  ```

### ExtractPowerShellScripts.ps1

Enhanced script to extract PowerShell scripts from event IDs 4103, 4104, and 4105, with options for .txt or .ps1 output.

```powershell
.\ExtractPowerShellScripts.ps1 -EvtxPath <path_to_evtx_file> [-OutputFolder <output_directory>] [-SaveAsPS1]
```

- **Output**: Saves scripts as .txt (default) or .ps1 files in the specified or default (`out`) folder, including metadata like execution time and context.
- **Example**:

  ```powershell
  .\ExtractPowerShellScripts.ps1 -EvtxPath "C:\Logs\PowerShell.evtx" -OutputFolder "C:\Scripts" -SaveAsPS1
  ```

### HuntWithChainsaw.ps1

Automates threat hunting on log files (e.g., .evtx, .json) in a folder using the Chainsaw tool with default Sigma and Chainsaw rules.

```powershell
.\HuntWithChainsaw.ps1 -p <path_to_folder_with_log_files> [-c <path_to_chainsaw.exe>] [-s <path_to_sigma_rules>] [-r <path_to_chainsaw_rules>] [-m <path_to_sigma_mapping>] [-SeverityLevel <informational|low|medium|high|critical>]
```

- **Output**: Saves results to a `.txt` file in the `chainsaw` folder within the specified log folder and displays them in the console in a log-like format.
- **Example**:

  ```powershell
  .\HuntWithChainsaw.ps1 -p "C:\Logs" -c "D:\Tools\chainsaw.exe" -SeverityLevel critical
  ```

### run.bat

Simplifies running the scripts by setting the `EVXTECMD_PATH` environment variable and bypassing PowerShell execution policy.

```batch
run.bat <path_to_ps1_file> [parameters...]
```

- **Example**:

  ```batch
  run.bat ExtractPowerShellScripts.ps1 -EvtxPath "C:\Logs\PowerShell.evtx" -SaveAsPS1
  ```
