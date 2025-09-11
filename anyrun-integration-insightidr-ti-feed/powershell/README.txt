ANY.RUN Feed Connector
======================

DESCRIPTION
-----------
The ANY.RUN Feed Connector is a PowerShell-based solution that automatically 
synchronizes threat indicators from ANY.RUN TAXII feeds to Rapid7 InsightIDR 
threat feeds. The connector supports both manual and scheduled execution modes 
with flexible logging options.

COMPONENTS
----------
1. connector-anyrun-feed.ps1      - Main connector script
2. ConfigureFeedConnector.ps1     - Windows installer/configuration script
3. .env                          - Configuration file (optional)

SYSTEM REQUIREMENTS
-------------------
- Windows OS (for scheduled execution)
- PowerShell 5.0 or later (PowerShell 7+ supported)
- Linux/macOS supported for manual execution
- Network access to ANY.RUN and Rapid7 APIs

CONFIGURATION
-------------
Create a .env file in the same directory as the scripts with the following variables:

    RAPID7_API_KEY=your-rapid7-api-key-here
    RAPID7_HOST=your-rapid7-instance.rapid7.com
    THREAT_FEED_ACCESS_KEY=your-threat-feed-access-key
    ANYRUN_BASIC_TOKEN=your-anyrun-token-here
    ANYRUN_FEED_FETCH_DEPTH=7
    ANYRUN_FEED_FETCH_INTERVAL=60

Alternatively, set these as system environment variables.

MANUAL EXECUTION
----------------
Run the connector script directly with PowerShell:

Windows:
    powershell.exe -File "connector-anyrun-feed.ps1" [mode] [logging]

Linux/macOS:
    pwsh ./connector-anyrun-feed.ps1 [mode] [logging]

EXECUTION MODES
---------------
infinite  - Runs continuously, fetching indicators at specified intervals
scheduled - Runs once and exits (for use with task schedulers)

LOGGING MODES
-------------
console   - Log to console output (default for infinite mode)
eventlog  - Log to Windows Event Log (default for scheduled mode, requires admin)

EXAMPLES
--------
Run once with console logging:
    powershell.exe -File "connector-anyrun-feed.ps1" scheduled console

Run continuously with default settings:
    powershell.exe -File "connector-anyrun-feed.ps1"

Run continuously with explicit console logging:
    powershell.exe -File "connector-anyrun-feed.ps1" infinite console

WINDOWS INSTALLATION
--------------------
For automated scheduled execution on Windows, use the installer:

1. Run PowerShell as Administrator (recommended for EventLog support)
2. Execute: powershell.exe -File "ConfigureFeedConnector.ps1"
3. Choose option [1] Install Feed Connector
4. Follow the prompts

The installer will:
- Check for administrator privileges
- Create EventLog source if possible (requires admin rights)
- Copy files to %LOCALAPPDATA%\ANYRUN\FeedConnector\
- Create a Windows scheduled task
- Start the connector automatically

INSTALLER OPTIONS
-----------------
[1] Install Feed Connector    - First-time installation
[2] Update Feed Connector     - Update existing installation  
[3] Uninstall Feed Connector  - Remove connector and scheduled task

EVENTLOG NOTES
--------------
- EventLog logging requires the "ANY.RUN Feed Connector" source to exist
- The installer will attempt to create this source with admin privileges
- If admin rights are unavailable, console logging will be used instead
- EventLog entries appear in Windows Application Log

TROUBLESHOOTING
---------------
1. Check configuration variables in .env file or environment
2. Verify network connectivity to ANY.RUN and Rapid7 APIs
3. Ensure API keys and tokens are valid and have proper permissions
4. For EventLog issues, run installer as Administrator
5. Check Windows Event Log for detailed error messages

SECURITY CONSIDERATIONS
-----------------------
- Store API keys securely in .env file or encrypted environment variables
- Use least-privilege accounts for scheduled execution
- Regularly rotate API keys and tokens
- Monitor logs for suspicious activity

API DOCUMENTATION
-----------------
ANY.RUN TAXII API: https://any.run/api-documentation/
Rapid7 API: https://docs.rapid7.com/insightidr/

SUPPORT
-------
For issues and feature requests, please contact your system administrator
or refer to the API documentation for the respective services.

VERSION COMPATIBILITY
---------------------
- PowerShell 5.0+: Full support on Windows
- PowerShell 7.0+: Cross-platform support
- Windows: Full support including EventLog
- Linux/macOS: Manual execution only

FILE STRUCTURE
--------------
project/
├── connector-anyrun-feed.ps1      # Main connector script
├── ConfigureFeedConnector.ps1     # Windows installer
├── .env                           # Configuration file
└── README.txt                     # This documentation

