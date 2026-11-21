$ErrorActionPreference='Stop'
$shell=New-Object -ComObject WScript.Shell
$link=$shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'ProxyHelper.lnk'))
$link.TargetPath=Join-Path $env:SystemRoot 'System32\wscript.exe'
$link.Arguments='"'+(Join-Path $PSScriptRoot '启动代理配置助手.vbs')+'"'
$link.WorkingDirectory=$PSScriptRoot
$link.IconLocation=(Join-Path $PSScriptRoot 'ProxyHelper.ico')+',0'
$link.Save()
