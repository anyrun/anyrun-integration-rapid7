#region Constants and Configuration
# Environment variables file name
$ENV_FILE = ".env"

# ANY.RUN TAXII collections - identifiers for different indicator types
$TAXII_FULL = "3dce855a-c044-5d49-9334-533c24678c5a"      # Full collection
$TAXII_IP = "55cda200-e261-5908-b910-f0e18909ef3d"        # IP addresses
$TAXII_DOMAIN = "2e0aa90a-5526-5a43-84ad-3db6f4549a09"    # Domains
$TAXII_URL = "05bfa343-e79f-57ec-8677-3122ca33d352"       # URL addresses

# Date format for TAXII API (ISO 8601 with milliseconds)
$TAXII_DATE_FORMAT = "yyyy-MM-ddTHH:mm:ss.fffZ"

# Mapping of indicator types to TAXII collections
$TAXII_COLLECTIONS = @{
    "full" = $TAXII_FULL
    "ip" = $TAXII_IP
    "domain" = $TAXII_DOMAIN
    "url" = $TAXII_URL
}

# Base URL for ANY.RUN TAXII API
$TAXII_API_URL = "https://api.any.run/v1/feeds/taxii2/api1/collections"

# Indicator types for processing
$INDICATOR_TYPES = @("ip", "url", "domain")

$RUN_MODES = @("infinite", "scheduled")
$DEFAULT_RUN_MODE = "infinite"
$DEFAULT_LOGGING_MODE = "console"

# Default values
$DEFAULT_FETCH_DEPTH_DAYS = "7"      # Indicator search depth in days
$DEFAULT_FETCH_INTERVAL_MINUTES = "60"   # Interval between requests in minutes
$MAX_OBJECTS_PER_REQUEST = "5000"    # Maximum objects per request

# Global variable for logging mode
$script:LoggingMode = $DEFAULT_LOGGING_MODE

#endregion

#region Utility Functions
# Functions for logging, configuration and response processing

<#
.SYNOPSIS
    Writes messages to log (console or Event Log)
.DESCRIPTION
    Depending on the global logging mode, writes messages to console or Windows Event Log.
    Supports cross-platform operation.
    Uses the global variable $script:LoggingMode.
.PARAMETER Message
    Message text for logging
.PARAMETER EntryType
    Message type (Information/Warning/Error)
.PARAMETER EventId
    Event identifier for Event Log
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Information','Warning','Error')]
        [string]$EntryType = 'Information',
        [int]$EventId = 1000
    )

    # Use global variable to determine logging mode
    if ($script:LoggingMode -ne "eventlog") {
        if ($entryType -eq "Error") {
            Write-Error "$([System.DateTime]::UtcNow) | ERROR | $Message"
        } elseif ($entryType -eq "Warning") {
            Write-Warning "$([System.DateTime]::UtcNow) | WARNING | $Message"
        } else {
            Write-Host "$([System.DateTime]::UtcNow) | INFO | $Message"
        }
        return
    }
    try {
        if (-not (Get-EventLog -LogName Application -Source "ANY.RUN Feed Connector" -ErrorAction SilentlyContinue)) {
            New-EventLog -LogName Application -Source "ANY.RUN Feed Connector" | Out-Null
        }
        Write-EventLog -LogName Application -Source "ANY.RUN Feed Connector" -EntryType $EntryType -EventId $EventId -Message $Message
    } catch {
        if (Get-Command eventcreate -ErrorAction SilentlyContinue) {
            $level = switch ($EntryType) {
                'Information' { 'INFORMATION' }
                'Warning'     { 'WARNING' }
                'Error'       { 'ERROR' }
            }
            eventcreate /l APPLICATION /so "ANY.RUN Feed Connector" /t $level /id $EventId /d $Message | Out-Null
        }
    }
}

<#
.SYNOPSIS
    Loads configuration from .env file
.DESCRIPTION
    Reads .env file and returns a hashtable with settings.
    Ignores comments and empty lines.
.PARAMETER EnvFile
    Path to environment variables file
#>
function Get-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvFile
    )
    
    
    if ([System.IO.File]::Exists($EnvFile)) {
        $config = @{}
        [System.IO.File]::ReadAllLines($EnvFile) | ForEach-Object {
            $match = [System.Text.RegularExpressions.Regex]::Match($_, '^([^#].*?)=(.*)$')
            if ($match.Success) {
                $config[$match.Groups[1].Value] = $match.Groups[2].Value
            }
        }
        return $config
    }
    return $null
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
        [string]$Default = $null
    )
    $value = $null
    if ($Config) {
        $value = $Config[$Name]
    }
    if (!($value)) {
        $value = [System.Environment]::GetEnvironmentVariable($Name)
    }
    if (!($value)) {
        $value = $Default
    }
    return $value
}

<#
.SYNOPSIS
    Parses JSON response from web request
.DESCRIPTION
    Handles different types of response content and converts to JSON.
    Supports both string content and byte arrays.
.PARAMETER Response
    Web request response object
#>
function Get-JsonResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Microsoft.PowerShell.Commands.WebResponseObject]$Response
    )
    if ($response.Content.GetType() -eq [System.String]) {
        $responseContent = $response.Content | ConvertFrom-Json
    } else {
        $responseContent = [System.Text.Encoding]::UTF8.GetString($response.Content) | ConvertFrom-Json
    } 
    return $responseContent
}

<#
.SYNOPSIS
    Validates Rapid7 API key format
.DESCRIPTION
    Checks if the string matches UUID format
.PARAMETER ApiKey
    API key to validate
#>
function Test-Rapid7ApiKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApiKey
    )
    
    return [System.Text.RegularExpressions.Regex]::IsMatch($ApiKey, '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$')
}

<#
.SYNOPSIS
    Validates and processes Rapid7 host URL
.DESCRIPTION
    Cleans and normalizes URL, adds HTTPS if necessary
.PARAMETER HostUrl
    Host URL to process
#>
function Format-Rapid7Host {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HostUrl
    )
    
    $normalizedHost = $HostUrl.TrimEnd('/')
    if (!$normalizedHost.StartsWith('http')) {
        $normalizedHost = "https://$normalizedHost"
    }
    
    if ([System.Uri]::IsWellFormedUriString($normalizedHost, [System.UriKind]::Absolute)) {
        return $normalizedHost
    }
    return $null
}

<#
.SYNOPSIS
    Validates and processes ANY.RUN token
.DESCRIPTION
    Determines token type (Basic or API-Key) and validates its format
.PARAMETER Token
    ANY.RUN token to process
#>
function Get-AnyRunAuthString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Token
    )
    
    # Check if token already contains "Basic " prefix
    if ($Token.StartsWith('Basic ')) {
        $basicToken = $Token.Substring(6)
        try {
            [System.Convert]::FromBase64String($basicToken) | Out-Null
            return $Token
        } catch {
            throw "Invalid Basic token format"
        }
    }
    
    # Check if token contains "Api-Key " prefix
    if ($Token.ToLower().StartsWith('api-key ')) {
        $apiKey = $Token.Substring(8)
        if (-not $apiKey) {
            throw "Invalid API key format"
        }
        return $Token
    }
    
    # Try to determine token type automatically
    try {
        $decodedToken = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Token))
        if ($decodedToken.Contains(':')) {
            return "Basic $Token"
        } else {
            return "Api-Key $Token"
        }
    } catch {
        # If unable to decode as Base64, treat as API key
        return "Api-Key $Token"
    }
}

<#
.SYNOPSIS
    Validates numeric configuration value
.DESCRIPTION
    Converts string value to number and validates its correctness
.PARAMETER Value
    Value to validate
.PARAMETER MinValue
    Minimum allowed value
#>
function Test-NumericConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Value,
        [int]$MinValue = 1
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
    Gets indicators from ANY.RUN TAXII API for specific type
.DESCRIPTION
    Performs paginated requests to TAXII API to retrieve all indicators for the specified period.
    Handles pagination automatically.
.PARAMETER IndicatorType
    Indicator type (ip, domain, url)
.PARAMETER ModifiedAfter
    Date in TAXII format, after which to search for indicators
.PARAMETER Headers
    Headers for ANY.RUN authentication
#>
function Get-AnyRunIndicators {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$IndicatorType,
        [Parameter(Mandatory)][string]$ModifiedAfter,
        [Parameter(Mandatory)][hashtable]$Headers
    )
    
    $collection_id = $TAXII_COLLECTIONS[$IndicatorType]
    if (-not $collection_id) {
        Write-Log -Message "[ANY.RUN] Unknown indicator type: $IndicatorType" -EntryType "Error"
        return @()
    }
    
    $params = @{
        "match[type]"="indicator"
        "match[version]"="all"
        "match[spec_version]"="2.1"
        "match[revoked]"="false"
        "modified_after"=$ModifiedAfter
        "limit"=$MAX_OBJECTS_PER_REQUEST
    }
    
    $results = @()
    $request_url = "$TAXII_API_URL/$collection_id/objects"
    
    do {
        try {
            $response = Invoke-WebRequest -Uri $request_url -Headers $Headers -Method Get -Body $params -UseBasicParsing
            $responseContent = Get-JsonResponse -Response $response
            
            # Extract indicators from patterns
            $indicators = $responseContent.objects | ForEach-Object { $_.pattern.Split("'")[1] }
            $results += $indicators
            
            $params["next"] = $responseContent.next
        } catch {
            Write-Log -Message "[ANY.RUN] Error fetching $IndicatorType indicators: $($_.Exception.Message)" -EntryType "Error"
            break
        }
    } while ($responseContent.next)

    $results = $results | Select-Object -Unique
    
    if ($results.Count -gt 0) {
        Write-Log -Message "[ANY.RUN] Found $($results.Count) $($IndicatorType.ToUpper()) indicators."
    } else {
        Write-Log -Message "[ANY.RUN] $($IndicatorType.ToUpper()) type indicators not found." -EntryType "Warning"
    }
    
    return $results
}

<#
.SYNOPSIS
    Sends indicators to Rapid7 Threat Feed
.DESCRIPTION
    Forms JSON payload and sends all collected indicators.
.PARAMETER Indicators
    Hashtable with indicators by types
.PARAMETER Url
    URL for sending to Rapid7
.PARAMETER Headers
    Headers for Rapid7 authentication
#>
function Send-IndicatorsToRapid7 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Indicators,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][hashtable]$Headers
    )
    
    try {
        $payload = @{
            "ips" = $Indicators["ip"]
            "domain_names" = $Indicators["domain"]
            "urls" = $Indicators["url"]
        } | ConvertTo-Json -Compress -Depth 100
        
        $response = Invoke-WebRequest -Uri $Url -Headers $Headers -Method Post -Body $payload -ContentType "application/json" -UseBasicParsing
        $responseContent = Get-JsonResponse -Response $response
        
        if ($response.StatusCode -eq [System.Net.HttpStatusCode]::OK) {
            Write-Log -Message "[Rapid7 API] Successfully loaded $($responseContent.threat.indicator_count) indicators."
            return $true
        } else {
            Write-Log -Message "[Rapid7 API] $($responseContent.message). Correlation ID: $($responseContent.correlation_id). Status code: $([int]$response.StatusCode)." -EntryType "Error"
            return $false
        }
    } catch {
        Write-Log -Message "[Rapid7 API] Error sending indicators: $($_.Exception.Message)" -EntryType "Error"
        return $false
    }
}

<#
.SYNOPSIS
    Performs one indicator synchronization cycle
.DESCRIPTION
    Main script logic: fetching indicators and sending to Rapid7
.PARAMETER FetchDepthDays
    Number of days back to search for indicators
.PARAMETER AnyRunHeaders
    Headers for ANY.RUN API
.PARAMETER Rapid7Url
    URL for Rapid7 API
.PARAMETER Rapid7Headers
    Headers for Rapid7 API
#>
function Invoke-IndicatorSync {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$FetchDepthDays,
        [Parameter(Mandatory)][hashtable]$AnyRunHeaders,
        [Parameter(Mandatory)][string]$Rapid7Url,
        [Parameter(Mandatory)][hashtable]$Rapid7Headers
    )
    
    Write-Log -Message "[ANY.RUN] Starting indicator enrichment process."
    
    # Calculate date for filtering
    $modified_after = [System.DateTime]::UtcNow.AddDays(-$FetchDepthDays).ToString($TAXII_DATE_FORMAT)
    
    # Collect indicators for all types
    $indicators = @{}
    foreach ($indicator_type in $INDICATOR_TYPES) {
        $indicators[$indicator_type] = Get-AnyRunIndicators -IndicatorType $indicator_type -ModifiedAfter $modified_after -Headers $AnyRunHeaders
    }
    
    # Send to Rapid7
    $success = Send-IndicatorsToRapid7 -Indicators $indicators -Url $Rapid7Url -Headers $Rapid7Headers
    
    if ($success) {
        Write-Log -Message "[ANY.RUN] Indicator enrichment completed successfully."
    } else {
        Write-Log -Message "[ANY.RUN] Indicator enrichment completed with errors." -EntryType "Warning"
    }
    
}

#endregion

#region Load environment variables and check run mode

# Parse command line arguments
if ($args.Length -gt 0) {
    $mode = $args[0]
    if (-not ($RUN_MODES -contains $mode)) {
        Write-Log -Message "Invalid mode: $mode. Valid modes are: ($($RUN_MODES -join ', '))" -EntryType "Error"
        exit 1
    }
    
    # Check for logging mode parameter (second argument)
    if ($args.Length -gt 1) {
        $requestedLoggingMode = $args[1]
        if ($requestedLoggingMode -eq "console" -or $requestedLoggingMode -eq "eventlog") {
            $script:LoggingMode = $requestedLoggingMode
        } else {
            Write-Log -Message "Invalid logging mode: $requestedLoggingMode. Valid modes are: console, eventlog" -EntryType "Warning"
            $script:LoggingMode = $DEFAULT_LOGGING_MODE
        }
    } else {
        # Set default logging mode based on run mode
        if ($mode -eq "infinite") {
            $script:LoggingMode = $DEFAULT_LOGGING_MODE
        } elseif ($mode -eq "scheduled") {
            $script:LoggingMode = "eventlog"  # Default for scheduled mode
        }
    }
} else {
    $mode = $DEFAULT_RUN_MODE
    $script:LoggingMode = $DEFAULT_LOGGING_MODE
}

Write-Log -Message "Script started in mode: $mode (logging: $script:LoggingMode)"

$config = Get-Config -EnvFile $ENV_FILE
if (!$config) {
    Write-Log -Message ".env file not found, using System Environment Variables" -EntryType "Warning"
}

$rapid7Host = Get-ConfigValue -Name "RAPID7_HOST" -Config $config

# Rapid7 host processing and normalization
$rapid7Host = Format-Rapid7Host -HostUrl $rapid7Host
if (!$rapid7Host) {
    Write-Log -Message "RAPID7_HOST not found in environment file or environment variables, or URL format is invalid" -EntryType "Error"
    exit 1
}

$rapid7ApiKey = Get-ConfigValue -Name "RAPID7_API_KEY" -Config $config

if (!$rapid7ApiKey) {
    Write-Log -Message "RAPID7_API_KEY not found in environment file or environment variables" -EntryType "Error"
    exit 1
} elseif (-not (Test-Rapid7ApiKey -ApiKey $rapid7ApiKey)) {
    Write-Log -Message "RAPID7_API_KEY is not a valid API key format" -EntryType "Error"
    exit 1
}

$rapid7ThreatFeedAccessKey = Get-ConfigValue -Name "THREAT_FEED_ACCESS_KEY" -Config $config

if (!$rapid7ThreatFeedAccessKey) {
    Write-Log -Message "THREAT_FEED_ACCESS_KEY not found in environment file or environment variables" -EntryType "Error"
    exit 1
} elseif (-not (Test-Rapid7ApiKey -ApiKey $rapid7ThreatFeedAccessKey)) {
    Write-Log -Message "THREAT_FEED_ACCESS_KEY is not a valid API key format" -EntryType "Error"
    exit 1
}

# ANY.RUN token processing
$anyrunToken = Get-ConfigValue -Name "ANYRUN_BASIC_TOKEN" -Config $config
if (!$anyrunToken) {
    Write-Log -Message "ANYRUN_BASIC_TOKEN not found in environment file or environment variables" -EntryType "Error"
    exit 1
}

try {
    $authStr = Get-AnyRunAuthString -Token $anyrunToken
} catch {
    Write-Log -Message "ANYRUN_BASIC_TOKEN format is invalid: $($_.Exception.Message)" -EntryType "Error"
    exit 1
}


$anyrunFeedFetchInterval = Get-ConfigValue -Name "ANYRUN_FEED_FETCH_INTERVAL" -Config $config -Default $DEFAULT_FETCH_INTERVAL_MINUTES
$anyrunFeedFetchInterval = Test-NumericConfigValue -Value $anyrunFeedFetchInterval -MinValue 1

if (!$anyrunFeedFetchInterval) {
    Write-Log -Message "ANYRUN_FEED_FETCH_INTERVAL is invalid or less than 1" -EntryType "Error"
    exit 1
}

$anyrunFeedFetchDepth = Get-ConfigValue -Name "ANYRUN_FEED_FETCH_DEPTH" -Config $config -Default $DEFAULT_FETCH_DEPTH_DAYS
$anyrunFeedFetchDepth = Test-NumericConfigValue -Value $anyrunFeedFetchDepth -MinValue 1

if (!$anyrunFeedFetchDepth) {
    Write-Log -Message "ANYRUN_FEED_FETCH_DEPTH is invalid or less than 1" -EntryType "Error"
    exit 1
}

$rapid7Url = "$rapid7Host/idr/v1/customthreats/key/$rapid7ThreatFeedAccessKey/indicators/replace?format=json"

$rapid7_headers = @{
    "X-Api-Key" = $rapid7ApiKey
    "Content-Type" = "application/json"
}

$anyrun_headers = @{
    "Authorization" = $authStr
    "Content-Type" = "application/json"
    "x-anyrun-connector" = "R7_insightIDR:1.0.0"
}

#endregion

#region Main Execution Loop

do {
    # Perform one indicator synchronization cycle
    Invoke-IndicatorSync -FetchDepthDays $anyrunFeedFetchDepth -AnyRunHeaders $anyrun_headers -Rapid7Url $rapid7Url -Rapid7Headers $rapid7_headers
    
    # In infinite mode, wait for the specified interval
    if ($mode -eq "infinite") {
        Write-Log -Message "[ANY.RUN] Next synchronization will start in $anyrunFeedFetchInterval minutes."
        Start-Sleep -Seconds ($anyrunFeedFetchInterval * 60)
    }
} while ($mode -eq "infinite")

#endregion