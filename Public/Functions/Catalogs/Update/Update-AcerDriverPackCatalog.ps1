<#
.SYNOPSIS
Updates the local Acer DriverPack Catalog in the OSD Module

.DESCRIPTION
Updates the local Acer DriverPack Catalog in the OSD Module

.LINK
https://github.com/OSDeploy/OSD/tree/master/Docs

.NOTES
#>
function Update-AcerDriverPackCatalog {
    [CmdletBinding()]
    param (
        #Updates the OSD Module Offline Catalog. Requires Admin rights
        [System.Management.Automation.SwitchParameter]
        $UpdateModuleCatalog,

        #Verifies that the DriverPack is reachable. This will take some time to complete
        [System.Management.Automation.SwitchParameter]
        $Verify
    )
    #=================================================
    #   Custom Defaults
    #=================================================
    $OnlineCatalogUri = 'https://www.acer.com/sccm/'

    $OfflineCatalogName = 'AcerDriverPackCatalog.xml'

    $ModuleCatalogXml = "$($MyInvocation.MyCommand.Module.ModuleBase)\Catalogs\AcerDriverPackCatalog.xml"
    $ModuleCatalogJson = "$($MyInvocation.MyCommand.Module.ModuleBase)\Catalogs\AcerDriverPackCatalog.json"

    #=================================================
    #   Custom Functions
    #=================================================
    $DriverDateLookup = @{}
    function Get-LastModifiedDateFromDriverUrl {
        param(
            [string]$Url
        )

        if ($DriverDateLookup.ContainsKey($Url)) {
            return $DriverDateLookup[$Url]
        }
        else {
            $response = Invoke-WebRequest -Method Head -Uri $Url -UseBasicParsing
            [datetime]$DriverDate = $response.Headers.'Last-Modified'

            $DriverDateLookup.Add($Url, $DriverDate)
            return $DriverDate
        }
    }
    #=================================================
    #   UseCatalog Cloud
    #=================================================
    $AcerDriverPackOverview = Invoke-WebRequest -Uri $OnlineCatalogUri -UseBasicParsing
    $CatalogVersion = Get-Date -Format 'yy.MM.dd'

    #=================================================
    #   Create DriverPack Object
    #=================================================
    $TableRowsRegex = '<tr[\s\S]*?<\/tr>'
    $RowParseRegex = '<tr title="(?''title''[a-zA-Z\s\d\(\),_\-]*?)"[\s\S]*?>[\s]*?<td.*?class="modelnametd">(?''modelname''[a-zA-Z\s\d\(\),_\-]*?)<\/td>[\s\S]*?<td.*?class="windows11td">(?''win11''[\s\S]*?)<\/td>[\s]*?<td.*?class="windows10x64td">(?''win10''[\s\S]*?)<\/td>'

    $TableRows = [regex]::Matches($AcerDriverPackOverview.Content, $TableRowsRegex)

    $Results = foreach ($TableRow in $TableRows) {

        if (-NOT ($TableRow.Value -match $RowParseRegex)) {
            #skip table rows not containing driver information
            continue
        }
    
        $UnparsedTitle = $Matches.title.Trim()
        $UnparsedModelName = $Matches.modelname.Trim()
        $UnparsedWin11 = $Matches.win11.Trim()
        $UnparsedWin10 = $Matches.win10.Trim()
    
        $Win11Url = if ($UnparsedWin11 -match 'https:\/{2}[\w\/\-\.\s\%]*?.((exe)|(cab))') { $Matches[0] } else { $null }
        $Win10Url = if ($UnparsedWin10 -match 'https:\/{2}[\w\/\-\.\s\%]*?.((exe)|(cab))') { $Matches[0] } else { $null }    
        
        $ModelNameSplit = $UnparsedTitle.Split(',')
        $ModelNameVariants = @()

        #parse every model string and expand it's variants (e.g. TMP614-51(T)(G) -> TMP614-51, TMP614-51T, TMP614-51G, TMP614-51TG
        foreach ($Model in $ModelNameSplit) {
    
            $Model = $Model.Trim()
    
            #The case of: TMP446M(G) or VN6640(G) v2
            if ($Model -match '^([\w\s\-]*?)\((\w{1})\)([\w\-\s]*?)$') {
                $ModelNameVariants += '{0}{1}' -f $Matches[1].Trim(), $Matches[3]
                $ModelNameVariants += '{0}{1}{2}' -f $Matches[1].Trim(), $Matches[2], $Matches[3]
            }
            #The Case of: TMP614-51(T)(G) or TMP614-51(T)(G)-G2 or TMP614(P)(RN)-52
            elseif ($Model -match '^([\w\s\-]*?)\((\w{1})\)\((\w{1,2})\)([\w\-]*?)$') {
                $ModelNameVariants += '{0}{1}' -f $Matches[1].Trim(), $Matches[4]
                $ModelNameVariants += '{0}{1}{2}' -f $Matches[1].Trim(), $Matches[2], $Matches[4]
                $ModelNameVariants += '{0}{1}{2}' -f $Matches[1].Trim(), $Matches[3], $Matches[4]
                $ModelNameVariants += '{0}{1}{2}{3}' -f $Matches[1].Trim(), $Matches[2], $Matches[3], $Matches[4]
            }
            #The Case of: TMP614(P)-53(T)
            elseif ($Model -match '^([\w\s\-]*?)\((\w{1})\)([\w\-]*?)\((\w{1,2})\)$') {
                <# TravelMate P614-53, TravelMate P614P-53, TravelMate P614-53T #>
                $ModelNameVariants += '{0}{1}' -f $Matches[1].Trim(), $Matches[3]
                $ModelNameVariants += '{0}{1}{2}' -f $Matches[1].Trim(), $Matches[2], $Matches[3]
                $ModelNameVariants += '{0}{1}{2}' -f $Matches[1].Trim(), $Matches[3], $Matches[4]
            }
            else {
                if ($Model -match '\(') { Write-Warning "Model: [$($Model)] stil contains a parenthesis" }
                $ModelNameVariants += $Model.Trim()
            }
        }
    
        #create a new catalog object for each model variant (Product) and supported OS
        #currently there is no way to extract sfx driver archives, so we skip them
        foreach ($Product in $ModelNameVariants) {

            if ($Win11Url -and ($Win11Url -notmatch '\.exe$')) {
   
                $OSName = 'Windows 11 x64'
                $osShortName = 'Win11'

                $Name = if ($Product -like 'Acer*') { "$($Product) $osShortName" } else { "Acer $($Product) $osShortName" }
                $Name = $Name -replace '  ', ' '

                $ObjectProperties = [Ordered]@{
                    CatalogVersion = $CatalogVersion
                    Status         = $null
                    Component      = 'DriverPack'
                    ReleaseDate    = ((Get-LastModifiedDateFromDriverUrl -Url $Win11Url).ToString('yy.MM.dd'))
                    Manufacturer   = 'Acer'
                    Name           = $Name
                    Model          = $UnparsedModelName
                    UnparsedTitle  = $UnparsedTitle
                    FileName       = ($Win11Url | Split-Path -Leaf)
                    FileBaseName   = ($Win11Url | Split-Path -Leaf).Split('.')[0]
                    Url            = $Win11Url
                    OS             = $OSName
                    OSVersion      = $null
                    OSReleaseId    = $null
                    OSBuild        = $null
                    Product        = [array]$Product
                }
        
                New-Object -TypeName PSObject -Property $ObjectProperties
            }
            if ($Win10Url -and ($Win10Url -notmatch '\.exe$')) {
                $OSName = 'Windows 10 x64'
                $osShortName = 'Win10'

                $Name = if ($Product -like 'Acer*') { "$($Product) $osShortName" } else { "Acer $($Product) $osShortName" }
                $Name = $Name -replace '  ', ' '

                $ObjectProperties = [Ordered]@{
                    CatalogVersion = $CatalogVersion
                    Status         = $null
                    Component      = 'DriverPack'
                    ReleaseDate    = ((Get-LastModifiedDateFromDriverUrl -Url $Win10Url).ToString('yy.MM.dd'))
                    Manufacturer   = 'Acer'
                    Name           = $Name
                    Model          = $UnparsedModelName
                    UnparsedTitle  = $UnparsedTitle
                    FileName       = ($Win10Url | Split-Path -Leaf)
                    FileBaseName   = ($Win10Url | Split-Path -Leaf).Split('.')[0]
                    Url            = $Win10Url
                    OS             = $OSName
                    OSVersion      = $null
                    OSReleaseId    = $null
                    OSBuild        = $null
                    Product        = [array]$Product
                }
        
                New-Object -TypeName PSObject -Property $ObjectProperties
            }          
        }   
    }
    
    #=================================================
    #   Verify DriverPack is reachable
    #=================================================
    if ($Verify) {
        Write-Warning 'Testing each download link, please wait...'
        $Results = $Results | Sort-Object Url
        $LastDriverPack = $null

        foreach ($CurrentDriverPack in $Results) {
            if ($CurrentDriverPack.Url -eq $LastDriverPack.Url) {
                $CurrentDriverPack.Status = $LastDriverPack.Status
                #$CurrentDriverPack.ReleaseDate = $LastDriverPack.ReleaseDate
            }
            else {
                $Global:DownloadHeaders = $null
                try {
                    $Global:DownloadHeaders = (Invoke-WebRequest -Method Head -Uri $CurrentDriverPack.Url -UseBasicParsing).Headers
                }
                catch {
                    Write-Warning "Failed: $($CurrentDriverPack.Url)"
                }

                if ($Global:DownloadHeaders) {
                    Write-Verbose -Verbose "$($CurrentDriverPack.Url)"
                    #$CurrentDriverPack.ReleaseDate = Get-Date ($Global:DownloadHeaders.'Last-Modified') -Format "yy.MM.dd"
                    #Write-Verbose -Verbose "ReleaseDate: $($CurrentDriverPack.ReleaseDate)"
                }
                else {
                    $CurrentDriverPack.Status = 'Failed'
                }
            }
            $LastDriverPack = $CurrentDriverPack
        }
    }
    #=================================================
    #   Sort Results
    #=================================================
    $Results = $Results | Sort-Object -Property Name
    #=================================================
    #   UpdateModule
    #=================================================
    if ($UpdateModuleCatalog) {
        Write-Verbose -Verbose "UpdateModule: Exporting to OSD Module Catalogs at $ModuleCatalogXml"
        $Results | Export-Clixml -Path $ModuleCatalogXml -Force
        Write-Verbose -Verbose "UpdateModule: Exporting to OSD Module Catalogs at $ModuleCatalogJson"
        $Results | ConvertTo-Json | Out-File $ModuleCatalogJson -Encoding ascii -Width 2000 -Force
        #=================================================
        #   UpdateCatalog
        #=================================================       
        $MasterDriverPacks = @()
        $MasterDriverPacks += Get-AcerDriverPack
        $MasterDriverPacks += Get-DellDriverPack
        $MasterDriverPacks += Get-HPDriverPack
        $MasterDriverPacks += Get-LenovoDriverPack
        $MasterDriverPacks += Get-MicrosoftDriverPack
    
        $MasterResults = $MasterDriverPacks | `
            Select-Object CatalogVersion, Status, ReleaseDate, Manufacturer, Model, `
            Product, Name, PackageID, FileName, `
        @{Name = 'Url'; Expression = { ([array]$_.DriverPackUrl) } }, `
        @{Name = 'OS'; Expression = { ([array]$_.DriverPackOS) } }, `
            OSReleaseId, OSBuild, HashMD5, `
        @{Name = 'Guid'; Expression = { ([guid]((New-Guid).ToString())) } }
    
        $MasterResults | Export-Clixml -Path (Join-Path (Get-Module -Name OSD -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).ModuleBase 'Catalogs\CloudDriverPacks.xml') -Force
        Import-Clixml -Path (Join-Path (Get-Module -Name OSD -ListAvailable | `
                    Sort-Object Version -Descending | `
                    Select-Object -First 1).ModuleBase 'Catalogs\CloudDriverPacks.xml') | `
            ConvertTo-Json | `
            Out-File (Join-Path (Get-Module -Name OSD -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).ModuleBase 'Catalogs\CloudDriverPacks.json') -Encoding ascii -Width 2000 -Force
    }
    #=================================================
    #   Complete
    #=================================================
    Write-Verbose -Verbose 'Complete: Results have been stored $Global:AcerDriverPackCatalog'
    $Global:AcerDriverPackCatalog = $Results | Sort-Object -Property Name
    #=================================================
}