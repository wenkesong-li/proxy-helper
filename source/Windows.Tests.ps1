$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot '../Windows/ProxyHelper.ps1'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
# Parse the embedded elevation/startup scripts as well as the outer GUI script.
$embedded=@($ast.FindAll({param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.Value.TrimStart().StartsWith('$ErrorActionPreference')},$true))
if($embedded.Count -lt 3){throw 'Embedded helper scripts not found'}
foreach($item in $embedded){$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseInput($item.Value,[ref]$t,[ref]$e)|Out-Null;if($e.Count){throw ($e.Message -join '; ')}}
$functions=$ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in @('Set-Startup','Test-Startup','Remove-Startup')},$true)
foreach($f in $functions){Invoke-Expression $f.Extent.Text}
function Test-Path {param($Path,$LiteralPath) if($Path -like 'HKCU:*'){return $true}; if($LiteralPath){return (Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath)}; return (Microsoft.PowerShell.Management\Test-Path -Path $Path)}
$script:runEntry=$null
function Get-ItemProperty {param($Path,$ErrorAction) if($script:runEntry){[pscustomobject]@{ProxyHelper=$script:runEntry}}else{[pscustomobject]@{}}}
function New-Item {param($Path,[switch]$Force) if($Path -notlike 'HKCU:*'){throw 'Unexpected registry path'}}
function New-ItemProperty {param($Path,$Name,$Value,$PropertyType,[switch]$Force) if($Name -ne 'ProxyHelper'){throw 'Unexpected registry name'}; $script:runEntry=$Value}
function Remove-ItemProperty {param($Path,$Name) if($Name -ne 'ProxyHelper'){throw 'Unexpected registry name'}; function Test-Path {param($Path,$LiteralPath) if($Path -like 'HKCU:*'){return $true}; if($LiteralPath){return (Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath)}; return (Microsoft.PowerShell.Management\Test-Path -Path $Path)}
$script:runEntry=$null}
$taskRoot=Join-Path ([IO.Path]::GetTempPath()) ('ProxyHelper-Windows-Test-'+[Guid]::NewGuid())
$previousLocal=$env:LOCALAPPDATA; $env:LOCALAPPDATA=$taskRoot
try {
 Set-Startup 'http://127.0.0.1:18080'
 if(-not (Test-Startup)){throw 'Startup not installed'}
 $scriptPath=Join-Path $taskRoot 'ProxyHelper/Set-ProxyEnv.ps1'
 if(-not (Test-Path $scriptPath)){throw 'Script not created'}
 $code=[IO.File]::ReadAllText($scriptPath)
 if($code -notmatch "FromBase64String\('([^']+)'\)"){throw 'Missing startup values'}
 $values=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1]))|ConvertFrom-Json
 if($values.HTTP_PROXY -ne 'http://127.0.0.1:18080'){throw 'Incorrect proxy'}
 Set-Startup 'http://127.0.0.1:18081'
 if(@(Get-ChildItem (Join-Path $taskRoot 'ProxyHelper') -Filter '*.backup-*').Count -ne 1){throw 'Missing backup'}
 Remove-Startup
 if(Test-Startup){throw 'Startup not removed'}
 if(Test-Path $scriptPath){throw 'Script not removed'}
 if(@(Get-ChildItem (Join-Path $taskRoot 'ProxyHelper') -Filter '*.backup-*').Count -ne 2){throw 'Missing removal backup'}
 'PASS: PowerShell syntax, startup install/update/remove and original script backups with isolated files/mock registry'
} finally {$env:LOCALAPPDATA=$previousLocal; if(Test-Path $taskRoot){Remove-Item -LiteralPath $taskRoot -Recurse -Force}}
