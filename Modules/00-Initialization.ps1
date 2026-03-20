#region ===== SCRIPT INITIALIZATION =====
# Tool identity (override via defaults.json)
$script:ToolName = "RackStack"                     # Short name (used in filenames, scheduled tasks)
$script:ToolFullName = "RackStack"                 # Display name (used in UI banners, reports)
$script:SupportContact = ""                          # Support contact shown in agent installer messages (set via defaults.json)
$script:ConfigDirName = "rackstackconfig"           # Derived: config directory under USERPROFILE

# Company/Environment Variables (generic defaults - override via defaults.json)
$domain = ""                             # Default primary domain (empty = not configured)
$localadminaccountname = 'localadmin'    # Local administrator account name
$FullName = "Local Administrator"        # Full name for the new local admin account
$SwitchName = "LAN-SET"                  # Switch Embedded Team name
$ManagementName = "Management"           # Management NIC name made by SET
$BackupName = "Backup"                   # Backup NIC name made by SET
$logFilePath = $null                     # Path for log file (set to enable logging)
$emailAddress = $null                    # Email address for log notifications

# DNS Presets for quick configuration (custom presets merged from defaults.json)
$script:DNSPresets = [ordered]@{
    "Google DNS" = @("8.8.8.8", "8.8.4.4")
    "Cloudflare" = @("1.1.1.1", "1.0.0.1")
    "OpenDNS" = @("208.67.222.222", "208.67.220.220")
    "Quad9" = @("9.9.9.9", "149.112.112.112")
}

# Configuration constants
$script:MinPasswordLength = 14           # Minimum password length
$script:MaxRetryAttempts = 3             # Max retries for operations
$script:UpdateTimeoutSeconds = 300       # 5 minute timeout for updates
$script:CacheTTLMinutes = 10               # TTL for file listings and agent installer cache
$script:FeatureInstallTimeoutSeconds = 1800  # 30 minutes max for Windows Feature installs
$script:LargeFileDownloadTimeoutSeconds = 3600  # 1 hour for ISO/VHD downloads
$script:DefaultDownloadTimeoutSeconds = 1800    # 30 minutes for standard downloads
$script:MaxDownloadRetries = 3                      # Max retry attempts for large file downloads (>500MB)

# Centralized timeout configuration (seconds)
# These can be overridden via defaults.json "Timeouts" section
$script:Timeouts = @{
    CIMQuery            = 10      # Standard CIM/WMI queries
    CIMQuerySlow        = 15      # CIM queries on older/slower systems
    WMIQuery            = 15      # Legacy WMI queries
    iSCSIConnection     = 25      # iSCSI target connection
    SubnetSweep         = 30      # Per-batch network sweep
    DomainJoin          = 120     # Domain join operation
    WindowsUpdate       = 300     # Windows Update cycle
    FeatureInstall      = 1800    # Windows feature installation
    LargeFileDownload   = 3600    # Large file download
    VMCreation          = 60      # VM creation
    ClusterOperation    = 300     # Cluster formation/validation
    DCPromotion         = 600     # Domain controller promotion
    CredentialExpiry    = 1800    # Cached credential expiry (30 min)
    MenuCache           = 60      # Menu dashboard cache TTL
    HealthCheckCache    = 30      # Health check result cache TTL
}

# Configurable MSP agent installer (override via defaults.json AgentInstaller)
$script:AgentInstaller = @{
    ToolName        = "MSP"
    FolderName      = "Agents"
    FilePattern     = ".*\.exe$"
    ServiceName     = "*Agent*"
    InstallArgs     = "/s /norestart"
    InstallPaths    = @()
    SuccessExitCodes = @(0, 1641, 3010)
    TimeoutSeconds  = 300
}

# Additional agent installers (v1.8.0, override via defaults.json AdditionalAgents array)
$script:AdditionalAgents = @()

# Agent installer cache
$script:AgentInstallerCache = $null
$script:AgentInstallerCacheTime = $null

# Windows power plan GUIDs (centralized - used by SystemCheck, ConfigExport, EntryPoint, OfflineVHD)
$script:PowerPlanGUID = @{
    "High Performance" = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    "Balanced"         = "381b4222-f694-41f0-9685-ff5bb260df2e"
    "Power Saver"      = "a1841308-3541-4fab-bc81-f71556f20b4a"
}

# Default connectivity test target (used by SystemCheck, SET internet detection)
$script:DefaultConnectivityTarget = "8.8.8.8"

# Default temp directory for transcripts, reports, and exports (override via defaults.json TempPath)
$script:TempPath = "$env:SystemDrive\Temp"

# SAN target IP mappings - last octet suffixes paired with labels (override via defaults.json SANTargetMappings)
$script:SANTargetMappings = @(
    @{ Suffix = 10; Label = "A0" }
    @{ Suffix = 11; Label = "B1" }
    @{ Suffix = 12; Label = "B0" }
    @{ Suffix = 13; Label = "A1" }
    @{ Suffix = 14; Label = "A2" }
    @{ Suffix = 15; Label = "B3" }
    @{ Suffix = 16; Label = "B2" }
    @{ Suffix = 17; Label = "A3" }
)

# Custom SAN target pairings - defines A/B pairs and host-to-pair assignments (override via defaults.json SANTargetPairings)
# When set, this overrides the default Initialize-SANTargetPairs logic and Get-SANTargetsForHost retry order.
# A side = even suffixes, B side = odd suffixes by convention.
# CycleSize controls the modulo: host 5 maps the same as host 1, host 6 as host 2, etc.
$script:SANTargetPairings = $null

# Defender exclusion paths for Hyper-V hosts (override via defaults.json)
$script:DefenderExclusionPaths = @(
    "C:\ProgramData\Microsoft\Windows\Hyper-V"
    "C:\ProgramData\Microsoft\Windows\Hyper-V\Snapshots"
    "C:\Users\Public\Documents\Hyper-V\Virtual Hard Disks"
    "C:\ClusterStorage"
)
$script:DefenderCommonVMPaths = @()  # Populated dynamically by Update-DefenderVMPaths or Import-Defaults

# Windows Software Licensing application ID (centralized - used by HealthCheck, MenuDisplay, ConfigExport, HTMLReports)
$script:WindowsLicensingAppId = "55c92734-d682-4d71-983e-d6ec3f16059f"

# FileServer - Cloudflare Access-protected file server
# Override via defaults.json - empty BaseURL = cloud features disabled
$script:FileServer = @{
    StorageType    = "nginx"  # nginx (default), azure, static
    BaseURL        = ""
    ClientId       = ""
    ClientSecret   = ""
    AzureAccount   = ""
    AzureContainer = ""
    AzureSasToken  = ""
    ISOsFolder     = "ISOs"
    VHDsFolder     = "VirtualHardDrives"
    AgentFolder    = "Agents"
}

# Folder file cache - keyed by folder path, each entry has Files array and CacheTime
$script:FileCache = @{}

# Default storage paths for Hyper-V hosts (D: is default, user can change via Host Storage Setup)
$script:SelectedHostDrive = "D:"                      # Selected host data drive (updated by Initialize-HostStorage)
$script:HostVMStoragePath = "D:\Virtual Machines"     # Default VM storage on hosts
$script:HostISOPath = "D:\ISOs"                       # ISO storage on hosts
$script:ClusterISOPath = "C:\ClusterStorage\Volume1\ISOs"  # ISO storage on clusters
$script:VHDCachePath = "D:\Virtual Machines\_BaseImages"    # Cached sysprepped VHDs on hosts
$script:ClusterVHDCachePath = "C:\ClusterStorage\Volume1\_BaseImages"  # Cached VHDs on clusters
$script:StorageInitialized = $false                                    # Whether host storage has been initialized

# Storage backend type: iSCSI, FC, S2D, SMB3, NVMeoF, Local (override via defaults.json StorageBackendType)
$script:StorageBackendType = "iSCSI"

# Store script path at startup (MUST be before functions for Exit-Script to work)
$script:ScriptPath = $PSCommandPath
if (-not $script:ScriptPath) {
    # ps2exe compiled exe: $PSCommandPath is empty, use process path instead
    try { $script:ScriptPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch {}
}
if (-not $script:ModuleRoot) { $script:ModuleRoot = $PSScriptRoot }
# ps2exe: $PSScriptRoot may point to a temp extraction dir, not the EXE folder.
# Always prefer the EXE directory when running compiled (detected by empty $PSCommandPath).
if (-not $PSCommandPath -and $script:ScriptPath) {
    $script:ModuleRoot = [System.IO.Path]::GetDirectoryName($script:ScriptPath)
}
if (-not $script:ModuleRoot -and $script:ScriptPath) {
    $script:ModuleRoot = [System.IO.Path]::GetDirectoryName($script:ScriptPath)
}
$script:ScriptVersion = "1.85.3"
$script:ScriptStartTime = Get-Date

# CLI headless mode parameters (populated from param block in monolithic/exe)
# When -Action is specified, the tool runs that action and exits without interactive menus
$script:CLIAction   = if ($Action)  { $Action }  else { $null }
$script:CLIProfile  = if ($Tier)    { $Tier }    else { 'Standard' }
$script:CLIConfig   = if ($Config)  { $Config }  else { $null }
$script:CLISilent   = if ($Silent)  { [bool]$Silent } else { $false }
$script:HeadlessMode = if ($Action) { $true } else { $false }
$script:CLIOutputFormat = if ($OutputFormat) { $OutputFormat } else { 'Console' }
$script:CLIOutputFile = if ($OutputFile) { $OutputFile } else { $null }
$script:CLIVersion  = if ($Version) { [bool]$Version } else { $false }
$script:CLIListActions = if ($ListActions) { [bool]$ListActions } else { $false }
# -Quiet auto-enabled when -OutputFormat JSON to ensure clean machine-readable output
$script:CLIQuiet    = if ($Quiet -or $OutputFormat -eq 'JSON') { $true } else { $false }

# OS version detection (for feature compatibility)
# 2012/2012 R2 lack SET, Storage Replica, Defender PowerShell module
# 2008 R2 SP1 supported with WMF 5.1 installed (run Install-Prerequisites.ps1)
$script:OSBuildNumber = try { [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).CurrentBuildNumber } catch { try { [int](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).BuildNumber } catch { 0 } }
$script:IsServer2008R2 = $script:OSBuildNumber -eq 7601        # 6.1.7601 (SP1)
$script:IsServer2012 = $script:OSBuildNumber -eq 9200           # 6.2.9200
$script:IsServer2012R2 = $script:OSBuildNumber -eq 9600         # 6.3.9600
$script:IsPreServer2016 = $script:OSBuildNumber -lt 14393       # Any OS before Server 2016
$script:IsServer2016OrLater = $script:OSBuildNumber -ge 14393   # 10.0.14393+

# Enforce TLS 1.2 (pre-2016 defaults to TLS 1.0/1.1 which fails on modern HTTPS endpoints)
if ([Net.ServicePointManager]::SecurityProtocol -notmatch "Tls12") {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

# Initialize global flags (prevents undefined variable issues)
$global:RebootNeeded = $false
$global:DisabledAdminReboot = $false
$global:ReturnToMainMenu = $false  # Flag to signal "go straight to main menu"

# Auto-update: if true, automatically download and install updates on startup (override via defaults.json)
$script:AutoUpdate = $false

# Auto-update state (populated by Test-StartupUpdateCheck on launch)
$script:UpdateAvailable = $false
$script:LatestVersion = $null
$script:LatestRelease = $null
$script:UpdateCheckCompleted = $false        # True once a successful API check finishes
$script:UpdateCheckLastAttempt = $null       # Throttle retries to once per 60 seconds

# Track changes made during session for summary and undo
$script:SessionChanges = [System.Collections.Generic.List[object]]::new()
$script:UndoStack = [System.Collections.Generic.List[object]]::new()

# QoL Features - Favorites and History (v2.8.0)
$script:AppConfigDir = "$env:USERPROFILE\.$($script:ConfigDirName)"
$script:FavoritesPath = "$script:AppConfigDir\favorites.json"
$script:HistoryPath = "$script:AppConfigDir\history.json"
$script:SessionStatePath = "$script:AppConfigDir\session.json"
$script:DefaultsPath = "$script:ModuleRoot\defaults.json"
$script:CompanyDefaultsName = $null             # e.g., "acme" (loaded from acme.defaults.json)
$script:CompanyDefaultsPath = $null             # e.g., "C:\...\acme.defaults.json"
$script:Favorites = @()
$script:CommandHistory = @()
$script:MaxHistoryItems = 100
$script:iSCSISubnet = "172.16.1"
$script:CustomKMSKeys = @{}
$script:CustomAVMAKeys = @{}
$script:CustomVMTemplates = @{}
$script:CustomVMDefaults = @{}
$script:BuiltInVMTemplates = $null
$script:CustomRoleTemplates = @{}
$script:TimeZoneRegion = ""

# VM naming convention (override via defaults.json VMNaming)
$script:VMNaming = @{
    SiteId       = ""
    Pattern      = "{Site}-{Prefix}{Seq}"
    SiteIdSource = "hostname"
    SiteIdRegex  = "^(\d{3,6})-"
}

# Color theme configuration (change theme here)
# Available themes: Default, Dark, Light, Matrix, Ocean
$script:ColorTheme = "Default"

# Color themes
$script:ColorThemes = @{
    "Default" = @{
        Success  = 'Green'
        Warning  = 'Yellow'
        Error    = 'Red'
        Info     = 'Cyan'
        Debug    = 'DarkGray'
        Critical = 'Magenta'
        Verbose  = 'White'
    }
    "Dark" = @{
        Success  = 'DarkGreen'
        Warning  = 'DarkYellow'
        Error    = 'DarkRed'
        Info     = 'DarkCyan'
        Debug    = 'DarkGray'
        Critical = 'DarkMagenta'
        Verbose  = 'Gray'
    }
    "Light" = @{
        Success  = 'Green'
        Warning  = 'Yellow'
        Error    = 'Red'
        Info     = 'Blue'
        Debug    = 'Gray'
        Critical = 'Magenta'
        Verbose  = 'Black'
    }
    "Matrix" = @{
        Success  = 'Green'
        Warning  = 'DarkGreen'
        Error    = 'Red'
        Info     = 'Green'
        Debug    = 'DarkGreen'
        Critical = 'Green'
        Verbose  = 'DarkGreen'
    }
    "Ocean" = @{
        Success  = 'Cyan'
        Warning  = 'Yellow'
        Error    = 'Red'
        Info     = 'Blue'
        Debug    = 'DarkCyan'
        Critical = 'Magenta'
        Verbose  = 'White'
    }
}
#endregion