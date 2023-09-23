function Set-SetupCompleteRunWindowsUpdate {

    $ScriptsPath = "C:\Windows\Setup\scripts"
    $RunScript = @(@{ Script = "SetupComplete"; BatFile = 'SetupComplete.cmd'; ps1file = 'SetupComplete.ps1';Type = 'Setup'; Path = "$ScriptsPath"})
    $PSFilePath = "$($RunScript.Path)\$($RunScript.ps1File)"

    if (Test-Path -Path $PSFilePath){
        Add-Content -Path $PSFilePath "Write-Output 'Running Windows Update'"
        Add-Content -Path $PSFilePath "Run-WindowsUpdate"
    }
    else {
    Write-Output "$PSFilePath - Not Found"
    }
}