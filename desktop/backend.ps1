param([string]$Action='status',[string]$Proxy='')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$keys=@('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY','NODE_USE_ENV_PROXY')
$dir=Join-Path $env:LOCALAPPDATA 'ProxyHelper';[IO.Directory]::CreateDirectory($dir)|Out-Null
$envPath=Join-Path $HOME '.codex\.env';$runKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
function Save-Env($remove){
 [IO.Directory]::CreateDirectory((Split-Path $envPath))|Out-Null
 $lines=@();if(Test-Path $envPath){Copy-Item $envPath "$envPath.backup-$([Guid]::NewGuid())";$lines=@([IO.File]::ReadAllLines($envPath)|Where-Object {$_ -notmatch '^\s*(?:export\s+)?(?i:HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY|NODE_USE_ENV_PROXY)\s*='})}
 foreach($key in $keys){$v=if($remove){$null}elseif($key -eq 'NO_PROXY'){'localhost,127.0.0.1,::1'}elseif($key -eq 'NODE_USE_ENV_PROXY'){'1'}else{$Proxy};[Environment]::SetEnvironmentVariable($key,$v,'User');if(-not $remove){$lines+="$key=$v"}}
 [IO.File]::WriteAllText($envPath,($lines -join "`r`n"),(New-Object Text.UTF8Encoding($false)))
}
try{
 switch($Action){
 'apply'{Save-Env $false}
 'clear'{Save-Env $true;Remove-ItemProperty $runKey -Name 'ProxyHelper' -ErrorAction SilentlyContinue}
 'test'{$r=[Net.WebRequest]::Create('https://example.com');$r.Proxy=New-Object Net.WebProxy($Proxy);$r.Timeout=8000;$response=$r.GetResponse();$response.Close()}
 'startup-on'{
  $body="`$ErrorActionPreference='Stop'`r`n";foreach($key in $keys){$value=if($key -eq 'NO_PROXY'){'localhost,127.0.0.1,::1'}elseif($key -eq 'NODE_USE_ENV_PROXY'){'1'}else{$Proxy};$body+="[Environment]::SetEnvironmentVariable('$key','$($value.Replace("'","''"))','User')`r`n"}
  $file=Join-Path $dir 'Set-ProxyEnv.ps1';[IO.File]::WriteAllText($file,$body,(New-Object Text.UTF8Encoding($true)))
  if(-not(Test-Path $runKey)){New-Item $runKey|Out-Null};New-ItemProperty $runKey -Name 'ProxyHelper' -Value ('powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$file+'"') -PropertyType String -Force|Out-Null
 }
 'startup-off'{Remove-ItemProperty $runKey -Name 'ProxyHelper' -ErrorAction SilentlyContinue}
 }
 $settings=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
 $values=@();foreach($key in $keys){$values+=@{name=$key;user=[Environment]::GetEnvironmentVariable($key,'User');machine=[Environment]::GetEnvironmentVariable($key,'Machine')}}
 $run=Get-ItemProperty $runKey -ErrorAction SilentlyContinue
 @{ok=$true;system=$settings.ProxyServer;enabled=($settings.ProxyEnable -eq 1);values=$values;startup=($null -ne $run -and $run.PSObject.Properties.Name -contains 'ProxyHelper');message='操作完成。用户环境已更新；已运行程序需退出重开。'}|ConvertTo-Json -Depth 5 -Compress
}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 1}
