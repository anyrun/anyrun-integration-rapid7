#region Constants and Configuration
# Windows-specific Feed Connector installer script
# Requires PowerShell 5.0+ and Windows Task Scheduler

# File and directory constants
$ENV_FILE = ".env"
$CONNECTOR_SCRIPT_NAME = "connector-anyrun-feed.ps1"
$TASK_NAME = "ANYRUN Feed Connector"
$INSTALL_DIR_NAME = "ANYRUN\FeedConnector"

# Default configuration values
$DEFAULT_FETCH_INTERVAL_MINUTES = 60
$MIN_FETCH_INTERVAL_MINUTES = 1

# Menu options
$MENU_INSTALL = "1"
$MENU_UPDATE = "2"
$MENU_UNINSTALL = "3"

# Logging modes
$LOGGING_CONSOLE = "console"
$LOGGING_EVENTLOG = "eventlog"

# EventLog constants
$EVENTLOG_SOURCE = "ANY.RUN Feed Connector"
$EVENTLOG_NAME = "Application"

#endregion

#region Utility Functions
# Functions for EventLog management, configuration loading, file operations and task management

<#
.SYNOPSIS
    Checks if the EventLog source exists
.DESCRIPTION
    Uses Get-EventLog to check if the specified source exists in Application log
.PARAMETER SourceName
    Name of the EventLog source to check
#>
function Test-EventLogSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceName
    )
    
    try {
        $eventLog = Get-EventLog -LogName $EVENTLOG_NAME -Source $SourceName -Newest 1 -ErrorAction SilentlyContinue
        if (!$eventLog) {
            Write-EventLog -LogName $EVENTLOG_NAME -Source $SourceName -EventId 1000 -Message "Checking EventLog accessiblity" -ErrorAction Stop
        }
        return $true
    } catch {
        return $false
    }
}

<#
.SYNOPSIS
    Creates EventLog source
.DESCRIPTION
    Creates a new EventLog source in the Application log
.PARAMETER SourceName
    Name of the EventLog source to create
#>
function New-EventLogSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceName
    )
    
    try {
        New-EventLog -LogName $EVENTLOG_NAME -Source $SourceName -ErrorAction Stop
        Write-Host "EventLog source '$SourceName' created successfully." -ForegroundColor Green
        return $true
    } catch {
        Write-Warning "Failed to create EventLog source: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Requests elevation to create EventLog source
.DESCRIPTION
    Starts elevated PowerShell process to create EventLog source and waits for completion
.PARAMETER SourceName
    Name of the EventLog source to create
#>
function Request-EventLogElevation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceName
    )
    
    Write-Host ""
    Write-Host "Administrator privileges are required to create EventLog source." -ForegroundColor Yellow
    Write-Host "Do you want to create EventLog source with administrator privileges? (y/n): " -NoNewline -ForegroundColor Cyan
    
    $response = Read-Host
    
    if ($response -eq "y" -or $response -eq "Y") {
        try {
            Write-Host "Creating EventLog source with elevated privileges..." -ForegroundColor Green
            
            # Create PowerShell command to create EventLog source
            $command = "Write-Host 'Creating EventLog source with elevated privileges...'; New-EventLog -LogName '$EVENTLOG_NAME' -Source '$SourceName' -ErrorAction Stop; Write-Host 'EventLog source created successfully.' -ForegroundColor Green;"
            
            # Start elevated PowerShell process and wait for completion
            $processArgs = [System.Diagnostics.ProcessStartInfo]::new()

            $processArgs.FileName = "powershell.exe"
            $processArgs.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command $command"
            $processArgs.Verb = "runas"
            $processArgs.UseShellExecute = $true
            
            $process = [System.Diagnostics.Process]::Start($processArgs)
            $process.WaitForExit()
            return $true
            
        } catch [System.ComponentModel.Win32Exception] {
            if ($_.Exception.NativeErrorCode -eq 1223) {
                # User cancelled UAC prompt
                Write-Host ""
                Write-Host "UAC prompt was cancelled." -ForegroundColor Yellow
                return $false
            } else {
                Write-Warning "Failed to create EventLog source: $($_.Exception.Message)"
                return $false
            }
        } catch {
            Write-Warning "Failed to create EventLog source: $($_.Exception.Message)"
            return $false
        }
    } else {
        Write-Host ""
        Write-Host "EventLog source creation cancelled." -ForegroundColor Yellow
        return $false
    }
}

<#
.SYNOPSIS
    Ensures EventLog source exists, creating it if necessary
.DESCRIPTION
    Checks if EventLog source exists, and creates it with appropriate privileges if needed
.PARAMETER SourceName
    Name of the EventLog source to ensure exists
#>
function Ensure-EventLogSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceName
    )
    
    Write-Host "Checking EventLog source..." -ForegroundColor Yellow
    
    # First check - does the source already exist?
    if (Test-EventLogSource -SourceName $SourceName) {
        Write-Host "EventLog source '$SourceName' already exists." -ForegroundColor Green
        return $true
    }
    
    Write-Host "EventLog source '$SourceName' does not exist." -ForegroundColor Yellow
    
    # Check if we have admin rights to create it
    $isAdmin = Test-IsAdministrator
    
    if ($isAdmin) {
        Write-Host "Creating EventLog source with current privileges..." -ForegroundColor Yellow
        return New-EventLogSource -SourceName $SourceName
    } else {
        # Request elevation to create the source
        $elevated = Request-EventLogElevation -SourceName $SourceName
        
        if ($elevated) {
            # Re-check if the source was created successfully
            Write-Host "Verifying EventLog source creation..." -ForegroundColor Yellow
            return Test-EventLogSource -SourceName $SourceName
        } else {
            return $false
        }
    }
}

<#
.SYNOPSIS
    Checks if the current PowerShell session is running with administrator privileges
.DESCRIPTION
    Uses Windows identity and principal classes to determine if the current user
    has administrator rights
#>
function Test-IsAdministrator {
    [CmdletBinding()]
    param()
    
    try {
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        Write-Warning "Could not determine administrator status: $($_.Exception.Message)"
        return $false
    }
}

# Functions for configuration loading, file operations and task management

<#
.SYNOPSIS
    Loads configuration from .env file with fallback to environment variables
.DESCRIPTION
    Reads .env file and returns a hashtable with settings.
    Ignores comments and empty lines. Compatible with PowerShell 5.0+
.PARAMETER EnvFile
    Path to environment variables file
#>
function Get-ConnectorConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvFile
    )
    
    $config = @{}
    
    if ([System.IO.File]::Exists($EnvFile)) {
        [System.IO.File]::ReadAllLines($EnvFile) | ForEach-Object {
        $match = [System.Text.RegularExpressions.Regex]::Match($_, '^([^#].*?)=(.*)$')
        if ($match.Success) {
            $config[$match.Groups[1].Value] = $match.Groups[2].Value
        }
    }
}

    return $config
}

<#
.SYNOPSIS
    Gets configuration value with fallback priority
.DESCRIPTION
    Searches for value in the following order:
    1. In the provided configuration
    2. In system environment variables
    3. Returns default value
.PARAMETER Name
    Variable name
.PARAMETER Config
    Configuration hashtable
.PARAMETER Default
    Default value
#>
function Get-ConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Config,
        $Default = $null
    )
    
    $value = $null
    if ($Config.ContainsKey($Name)) {
        $value = $Config[$Name]
    }
    if (!$value) {
        $value = [System.Environment]::GetEnvironmentVariable($Name)
    }
    if (!$value) {
        $value = $Default
    }
    
    return $value
}

<#
.SYNOPSIS
    Validates and converts fetch interval value
.DESCRIPTION
    Ensures the interval is a valid positive integer
.PARAMETER Value
    Value to validate
.PARAMETER MinValue
    Minimum allowed value
#>
function Test-FetchInterval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Value,
        [int]$MinValue = $MIN_FETCH_INTERVAL_MINUTES
    )
    
    $numericValue = $null
    
    if ($Value.GetType() -eq [System.String]) {
        try {
            $numericValue = [System.Int32]::Parse($Value)
        } catch {
            return $null
        }
    } elseif ($Value -is [int]) {
        $numericValue = $Value
    } else {
        return $null
    }
    
    if ($numericValue -ge $MinValue) {
        return $numericValue
    }
    
    return $null
}

<#
.SYNOPSIS
    Validates that required files exist
.DESCRIPTION
    Checks for the existence of the main connector script
.PARAMETER ScriptName
    Name of the connector script file
#>
function Test-RequiredFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptName
    )
    
    if (![System.IO.File]::Exists($ScriptName)) {
        Write-Error "$ScriptName not found in current directory"
        return $false
    }
    
    return $true
}

<#
.SYNOPSIS
    Creates Windows scheduled task for the connector
.DESCRIPTION
    Uses schtasks.exe to create a scheduled task that runs the connector
.PARAMETER TaskName
    Name of the scheduled task
.PARAMETER Command
    Command to execute
.PARAMETER IntervalMinutes
    Interval in minutes between task executions
#>
function New-ConnectorTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][int]$IntervalMinutes
    )
    
    try {
        $output = schtasks /create /tn $TaskName /tr $Command /sc minute /mo $IntervalMinutes /f 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create scheduled task: $output"
            return $false
        }
        return $true
    } catch {
        Write-Error "Error creating scheduled task: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Starts Windows scheduled task
.DESCRIPTION
    Uses schtasks.exe to immediately run the scheduled task
.PARAMETER TaskName
    Name of the scheduled task to start
#>
function Start-ConnectorTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TaskName
    )
    
    try {
        $output = schtasks /run /tn $TaskName 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to start scheduled task: $output"
            return $false
        }
        return $true
    } catch {
        Write-Warning "Error starting scheduled task: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Removes Windows scheduled task
.DESCRIPTION
    Uses schtasks.exe to delete the scheduled task
.PARAMETER TaskName
    Name of the scheduled task to remove
#>
function Remove-ConnectorTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TaskName
    )
    
    try {
        $output = schtasks /delete /tn $TaskName /f 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to delete scheduled task: $output"
            return $false
        }
        return $true
    } catch {
        Write-Warning "Error deleting scheduled task: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Copies connector files to installation directory
.DESCRIPTION
    Creates installation directory and copies required files
.PARAMETER SourceScript
    Source connector script path
.PARAMETER SourceEnv
    Source .env file path (optional)
.PARAMETER DestinationDir
    Destination installation directory
#>
function Copy-ConnectorFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceScript,
        [string]$SourceEnv,
        [Parameter(Mandatory)][string]$DestinationDir
    )
    
    try {
        # Create installation directory
        [System.IO.Directory]::CreateDirectory($DestinationDir) | Out-Null
        
        # Copy main script
        $destScript = Join-Path $DestinationDir (Split-Path $SourceScript -Leaf)
        [System.IO.File]::Copy($SourceScript, $destScript, $true)
        
        # Copy .env file if it exists
        if ($SourceEnv -and [System.IO.File]::Exists($SourceEnv)) {
            $destEnv = Join-Path $DestinationDir (Split-Path $SourceEnv -Leaf)
            [System.IO.File]::Copy($SourceEnv, $destEnv, $true)
            return $true
        }
        
        return $false  # .env file was not copied
    } catch {
        Write-Error "Error copying files: $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Script Initialization
# Load configuration and validate environment

Write-Host "ANY.RUN Feed Connector Installer" -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Green
Write-Host ""

# Load configuration from .env file
$config = Get-ConnectorConfig -EnvFile $ENV_FILE

# Get and validate fetch interval
$anyrunFeedFetchInterval = Get-ConfigValue -Name "ANYRUN_FEED_FETCH_INTERVAL" -Config $config -Default $DEFAULT_FETCH_INTERVAL_MINUTES
$anyrunFeedFetchInterval = Test-FetchInterval -Value $anyrunFeedFetchInterval

if (!$anyrunFeedFetchInterval) {
    Write-Error "ANYRUN_FEED_FETCH_INTERVAL is invalid or less than $MIN_FETCH_INTERVAL_MINUTES minutes"
    exit 1
}

# Validate Windows environment
$localAppData = [System.Environment]::GetEnvironmentVariable('LOCALAPPDATA')
if (!$localAppData -or ![System.IO.Directory]::Exists($localAppData)) {
    Write-Error "LOCALAPPDATA environment variable is invalid. Cannot install Feed Connector."
    exit 1
}

# Prepare installation paths
$installDir = Join-Path $localAppData $INSTALL_DIR_NAME
$scriptPath = Join-Path $installDir $CONNECTOR_SCRIPT_NAME

# Determine logging mode based on EventLog source availability
Write-Host "Determining optimal logging mode..." -ForegroundColor Yellow

# Try to ensure EventLog source exists
$eventLogAvailable = Ensure-EventLogSource -SourceName $EVENTLOG_SOURCE

# Set logging mode based on EventLog availability
if ($eventLogAvailable) {
    $loggingMode = $LOGGING_EVENTLOG
    Write-Host "EventLog source is available. Using EventLog logging." -ForegroundColor Green
} else {
    $loggingMode = $LOGGING_CONSOLE
    Write-Host "EventLog source is not available. Using console logging." -ForegroundColor Yellow
}

Write-Host ""

# Prepare task command with logging mode
$taskCommand = "cmd /c `'cd /d `"$installDir`" && powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" scheduled $loggingMode`'"

Write-Host "Configuration loaded successfully:" -ForegroundColor Yellow
Write-Host "  EventLog source available: $(if ($eventLogAvailable) { 'Yes' } else { 'No' })" -ForegroundColor Gray
Write-Host "  Logging mode: $loggingMode" -ForegroundColor Gray
Write-Host "  Fetch Interval: $anyrunFeedFetchInterval minutes" -ForegroundColor Gray
Write-Host "  Install Directory: $installDir" -ForegroundColor Gray
Write-Host ""

#endregion

#region Action Functions
# Individual functions for each installer action

<#
.SYNOPSIS
    Installs the Feed Connector
.DESCRIPTION
    Copies files, creates scheduled task, and starts the connector
#>
function Install-FeedConnector {
    Write-Host "Installing ANY.RUN Feed Connector..." -ForegroundColor Yellow
    
    # Validate required files exist
    if (!(Test-RequiredFiles -ScriptName $CONNECTOR_SCRIPT_NAME)) {
        return $false
    }
    
    try {
        # Copy files to installation directory
        $envCopied = Copy-ConnectorFiles -SourceScript $CONNECTOR_SCRIPT_NAME -SourceEnv $ENV_FILE -DestinationDir $installDir
        
        if (!$envCopied) {
            Write-Host ".env file not found. Connector will use System Environment Variables." -ForegroundColor Yellow
            Write-Host "Do you want to continue? (y/n): " -NoNewline -ForegroundColor Yellow
            $continue = Read-Host
            if ($continue -ne "y" -and $continue -ne "Y") {
                Write-Host "Installation cancelled." -ForegroundColor Red
                return $false
            }
        }
        
        # Create scheduled task
        if (!(New-ConnectorTask -TaskName $TASK_NAME -Command $taskCommand -IntervalMinutes $anyrunFeedFetchInterval)) {
            Write-Error "Failed to create scheduled task"
            return $false
        }
        
        # Start the task immediately
        if (Start-ConnectorTask -TaskName $TASK_NAME) {
            Write-Host "Feed Connector installed and started successfully!" -ForegroundColor Green
            Write-Host "Logging mode: $loggingMode" -ForegroundColor Gray
        } else {
            Write-Host "Feed Connector installed successfully, but failed to start immediately." -ForegroundColor Yellow
            Write-Host "Logging mode: $loggingMode" -ForegroundColor Gray
        }
        
        return $true
    } catch {
        Write-Error "Installation failed: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Updates the Feed Connector
.DESCRIPTION
    Updates configuration files and recreates scheduled task
#>
function Update-FeedConnector {
    Write-Host "Updating ANY.RUN Feed Connector..." -ForegroundColor Yellow
    
    try {
        # Update .env file if it exists
        if ([System.IO.File]::Exists($ENV_FILE)) {
            $envDest = Join-Path $installDir $ENV_FILE
            [System.IO.File]::Copy($ENV_FILE, $envDest, $true)
            Write-Host "Configuration file updated." -ForegroundColor Green
        }
        
        # Update connector script if it exists
        if ([System.IO.File]::Exists($CONNECTOR_SCRIPT_NAME)) {
            $scriptDest = Join-Path $installDir $CONNECTOR_SCRIPT_NAME
            [System.IO.File]::Copy($CONNECTOR_SCRIPT_NAME, $scriptDest, $true)
            Write-Host "Connector script updated." -ForegroundColor Green
        }
        
        # Recreate scheduled task with new interval
        if (!(New-ConnectorTask -TaskName $TASK_NAME -Command $taskCommand -IntervalMinutes $anyrunFeedFetchInterval)) {
            Write-Error "Failed to update scheduled task"
            return $false
        }
        
        # Start the updated task
        if (Start-ConnectorTask -TaskName $TASK_NAME) {
            Write-Host "Feed Connector updated and restarted successfully!" -ForegroundColor Green
            Write-Host "Logging mode: $loggingMode" -ForegroundColor Gray
        } else {
            Write-Host "Feed Connector updated successfully, but failed to restart immediately." -ForegroundColor Yellow
            Write-Host "Logging mode: $loggingMode" -ForegroundColor Gray
        }
        
        return $true
    } catch {
        Write-Error "Update failed: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Uninstalls the Feed Connector
.DESCRIPTION
    Removes scheduled task and deletes installation directory
#>
function Uninstall-FeedConnector {
    Write-Host "Uninstalling ANY.RUN Feed Connector..." -ForegroundColor Yellow
    
    try {
        # Remove scheduled task
        Remove-ConnectorTask -TaskName $TASK_NAME | Out-Null
        
        # Remove installation directory
        if ([System.IO.Directory]::Exists($installDir)) {
            [System.IO.Directory]::Delete($installDir, $true)
            Write-Host "Installation directory removed." -ForegroundColor Green
        }
        
        Write-Host "Feed Connector uninstalled successfully!" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Uninstallation failed: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Displays the main menu
.DESCRIPTION
    Shows available actions and prompts for user selection
#>
function Show-Menu {
    Write-Host "Please select an action:" -ForegroundColor Cyan
    Write-Host "" 
    Write-Host "  [$MENU_INSTALL] Install Feed Connector" -ForegroundColor White
    Write-Host "  [$MENU_UPDATE] Update Feed Connector" -ForegroundColor White
    Write-Host "  [$MENU_UNINSTALL] Uninstall Feed Connector" -ForegroundColor White
    Write-Host "  [Any other key] Exit" -ForegroundColor Gray
    Write-Host ""
    
    return Read-Host -Prompt "Enter your choice"
}

#endregion

#region Main Execution
# Main script logic

$action = Show-Menu

switch ($action) {
    $MENU_INSTALL {
        $success = Install-FeedConnector
        if ($success) {
            Write-Host ""
            Write-Host "Installation completed successfully!" -ForegroundColor Green
            Write-Host "The connector will run every $anyrunFeedFetchInterval minutes." -ForegroundColor Gray
        } else {
            Write-Host ""
            Write-Host "Installation failed. Please check the error messages above." -ForegroundColor Red
        exit 1
        }
    }
    
    $MENU_UPDATE {
        $success = Update-FeedConnector
        if ($success) {
            Write-Host ""
            Write-Host "Update completed successfully!" -ForegroundColor Green
            Write-Host "The connector will run every $anyrunFeedFetchInterval minutes." -ForegroundColor Gray
    } else {
            Write-Host ""
            Write-Host "Update failed. Please check the error messages above." -ForegroundColor Red
            exit 1
        }
    }
    
    $MENU_UNINSTALL {
        $success = Uninstall-FeedConnector
        if ($success) {
            Write-Host ""
            Write-Host "Uninstallation completed successfully!" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "Uninstallation failed. Please check the error messages above." -ForegroundColor Red
            exit 1
        }
    }
    
    default {
        Write-Host ""
        Write-Host "No action selected. Exiting..." -ForegroundColor Gray
        exit 0
    }
}

Write-Host ""
Write-Host "Press any key to continue..." -ForegroundColor Gray
$null = Read-Host

#endregion