function Set-SetupCompleteOSDCloudUSB {


    $ScriptsPath = "C:\Windows\Setup\scripts"
    $RunScript = @(@{ Script = "SetupComplete"; BatFile = 'SetupComplete.cmd'; ps1file = 'SetupComplete.ps1';Type = 'Setup'; Path = "$ScriptsPath"})
    $PSFilePath = "$($RunScript.Path)\$($RunScript.ps1File)"

    if (Test-Path -Path $PSFilePath){
        Add-Content -Path $PSFilePath "Write-OutPut 'Running Scripts in OSDCloudUSB SetupComplete Folder'"
        Add-Content -Path $PSFilePath '$OSDCloudUSB = Get-Volume.usb | Where-Object {($_.FileSystemLabel -match 'OSDCloud') -or ($_.FileSystemLabel -match 'BHIMAGE')} | Select-Object -First 1'
        Add-Content -Path $PSFilePath '$SetupCompletePath = "$($OSDCloudUSB.DriveLetter):\OSDCloud\SetupComplete"'
        Add-Content -Path $PSFilePath 'if (Test-Path $SetupCompletePath){$SetupComplete = Get-ChildItem $SetupCompletePath -Filter SetupComplete.cmd}'
        Add-Content -Path $PSFilePath 'if ($SetupComplete){cmd.exe /start /wait /c $SetupComplete.FullName}'
    }
    else {
    Write-Output "$PSFilePath - Not Found"
    }
}