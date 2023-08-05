<#
.SYNOPSIS
    Initializes the OSDCloud startnet environment.

.DESCRIPTION
    This function initializes the OSDCloud startnet environment by performing the following tasks:
    - Creates a log path if it does not already exist.
    - Copies OSDCloud config startup scripts to the mounted WinPE.
    - Initializes a splash screen if a SPLASH.JSON file is found in OSDCloud\Config.
    - Initializes hardware devices.
    - Initializes wireless network (optional).
    - Initializes network connections.
    - Updates PowerShell modules.

.PARAMETER WirelessConnect
    Specifies whether to connect to a wireless network. If this switch is specified, the function will attempt to connect to a wireless network using the Start-WinREWiFi function.

.EXAMPLE
    Initialize-OSDCloudStartnet -WirelessConnect
    Initializes the OSDCloud startnet environment and attempts to connect to a wireless network.
#>
function Initialize-OSDCloudStartnet {
    [CmdletBinding()]
    param (
        [System.Management.Automation.SwitchParameter]
        $WirelessConnect
    )
    # Make sure we are in WinPE
    if ($env:SystemDrive -eq 'X:') {
        $StartTime = Get-Date
        Write-Host -ForegroundColor Gray "00:00 Initialize-OSDCloudStartnet.ps1"
        # Create Logs Path
        $LogsPath = "$env:SystemDrive\OSDCloud\Logs"
        if (-NOT (Test-Path -Path $LogsPath)) {
            New-Item -Path $LogsPath -ItemType Directory -Force | Out-Null
        }

        <#
        OSDCloud Config Startup Scripts
        These scripts will be in the OSDCloud Workspace in Config\Scripts\StartNet
        When Edit-OSDCloudWinPE is executed then these files should be copied to the mounted WinPE
        In WinPE, the scripts will exist in X:\OSDCloud\Config\Scripts\*
        #>
        $Global:ScriptStartNet = Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Name -ne 'C'} | ForEach-Object {
            Get-ChildItem "$($_.Root)OSDCloud\Config\Scripts\StartNet\" -Include "*.ps1" -File -Recurse -Force -ErrorAction Ignore
        }
        if ($Global:ScriptStartNet) {
            $TimeSpan = New-TimeSpan -Start $StartTime -End (Get-Date)
            Write-Host -ForegroundColor Gray "$($TimeSpan.ToString("mm':'ss")) Intialize Startnet Scripts"
            $Global:ScriptStartNet = $Global:ScriptStartNet | Sort-Object -Property FullName
            foreach ($Item in $Global:ScriptStartNet) {
                Write-Host -ForegroundColor DarkGray "$($Item.FullName)"
                & "$($Item.FullName)"
            }
        }

        # Initialize Splash Screen  
        # Looks for SPLASH.JSON files in OSDCloud\Config, if found, it will run a splash screen.
        $Global:SplashScreen = Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Name -ne 'C'} | ForEach-Object {
            Get-ChildItem "$($_.Root)OSDCloud\Config\" -Include "SPLASH.JSON" -File -Recurse -Force -ErrorAction Ignore
        }

        if ($Global:SplashScreen) {
            $TimeSpan = New-TimeSpan -Start $StartTime -End (Get-Date)
            Write-Host -ForegroundColor Gray "$($TimeSpan.ToString("mm':'ss")) Intialize Splash Screen"
            $Global:SplashScreen = $Global:SplashScreen | Sort-Object -Property FullName
            foreach ($Item in $Global:SplashScreen) {
                Write-Host -ForegroundColor DarkGray "Found: $($Item.FullName)"
            }
            if ($Global:SplashScreen.count -gt 1) {
                $SplashJson = $Global:SplashScreen | Select-Object -Last 1
                Write-Host -ForegroundColor DarkGray "Using $($SplashJson.FullName)"
            }
            if (Test-Path -Path "C:\OSDCloud\Logs") {
                Remove-Item -Path "C:\OSDCloud\Logs" -Recurse -Force
            }
            Start-Transcript -Path "X:\OSDCloud\Logs\Deploy-OSDCloud.log"
            if (-NOT ($Global:ModuleBase = (Get-Module -Name OSD).ModuleBase)) {
                Import-Module OSD -Force -ErrorAction Ignore -WarningAction Ignore
            }
            if ($Global:ModuleBase = (Get-Module -Name OSD).ModuleBase) {
                # Write-Host -ForegroundColor DarkGray "Starting $Global:ModuleBase\Resources\SplashScreen\Show-Background.ps1"
                & $Global:ModuleBase\Resources\SplashScreen\Show-Background.ps1
            }
        }

        $TimeSpan = New-TimeSpan -Start $StartTime -End (Get-Date)
        Write-Host -ForegroundColor Gray "$($TimeSpan.ToString("mm':'ss")) Intialize Hardware Devices"
        Start-Sleep -Seconds 10

        # Initialize Wireless Network
        if (Test-Path "$env:SystemRoot\System32\dmcmnutils.dll") {
            $TimeSpan = New-TimeSpan -Start $StartTime -End (Get-Date)
            Write-Host -ForegroundColor Gray "$($TimeSpan.ToString("mm':'ss")) Intialize Wireless Networking"
            if ($WirelessConnect) {
                Start-Process PowerShell -ArgumentList 'Start-WinREWiFi -WirelessConnect' -Wait
            }
            else {
                Start-Process PowerShell Start-WinREWiFi -Wait
            }
        }

        # Initialize Network Connections
        $TimeSpan = New-TimeSpan -Start $StartTime -End (Get-Date)
        Write-Host -ForegroundColor Gray "$($TimeSpan.ToString("mm':'ss")) Intialize Network Connections"
        Start-Sleep -Seconds 10

        # Check if the OSD Module in the PowerShell Gallery is newer than the installed version
        $TimeSpan = New-TimeSpan -Start $StartTime -End (Get-Date)
        Write-Host -ForegroundColor Gray "$($TimeSpan.ToString("mm':'ss")) Updating OSD PowerShell Module"
        $PSModuleName = 'OSD'
        $InstalledModule = Get-Module -Name $PSModuleName -ListAvailable -ErrorAction Ignore | Sort-Object Version -Descending | Select-Object -First 1
        $GalleryPSModule = Find-Module -Name $PSModuleName -ErrorAction Ignore -WarningAction Ignore

        # Install the OSD module if it is not installed or if the version is older than the gallery version
        if ($GalleryPSModule) {
            if (($GalleryPSModule.Version -as [version]) -gt ($InstalledModule.Version -as [version])) {
                Write-Host -ForegroundColor DarkGray "$PSModuleName $($GalleryPSModule.Version) [AllUsers]"
                Install-Module $PSModuleName -Scope AllUsers -Force -SkipPublisherCheck
                Import-Module $PSModuleName -Force
            }
        }

        # Export Logs
        $TimeSpan = New-TimeSpan -Start $StartTime -End (Get-Date)
        Write-Host -ForegroundColor Gray "$($TimeSpan.ToString("mm':'ss")) Exporting Hardware logs to $LogsPath"
        
        $WIN32OPERATINGSYSTEM = Get-WmiObject -Class Win32_OperatingSystem | Select-Object -Property *
        $WIN32OPERATINGSYSTEM | Out-File $LogsPath\Win32_OperatingSystem.txt -Width 4096 -Force
        $WIN32COMPUTERSYSTEM = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -Property *
        $WIN32COMPUTERSYSTEM | Out-File $LogsPath\Win32_ComputerSystem.txt -Width 4096 -Force
        $WIN32BIOS = Get-WmiObject -Class Win32_BIOS | Select-Object -Property *
        $WIN32BIOS | Out-File $LogsPath\Win32_BIOS.txt -Width 4096 -Force
        $WIN32PROCESSOR = Get-WmiObject -Class Win32_Processor | Select-Object -Property *
        $WIN32PROCESSOR | Out-File $LogsPath\Win32_Processor.txt -Width 4096 -Force

        Write-Host -ForegroundColor Gray "WinPE" $WIN32OPERATINGSYSTEM.BuildNumber $WIN32OPERATINGSYSTEM.OSArchitecture '|' $WIN32OPERATINGSYSTEM.Version
        Write-Host -ForegroundColor Gray $WIN32COMPUTERSYSTEM.Manufacturer '|' $WIN32COMPUTERSYSTEM.Model
        Write-Host -ForegroundColor Gray "Product" $(Get-MyComputerProduct) "| Serial Number" $WIN32BIOS.SerialNumber
        Write-Host -ForegroundColor Gray "BIOS" $WIN32BIOS.SMBIOSBIOSVersion
        Write-Host -ForegroundColor Gray $WIN32PROCESSOR.Name "|" $WIN32PROCESSOR.NumberOfLogicalProcessors "Logical Processors"
        Write-Host -ForegroundColor Gray $WIN32OPERATINGSYSTEM.TotalVisibleMemorySize "MB Memory"


$memory = [math]::Round((Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1GB)
Write-Host -ForegroundColor Gray "System Memory: $memory GB"

        # Start PowerShell minimized
        Write-Host -ForegroundColor DarkGray "$((Get-Date).ToString('yyyy-MM-dd-HHmmss')) Start PowerShell Session (minimized)"
        Start-Process PowerShell -WindowStyle Minimized

        # Force import the OSD module
        Import-Module OSD -Force -ErrorAction Ignore -WarningAction Ignore

        # Get the OSD version
        $OSDVersion = (Get-Module -Name OSD -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
        Write-Host -ForegroundColor Green "$((Get-Date).ToString('yyyy-MM-dd-HHmmss')) OSDCloud $OSDVersion Ready"
    }
}