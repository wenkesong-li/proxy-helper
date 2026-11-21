param([string]$HelperExe='', [switch]$LaunchChatGPT, [string]$RuntimeDirectory='')
if(-not $RuntimeDirectory){$RuntimeDirectory=$PSScriptRoot}
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Write-History([string]$message) {
    $dir=Join-Path $env:LOCALAPPDATA 'ProxyHelper'
    [IO.Directory]::CreateDirectory($dir) | Out-Null
    Add-Content -LiteralPath (Join-Path $dir 'history.log') -Encoding UTF8 -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $message)
}
function Get-BackupFiles {
    $specs = @(
        @{Dir=(Join-Path $HOME '.codex'); Pattern='.env.backup-*'},
        @{Dir=(Join-Path $env:LOCALAPPDATA 'ProxyHelper'); Pattern='Set-ProxyEnv.ps1.backup-*'},
        @{Dir=(Join-Path $env:LOCALAPPDATA 'ProxyHelper'); Pattern='Run-backup-*.txt'},
        @{Dir=$env:ProgramData; Pattern='ProxyHelper-machine-backup-*.json'},
        @{Dir=(Join-Path $env:LOCALAPPDATA 'ProxyHelper'); Pattern='user-env-backup-*.json'}
    )
    foreach ($spec in $specs) {
        if (Test-Path $spec.Dir) { Get-ChildItem -LiteralPath $spec.Dir -Filter $spec.Pattern -File -Force | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } }
    }
}
function Show-History {
    $dialog=New-Object Windows.Forms.Form; $dialog.Text='修改历史与备份管理'; $dialog.Size=New-Object Drawing.Size(900,650); $dialog.StartPosition='CenterParent'
    $log=New-Object Windows.Forms.TextBox; $log.Multiline=$true; $log.ReadOnly=$true; $log.ScrollBars='Both'; $log.SetBounds(15,15,850,175)
    $logPath=Join-Path $env:LOCALAPPDATA 'ProxyHelper\history.log'
    if (Test-Path $logPath) { $log.Text=[IO.File]::ReadAllText($logPath) } else { $log.Text='暂无操作记录。旧版本没有记录操作历史，下方列出现存备份。' }
    $grid=New-Object Windows.Forms.DataGridView; $grid.SetBounds(15,205,850,325); $grid.AllowUserToAddRows=$false; $grid.AllowUserToDeleteRows=$false; $grid.RowHeadersVisible=$false
    $check=New-Object Windows.Forms.DataGridViewCheckBoxColumn; $check.Name='Selected'; $check.HeaderText='选择'; [void]$grid.Columns.Add($check)
    [void]$grid.Columns.Add('Date','创建时间'); [void]$grid.Columns.Add('Path','备份文件'); $grid.Columns['Date'].Width=150; $grid.Columns['Path'].Width=570; $grid.Columns['Date'].ReadOnly=$true; $grid.Columns['Path'].ReadOnly=$true
    $reload = { if(Test-Path $logPath){$log.Text=[IO.File]::ReadAllText($logPath)}; $grid.Rows.Clear(); foreach ($file in @(Get-BackupFiles)) { [void]$grid.Rows.Add($false,$file.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'),$file.FullName) } }
    & $reload
    $all=New-Object Windows.Forms.Button; $all.Text='全选'; $all.SetBounds(15,550,120,35); $all.Add_Click({ foreach ($row in $grid.Rows) { $row.Cells[0].Value=$true } })
    $none=New-Object Windows.Forms.Button; $none.Text='取消全选'; $none.SetBounds(150,550,120,35); $none.Add_Click({ foreach ($row in $grid.Rows) { $row.Cells[0].Value=$false } })
    $delete=New-Object Windows.Forms.Button; $delete.Text='删除勾选备份'; $delete.SetBounds(290,550,170,35)
    $delete.Add_Click({
        $grid.EndEdit() | Out-Null
        $paths=@($grid.Rows | Where-Object { $_.Cells[0].Value -eq $true } | ForEach-Object { [string]$_.Cells[2].Value })
        if (-not $paths.Count) { return }
        if ([Windows.Forms.MessageBox]::Show("永久删除 $($paths.Count) 个备份？当前配置和修改历史将保留。",'确认删除','YesNo','Warning') -ne 'Yes') { return }
        $allowed=@(Get-BackupFiles | ForEach-Object { $_.FullName }); $failures=@(); $count=0
        $machinePaths=@($paths | Where-Object { $allowed -contains $_ -and [IO.Path]::GetDirectoryName($_) -eq $env:ProgramData })
        foreach ($path in $paths) { if ($allowed -contains $path -and $machinePaths -notcontains $path) { try { Remove-Item -LiteralPath $path -Force; $count++ } catch { $failures += $path + ': ' + $_.Exception.Message } } }
        if ($machinePaths.Count) {
            $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $machinePaths -Compress)))
            $code=@'
$ErrorActionPreference='Stop'
try {
 $paths=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PATHS__')) | ConvertFrom-Json
 foreach ($path in $paths) {
  $file=Get-Item -LiteralPath $path -Force
  if ($file.DirectoryName -ne $env:ProgramData -or $file.Name -notlike 'ProxyHelper-machine-backup-*.json' -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid backup path' }
  Remove-Item -LiteralPath $file.FullName -Force
 }
 exit 0
} catch { exit 1 }
'@
            try {
                $command=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code.Replace('__PATHS__',$encoded)))
                $process=Start-Process -FilePath "$PSHOME\powershell.exe" -ArgumentList @('-NoProfile','-EncodedCommand',$command) -Verb RunAs -WindowStyle Hidden -PassThru
                $process=Wait-Elevated $process
                foreach ($path in $machinePaths) { if (Test-Path -LiteralPath $path) { $failures += $path } else { $count++ } }
            } catch { $failures += '系统级备份删除未完成：'+$_.Exception.Message }
        }
        Write-History "删除备份 $count 个；失败 $($failures.Count) 个"
        & $reload
        if ($failures.Count) { [void][Windows.Forms.MessageBox]::Show(($failures -join "`r`n"),'部分备份删除失败（系统级备份可能需要管理员权限）') }
    })
    $back=New-Object Windows.Forms.Button; $back.Text='返回主界面'; $back.SetBounds(680,550,170,35); $back.Add_Click({ $dialog.Close() }); $dialog.CancelButton=$back
    $dialog.Font=New-Object Drawing.Font('Microsoft YaHei UI',10); $dialog.BackColor=[Drawing.Color]::FromArgb(245,247,250)
    $dialog.Controls.AddRange(@($log,$grid,$all,$none,$delete,$back)); [void]$dialog.ShowDialog($form)
}

function Find-Proxy {
    $settings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if ($settings.ProxyEnable -eq 1 -and $settings.ProxyServer) {
        $server = [string]$settings.ProxyServer
        if ($server -match '(?:^|;)http=([^;]+)') { return "http://$($Matches[1])" }
        if ($server -notmatch '=') { if ($server -match '^http://') { return $server }; return "http://$server" }
    }
    foreach ($scope in @('User','Machine','Process')) {
        foreach ($key in @('HTTPS_PROXY','HTTP_PROXY','ALL_PROXY')) {
            $value = [Environment]::GetEnvironmentVariable($key,$scope)
            if ($value -match '^http://') { return $value }
        }
    }
    $path = Join-Path $HOME '.codex\.env'
    if (Test-Path $path) {
        foreach ($line in Get-Content $path) {
            if ($line -match '^\s*(?:HTTP_PROXY|HTTPS_PROXY)\s*=\s*(http://\S+)\s*$') { return $Matches[1] }
        }
    }
    return ''
}
function Apply-Proxy([string]$proxy, [bool]$validated=$false) {
    $uri = $null
    if (-not [Uri]::TryCreate($proxy,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'http' -or $proxy -notmatch ':\d+/?$' -or $uri.Port -lt 1 -or $uri.Port -gt 65535 -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -ne '/') { throw '请输入 http://主机:端口，不支持账号密码。' }
    if (-not $validated) {
    $status.Text = '正在验证代理连接…'; $form.Refresh()
    $request = [Net.WebRequest]::Create('https://example.com')
    $request.Proxy = New-Object Net.WebProxy($proxy)
    $request.Timeout = 8000
    try { $response = $request.GetResponse(); $response.Close() } catch { throw "代理验证失败，未修改配置：$($_.Exception.Message)" }
    }
    $values=[ordered]@{HTTP_PROXY=$proxy;HTTPS_PROXY=$proxy;ALL_PROXY=$proxy;NO_PROXY='localhost,127.0.0.1,::1';NODE_USE_ENV_PROXY='1'}
    $payload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($values|ConvertTo-Json -Compress)))
    $code=@'
$ErrorActionPreference='Stop'
try{
 $v=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__VALUES__'))|ConvertFrom-Json
 $backup=@{};foreach($p in $v.PSObject.Properties){$backup[$p.Name]=[Environment]::GetEnvironmentVariable($p.Name,'Machine')}
 $backup|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $env:ProgramData ('ProxyHelper-machine-backup-'+[Guid]::NewGuid()+'.json'))
 foreach($p in $v.PSObject.Properties){[Environment]::SetEnvironmentVariable($p.Name,[string]$p.Value,'Machine')};exit 0
}catch{exit 1}
'@
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code.Replace('__VALUES__',$payload)))
    $process=Start-Process "$PSHOME\powershell.exe" -ArgumentList @('-NoProfile','-EncodedCommand',$encoded) -Verb RunAs -WindowStyle Hidden -PassThru
    $process=Wait-Elevated $process
    if($process.ExitCode -ne 0){throw '全局环境写入失败'}
    $path=Join-Path $HOME '.codex\.env';[IO.Directory]::CreateDirectory((Split-Path $path))|Out-Null
    $lines=@();if(Test-Path $path){Copy-Item $path "$path.backup-$([Guid]::NewGuid())";$lines=@([IO.File]::ReadAllLines($path)|Where-Object {$_ -notmatch '^\s*(?:export\s+)?(?i:HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY|NODE_USE_ENV_PROXY)\s*='})}
    foreach($key in $values.Keys){$lines+="$key=$($values[$key])";[Environment]::SetEnvironmentVariable($key,$values[$key],'User');[Environment]::SetEnvironmentVariable($key,$values[$key],'Process')}
    [IO.File]::WriteAllText($path,($lines -join "`r`n")+"`r`n",(New-Object Text.UTF8Encoding($false)))
    if($startupOption.Checked){Set-Startup $proxy}else{Remove-Startup}
    foreach($key in $values.Keys){
        foreach($scopeName in @('User','Machine')){
            if([Environment]::GetEnvironmentVariable($key,$scopeName) -ne $values[$key]){throw "写入回读不一致：$scopeName / $key"}
        }
    }
    $saved=[IO.File]::ReadAllText($path)
    foreach($key in $values.Keys){if(-not $saved.Contains("$key=$($values[$key])")){throw ".env 回读失败：$key"}}
    Broadcast-Environment
    $status.Text='已同步系统级/用户环境、Codex .env 与登录启动配置。已运行应用需重启刷新。';Write-History ($status.Text+' '+$proxy)
}

function Set-Startup([string]$proxy) {
    $values = [ordered]@{HTTP_PROXY=$proxy; HTTPS_PROXY=$proxy; ALL_PROXY=$proxy; NO_PROXY='localhost,127.0.0.1,::1'; NODE_USE_ENV_PROXY='1'}
    $encodedValues = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($values | ConvertTo-Json -Compress)))
    $startupDir = Join-Path $env:LOCALAPPDATA 'ProxyHelper'
    [IO.Directory]::CreateDirectory($startupDir) | Out-Null
    $startupPath = Join-Path $startupDir 'Set-ProxyEnv.ps1'
    if (Test-Path $startupPath) { Copy-Item $startupPath "$startupPath.backup-$([Guid]::NewGuid())" }
    $startupCode = @'
$ErrorActionPreference = 'Stop'
$v = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__VALUES__')) | ConvertFrom-Json
foreach ($p in $v.PSObject.Properties) {
    [Environment]::SetEnvironmentVariable($p.Name,[string]$p.Value,'User')
    [Environment]::SetEnvironmentVariable($p.Name,[string]$p.Value,'Process')
}
'@
    [IO.File]::WriteAllText($startupPath,$startupCode.Replace('__VALUES__',$encodedValues),(New-Object Text.UTF8Encoding($true)))
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if (-not (Test-Path $runKey)) { New-Item -Path $runKey | Out-Null }
    $command = '"' + "$PSHOME\powershell.exe" + '" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $startupPath + '"'
    $oldRun = Get-ItemProperty -Path $runKey
    if ($oldRun.PSObject.Properties.Name -contains 'ProxyHelper') { [IO.File]::WriteAllText((Join-Path $startupDir ('Run-backup-' + [Guid]::NewGuid() + '.txt')),[string]$oldRun.ProxyHelper) }
    New-ItemProperty -Path $runKey -Name 'ProxyHelper' -Value $command -PropertyType String -Force | Out-Null
}

function Test-Startup {
    $item=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
    return ($null -ne $item -and $item.PSObject.Properties.Name -contains 'ProxyHelper')
}
function Remove-Startup {
    $dir=Join-Path $env:LOCALAPPDATA 'ProxyHelper'; [IO.Directory]::CreateDirectory($dir) | Out-Null
    $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if (Test-Startup) {
        $value=(Get-ItemProperty $key).ProxyHelper
        [IO.File]::WriteAllText((Join-Path $dir ('Run-backup-'+[Guid]::NewGuid()+'.txt')),[string]$value)
        Remove-ItemProperty $key -Name 'ProxyHelper'
    }
    $scriptPath=Join-Path $dir 'Set-ProxyEnv.ps1'
    if (Test-Path $scriptPath) { Copy-Item $scriptPath "$scriptPath.backup-$([Guid]::NewGuid())"; Remove-Item -LiteralPath $scriptPath }
}
function Get-Report {
    $lines=@('代理配置助手 · 当前配置',('采集时间：'+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),'')
    $settings=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    $lines += "系统代理启用：$($settings.ProxyEnable)；地址：$($settings.ProxyServer)"
    $lines += "登录启动项：$(if(Test-Startup){'已安装'}else{'未安装'})"
    $startupFile=Join-Path $env:LOCALAPPDATA 'ProxyHelper\Set-ProxyEnv.ps1'
    if(Test-Path $startupFile){
        $startupText=[IO.File]::ReadAllText($startupFile)
        if($startupText -match "FromBase64String\('([^']+)'\)"){try{$saved=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1]))|ConvertFrom-Json; $lines += "登录时恢复的代理：$($saved.HTTP_PROXY)"}catch{$lines += '启动脚本配置无法解析'}}
    }elseif(Test-Startup){$lines += '警告：启动项存在，但启动脚本缺失'}
    $path=Join-Path $HOME '.codex\.env'; $envMap=@{}
    if (Test-Path $path) { foreach ($line in Get-Content $path) { if ($line -match '^\s*(?:export\s+)?(HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY|NODE_USE_ENV_PROXY)\s*=\s*(.*)$') { $envMap[$Matches[1]]=$Matches[2] } } }
    $different=$false
    foreach ($key in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY','NODE_USE_ENV_PROXY')) {
        $user=[Environment]::GetEnvironmentVariable($key,'User'); $machine=[Environment]::GetEnvironmentVariable($key,'Machine')
        $file=$envMap[$key]; if (-not $user -or -not $machine -or -not $file -or $user -ne $machine -or $user -ne $file) { $different=$true }
        $lines += "`r`n$key`r`n  用户：$(if($user){$user}else{'未设置'})`r`n  全局：$(if($machine){$machine}else{'未设置'})`r`n  .env：$(if($file){$file}else{'未设置'})"
    }
    $lines += "`r`n变量一致性：$(if($different){'存在缺失或差异；按应用隔离时可以为空或不同'}else{'上述代理变量一致'})"
    $lines += "`r`n配置文件：$path`r`n启动脚本：$(Join-Path $env:LOCALAPPDATA 'ProxyHelper\Set-ProxyEnv.ps1')"
    $lines += "`r`n已运行的应用不会自动刷新环境变量，请退出后重新打开。"
    return ($lines -join "`r`n")
}
# Verify in a worker task so the UI stays responsive during network timeouts.
Add-Type @'
#pragma warning disable
using System; using System.Net; using System.Threading.Tasks;
public static class ProxyConnection {
 public static Task<string> Test(string proxy) {
  return Task.Factory.StartNew<string>(() => {
   try { var r=WebRequest.Create("https://example.com"); r.Proxy=new WebProxy(proxy); r.Timeout=8000; using(var response=r.GetResponse()) {} return ""; }
   catch(Exception e) { return e.Message; }
  });
 }
}
'@

function Broadcast-Environment {
    if(-not ('ProxyEnvironmentNotify' -as [type])){Add-Type @'
using System; using System.Runtime.InteropServices;
public class ProxyEnvironmentNotify {
[DllImport("user32.dll",CharSet=CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,UIntPtr w,string l,uint f,uint t,out UIntPtr r);
}
'@}
    $r=[UIntPtr]::Zero; [ProxyEnvironmentNotify]::SendMessageTimeout([IntPtr]0xffff,0x1a,[UIntPtr]::Zero,'Environment',2,3000,[ref]$r)|Out-Null
}
function Clear-ProxySettings {
    $keys=@('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY','NODE_USE_ENV_PROXY')
    $code=@'
$ErrorActionPreference='Stop'
try{
 $keys=@('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY','NODE_USE_ENV_PROXY')
 $backup=@{};foreach($key in $keys){$backup[$key]=[Environment]::GetEnvironmentVariable($key,'Machine')}
 $backup|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $env:ProgramData ('ProxyHelper-machine-backup-'+[Guid]::NewGuid()+'.json'))
 foreach($key in $keys){[Environment]::SetEnvironmentVariable($key,$null,'Machine')};exit 0
}catch{exit 1}
'@
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $process=Start-Process "$PSHOME\powershell.exe" -ArgumentList @('-NoProfile','-EncodedCommand',$encoded) -Verb RunAs -WindowStyle Hidden -PassThru
    $process=Wait-Elevated $process
    if($process.ExitCode -ne 0){throw '全局环境变量清理失败'}
    $dir=Join-Path $env:LOCALAPPDATA 'ProxyHelper';[IO.Directory]::CreateDirectory($dir)|Out-Null
    $backup=@{};foreach($key in $keys){$backup[$key]=[Environment]::GetEnvironmentVariable($key,'User')}
    $backup|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $dir ('user-env-backup-'+[Guid]::NewGuid()+'.json'))
    Remove-Startup
    foreach($key in $keys){[Environment]::SetEnvironmentVariable($key,$null,'User');[Environment]::SetEnvironmentVariable($key,$null,'Process')}
    $path=Join-Path $HOME '.codex\.env'
    if(Test-Path $path){
        Copy-Item $path "$path.backup-$([Guid]::NewGuid())"
        $lines=@([IO.File]::ReadAllLines($path)|Where-Object {$_ -notmatch '^\s*(?:export\s+)?(?i:HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY|NODE_USE_ENV_PROXY)\s*='})
        [IO.File]::WriteAllText($path,($lines -join "`r`n"),(New-Object Text.UTF8Encoding($false)))
    }
    Broadcast-Environment
}
function Get-SelectedApps {
    for($i=0;$i -lt $appList.Items.Count;$i++){
        $item=$appList.Items[$i];[pscustomobject]@{Name=$item.Name;Path=$item.Path;Selected=$appList.GetItemChecked($i)}
    }
}
function Save-AppList($apps){
    $dir=Join-Path $env:LOCALAPPDATA 'ProxyHelper';[IO.Directory]::CreateDirectory($dir)|Out-Null
    ConvertTo-Json -InputObject @($apps) | Set-Content -Encoding UTF8 (Join-Path $dir 'applications.json')
}
function Write-AppLaunchers($apps,[string]$proxy){
    $dir=Join-Path $env:LOCALAPPDATA 'ProxyHelper\AppLaunchers';[IO.Directory]::CreateDirectory($dir)|Out-Null
    foreach($old in Get-ChildItem -LiteralPath $dir -File){if($old.Name -match '^app-\d+(?:-[^\r\n]*)?\.(ps1|lnk)$'){Remove-Item -LiteralPath $old.FullName -Force}}
    $shell=New-Object -ComObject WScript.Shell
    $i=0
    foreach($app in $apps){

        $data=@{Path=$app.Path;Proxy=$proxy;Selected=[bool]$app.Selected}|ConvertTo-Json -Compress
        $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($data))
        $code=@'
$ErrorActionPreference='Stop'
$v=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__DATA__'))|ConvertFrom-Json
$p=New-Object Diagnostics.ProcessStartInfo
$p.FileName=$v.Path;$p.UseShellExecute=$false;$p.WorkingDirectory=Split-Path $v.Path
foreach($key in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY','NODE_USE_ENV_PROXY')){$p.EnvironmentVariables.Remove($key)}
if($v.Selected){foreach($key in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')){$p.EnvironmentVariables[$key]=$v.Proxy};$p.EnvironmentVariables['NO_PROXY']='localhost,127.0.0.1,::1';$p.EnvironmentVariables['NODE_USE_ENV_PROXY']='1'}
[Diagnostics.Process]::Start($p)|Out-Null
'@
        $scriptPath=Join-Path $dir ("app-$i.ps1")
        [IO.File]::WriteAllText($scriptPath,$code.Replace('__DATA__',$encoded),(New-Object Text.UTF8Encoding($true)))
        $safeName=$app.Name -replace '[<>:"/\\|?*]','_'
        $link=$shell.CreateShortcut((Join-Path $dir ("app-$i-$safeName.lnk")))
        $link.TargetPath="$PSHOME\powershell.exe";$link.Arguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$scriptPath+'"';$link.IconLocation=$app.Path+',0';$link.Description=$app.Name+$(if($app.Selected){' · 代理'}else{' · 默认'});$link.Save();$i++
    }
}
function Clear-AllProxy {
 if([Windows.Forms.MessageBox]::Show('备份并清除全局/用户代理环境、.env 代理项及旧登录项？系统代理/VPN 保留，已运行应用需重启刷新。','清除代理','YesNo','Warning') -ne 'Yes'){return}
 $tabs.Enabled=$false
 try{
  Clear-ProxySettings

  $status.Text='代理配置已清除并广播环境变化。新启动程序立即生效；已运行程序请重启。';Write-History $status.Text
 }catch{$status.Text='清除未完成，部分配置可能已更新：'+$_.Exception.Message;Write-History $status.Text}
 finally{$tabs.Enabled=$true;Refresh-Views;[void][Windows.Forms.MessageBox]::Show($form,$status.Text,'清除结果','OK','Information')}
}

function Get-ChatGPTPath {
    $config=Join-Path $env:LOCALAPPDATA 'ProxyHelper\chatgpt-path.txt'
    # Resolve the current Store package every time, since updates change WindowsApps paths.
    $alias=Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\ChatGPT.exe'
    if(Test-Path -LiteralPath $alias){return $alias}
    $packages=@(Get-AppxPackage -Name '*ChatGPT*' -ErrorAction SilentlyContinue | Sort-Object Version -Descending)
    foreach($package in $packages){
        try{
            $manifest=Get-AppxPackageManifest -Package $package.PackageFullName -ErrorAction Stop
            foreach($application in $manifest.Package.Applications.Application){
                $relative=[string]$application.Executable
                if($relative -and $relative -notmatch '\$'){
                    $candidate=Join-Path $package.InstallLocation $relative
                    if(Test-Path -LiteralPath $candidate){
                        [IO.Directory]::CreateDirectory((Split-Path $config))|Out-Null
                        [IO.File]::WriteAllText($config,$candidate);return $candidate
                    }
                }
            }
            $candidate=Join-Path $package.InstallLocation 'app\ChatGPT.exe'
            if(Test-Path -LiteralPath $candidate){return $candidate}
        }catch{continue}
    }
    if(Test-Path $config){$saved=[IO.File]::ReadAllText($config);if(Test-Path -LiteralPath $saved){return $saved}}
    $candidates=@("$env:LOCALAPPDATA\Programs\ChatGPT\ChatGPT.exe","$env:ProgramFiles\ChatGPT\ChatGPT.exe")
    $command=Get-Command ChatGPT.exe -ErrorAction SilentlyContinue;if($command){$candidates=@($command.Source)+$candidates}
    $found=$candidates|Where-Object {Test-Path -LiteralPath $_}|Select-Object -First 1
    if(-not $found){
        $entry=@(Get-StartApps -ErrorAction SilentlyContinue | Where-Object {$_.Name -match '^ChatGPT(?:\s|$)' -or $_.AppID -match 'ChatGPT'} | Select-Object -First 1)
        if($entry.Count){return ('store-appid:'+$entry[0].AppID)}
        $dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Title='选择 ChatGPT.exe（只需设置一次）';$dialog.Filter='ChatGPT 应用 (*.exe)|*.exe'
        if($dialog.ShowDialog() -ne 'OK'){throw '未选择 ChatGPT 程序'};$found=$dialog.FileName
    }
    [IO.Directory]::CreateDirectory((Split-Path $config))|Out-Null;[IO.File]::WriteAllText($config,$found);return $found
}
function Launch-ChatGPTWithProxy {
    $path=Get-ChatGPTPath
    $config=Join-Path $env:LOCALAPPDATA 'ProxyHelper\chatgpt-proxy.txt'
    $proxy=if(Test-Path $config){[IO.File]::ReadAllText($config)}else{Find-Proxy}
    if(-not $proxy){throw '请先填写地址并创建 ChatGPT 代理快捷方式'}
    if($path.StartsWith('store-appid:')){
        $answer=[Windows.Forms.MessageBox]::Show('将通过 Windows 注册入口打开商店版。此方式无法保证单次代理变量生效，需要代理时请先设置全局变量。是否打开？','商店版启动','YesNo','Information')
        if($answer -eq 'Yes'){Start-Process explorer.exe -ArgumentList ('shell:AppsFolder\'+$path.Substring(12))};return
    }
    $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=$path;$start.UseShellExecute=$false;$start.WorkingDirectory=Split-Path $path
    foreach($key in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')){$start.EnvironmentVariables[$key]=$proxy}
    $start.EnvironmentVariables['NO_PROXY']='localhost,127.0.0.1,::1';$start.EnvironmentVariables['NODE_USE_ENV_PROXY']='1'
    try{[Diagnostics.Process]::Start($start)|Out-Null}
    catch{
        if($path -notmatch 'WindowsApps'){throw}
        $packages=@(Get-AppxPackage -Name '*ChatGPT*' -ErrorAction SilentlyContinue | Sort-Object Version -Descending)
        foreach($package in $packages){
            $manifest=Get-AppxPackageManifest -Package $package.PackageFullName
            $application=@($manifest.Package.Applications.Application)|Select-Object -First 1
            if($application.Id){
                $answer=[Windows.Forms.MessageBox]::Show('商店版禁止直接启动。可改用 Windows 商店激活方式打开，但无法保证继承绿色入口的单次代理变量。如需代理，请使用工具设置全局变量。是否继续打开？','商店版 ChatGPT','YesNo','Information')
                if($answer -eq 'Yes'){Start-Process explorer.exe -ArgumentList ('shell:AppsFolder\'+$package.PackageFamilyName+'!'+$application.Id)}
                return
            }
        }
        $entry=@(Get-StartApps -ErrorAction SilentlyContinue | Where-Object {$_.Name -match '^ChatGPT(?:\s|$)' -or $_.AppID -match 'ChatGPT'} | Select-Object -First 1)
        if($entry.Count -and $entry[0].AppID){
            $answer=[Windows.Forms.MessageBox]::Show('已找到开始菜单中的 ChatGPT。将通过 Windows 注册的入口启动，该方式不能保证继承单次代理变量；使用代理请先设置全局变量。是否打开？','启动 ChatGPT','YesNo','Information')
            if($answer -eq 'Yes'){Start-Process explorer.exe -ArgumentList ('shell:AppsFolder\'+$entry[0].AppID)}
            return
        }
        throw '商店版启动失败。请在 Windows 设置 → 应用 → 高级应用设置 → 应用执行别名中启用 ChatGPT，再重试。'
    }
}
function Save-ChatGPTProxy {
    $proxy=$field.Text.Trim();$uri=$null
    if(-not [Uri]::TryCreate($proxy,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'http' -or $proxy -notmatch ':\d+/?$' -or $uri.UserInfo){throw '请输入有效 HTTP 代理地址'}
    [IO.Directory]::CreateDirectory((Join-Path $env:LOCALAPPDATA 'ProxyHelper'))|Out-Null
    [IO.File]::WriteAllText((Join-Path $env:LOCALAPPDATA 'ProxyHelper\chatgpt-proxy.txt'),$proxy)
}
function New-ChatGPTShortcut {
    if(-not $HelperExe){throw '请从 EXE 启动工具'}
    $null=Get-ChatGPTPath;Save-ChatGPTProxy
    $shell=New-Object -ComObject WScript.Shell
    $link=$shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'ChatGPT - Green Proxy.lnk'))
    $link.TargetPath=$HelperExe;$link.Arguments='--chatgpt';$link.WorkingDirectory=Split-Path $HelperExe;$link.IconLocation=(Join-Path $RuntimeDirectory 'ChatGPT-Green.ico')+',0';$link.Save()
    [void][Windows.Forms.MessageBox]::Show('已创建绿色代理快捷方式。请完全退出已运行的 ChatGPT，再从新入口打开。','完成')
}
if($LaunchChatGPT){
    try{Launch-ChatGPTWithProxy}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'ChatGPT 启动失败')}
    exit
}
$form=New-Object Windows.Forms.Form
$form.Text='代理配置助手 · Windows'; $form.ClientSize=New-Object Drawing.Size(1000,850); $form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedSingle'; $form.MaximizeBox=$false
$form.AutoScaleMode='Dpi'; $form.Font=New-Object Drawing.Font('Microsoft YaHei UI',10); $form.BackColor=[Drawing.Color]::FromArgb(240,245,248)
$iconPath=Join-Path $RuntimeDirectory 'ProxyHelper.ico'; if(Test-Path $iconPath){$form.Icon=New-Object Drawing.Icon($iconPath)}

$script:uiBusy=$false;$script:networkPending=$false
function Set-Loading([bool]$enabled,[string]$message='') {
    $script:uiBusy=$enabled
    $tabs.Enabled=-not $enabled;$tools.Enabled=-not $enabled;$back.Enabled=-not $enabled
    $form.UseWaitCursor=$enabled
    $loading.Visible=$enabled
    if($enabled){$loading.Style='Marquee';if($message){$status.Text=$message}}else{$loading.Style='Blocks'}
    $form.Refresh();[Windows.Forms.Application]::DoEvents()
}
function Get-DetectionStatus([string]$proxy){
    $expected=@{HTTP_PROXY=$proxy;HTTPS_PROXY=$proxy;ALL_PROXY=$proxy;NO_PROXY='localhost,127.0.0.1,::1';NODE_USE_ENV_PROXY='1'}
    $path=Join-Path $HOME '.codex\.env';$map=@{}
    if(Test-Path $path){foreach($line in [IO.File]::ReadAllLines($path)){if($line -match '^\s*(HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY|NODE_USE_ENV_PROXY)\s*=\s*(.*)$'){$map[$Matches[1]]=$Matches[2]}}}
    $issues=@()
    foreach($key in $expected.Keys){
        foreach($scopeName in @('User','Machine')){if([Environment]::GetEnvironmentVariable($key,$scopeName) -ne $expected[$key]){$issues+="$scopeName/$key"}}
        if($map[$key] -ne $expected[$key]){$issues+=".env/$key"}
    }
    if(-not $issues.Count){return "检测地址 $proxy · 已应用：用户、全局环境和 .env 均一致。"}
    return "检测地址 $proxy · 有 $($issues.Count) 项缺失或不同，请应用同步。明细见当前配置。"
}
function Wait-Elevated($process){
    while(-not $process.HasExited){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 60;$process.Refresh()}
    $process.WaitForExit()
    return $process
}
function Add-Label($parent,[string]$text,[int]$x,[int]$y,[int]$w,[int]$h,[int]$size=10) {
 $v=New-Object Windows.Forms.Label; $v.Text=$text; $v.SetBounds($x,$y,$w,$h); $v.Font=New-Object Drawing.Font('Microsoft YaHei UI',$size); $parent.Controls.Add($v); return $v
}
function Add-Button($parent,[string]$text,[int]$x,[int]$y,[int]$w,$handler) {
 $b=New-Object Windows.Forms.Button; $b.Text=$text; $b.SetBounds($x,$y,$w,38); $b.FlatStyle='Flat'; $b.BackColor=[Drawing.Color]::FromArgb(245,249,251); $b.FlatAppearance.BorderColor=[Drawing.Color]::FromArgb(211,223,229); $b.FlatAppearance.MouseOverBackColor=[Drawing.Color]::FromArgb(224,242,244); $b.Cursor=[Windows.Forms.Cursors]::Hand; $b.ForeColor=[Drawing.Color]::FromArgb(30,55,65); $b.UseVisualStyleBackColor=$false
 $b.Tag=$handler
 $click={
    if($script:uiBusy){return}
    Set-Loading $true '正在处理，请稍候…'
    try{& $this.Tag}catch{$status.Text='操作失败：'+$_.Exception.Message;[void][Windows.Forms.MessageBox]::Show($form,$status.Text,'操作失败','OK','Error')}
    finally{if(-not $script:networkPending){Set-Loading $false}}
 }
 $b.Add_Click($click); $parent.Controls.Add($b); return $b
}
$null=Add-Label $form '代理配置助手' 25 18 700 40 22
$null=Add-Label $form '检测、同步、管理 ChatGPT 与 Codex 的代理配置' 28 64 740 30
$tabs=New-Object Windows.Forms.TabControl; $tabs.SizeMode='Fixed'; $tabs.ItemSize=New-Object Drawing.Size(226,40); $tabs.SetBounds(25,110,950,515); $form.Controls.Add($tabs)
$overview=New-Object Windows.Forms.TabPage; $overview.Text='概览'
$config=New-Object Windows.Forms.TabPage; $config.Text='当前配置'
$history=New-Object Windows.Forms.TabPage; $history.Text='历史与备份'
$startup=New-Object Windows.Forms.TabPage; $startup.Text='启动管理'

$tabs.TabPages.AddRange(@($overview,$config,$history,$startup))
foreach($tab in $tabs.TabPages){$tab.BackColor=[Drawing.Color]::White; $tab.Padding=New-Object Windows.Forms.Padding(15)}
$back=Add-Button $form '‹ 返回概览' 815 25 155 { $tabs.SelectedIndex=0 }
$tabs.Add_SelectedIndexChanged({$back.Visible=$tabs.SelectedIndex -ne 0; if($null -ne $status){Refresh-Views}})
$back.Visible=$false
$summary=Add-Label $overview '' 20 20 880 78 11; $summary.BackColor=[Drawing.Color]::FromArgb(231,245,246); $summary.ForeColor=[Drawing.Color]::FromArgb(22,79,88); $summary.Padding=New-Object Windows.Forms.Padding(14,12,8,8)
$null=Add-Label $overview '代理地址' 20 110 600 30 15
$null=Add-Label $overview '检测和测试连接不会写入配置；你也可以手动填写 HTTP 代理。' 20 150 880 30
$field=New-Object Windows.Forms.TextBox; $field.SetBounds(20,190,875,35); $field.Font=New-Object Drawing.Font('Consolas',15); $field.Text=Find-Proxy; $overview.Controls.Add($field)
$null=Add-Button $overview '重新检测' 20 250 150 { $value=Find-Proxy; if($value){$field.Text=$value; $status.Text=Get-DetectionStatus $value}else{$status.Text='未找到代理，请开启系统代理或手动填写。'}; Refresh-Views }
$null=Add-Button $overview '测试连接' 185 250 150 { Start-Operation 'test' }
$apply=Add-Button $overview '应用当前地址' 350 250 190 { Start-Operation 'apply' }; $apply.BackColor=[Drawing.Color]::FromArgb(10,125,135); $apply.ForeColor=[Drawing.Color]::White; $apply.FlatAppearance.MouseOverBackColor=[Drawing.Color]::FromArgb(8,100,110); $apply.FlatAppearance.MouseDownBackColor=[Drawing.Color]::FromArgb(6,80,90)
$null=Add-Button $overview '一键检测并应用' 555 250 220 { $value=Find-Proxy; if($value){$field.Text=$value; Start-Operation 'apply'}else{$status.Text='未检测到代理，请开启系统代理或手动填写。'} }
$startupOption=New-Object Windows.Forms.CheckBox; $startupOption.Text='登录后自动恢复代理配置'; $startupOption.SetBounds(20,315,500,32); $startupOption.Checked=Test-Startup; $startupOption.Visible=$true; $overview.Controls.Add($startupOption)

$null=Add-Label $overview '统一写入全局/用户环境与 .env；其他新启动应用（包括 ToDesk）也会继承代理。' 20 360 880 55
$null=Add-Label $overview '完成后请保存工作并完全退出、重新打开 ChatGPT / Codex。' 20 430 880 30
$clearButton=Add-Button $overview '清除代理配置' 640 315 235 {Clear-AllProxy}; $clearButton.ForeColor=[Drawing.Color]::FromArgb(185,60,60)
$report=New-Object Windows.Forms.TextBox; $report.Multiline=$true; $report.ReadOnly=$true; $report.ScrollBars='Both'; $report.SetBounds(20,20,880,385); $report.Font=New-Object Drawing.Font('Consolas',10); $config.Controls.Add($report)
$null=Add-Button $config '刷新配置' 20 425 145 { Refresh-Views; $status.Text='已刷新配置。' }
$null=Add-Button $config '复制诊断' 180 425 145 { [Windows.Forms.Clipboard]::SetText((Get-Report)); $status.Text='已复制代理诊断信息，不包含其他 .env 配置。' }
$null=Add-Button $config '打开 .env' 340 425 145 { $path=Join-Path $HOME '.codex\.env'; if(Test-Path $path){Start-Process notepad.exe -ArgumentList ('"'+$path+'"')}else{$status.Text='尚未创建 .env，请先应用代理。'} }
$null=Add-Button $config '打开配置目录' 500 425 185 { $path=Join-Path $HOME '.codex'; if(Test-Path $path){Start-Process explorer.exe -ArgumentList ('"'+$path+'"')} }
$null=Add-Label $history '操作历史与备份清理' 20 25 850 45 20
$null=Add-Label $history '查看操作记录、勾选或全选备份并批量删除。当前配置与历史日志会保留。管理窗口内也有返回按钮。' 20 90 880 75
$null=Add-Button $history '打开历史与备份管理' 20 200 285 { Show-History; Refresh-Views }
$null=Add-Button $history '打开日志目录' 325 200 200 { $path=Join-Path $env:LOCALAPPDATA 'ProxyHelper'; if(Test-Path $path){Start-Process explorer.exe -ArgumentList ('"'+$path+'"')} }
$startupStatus=Add-Label $startup '' 20 25 880 70 15
$null=Add-Label $startup '登录时自动恢复代理环境。添加或更新使用概览页的代理地址；移除会先备份，当前环境和 .env 保留。' 20 115 880 65
$null=Add-Button $startup '添加 / 更新启动项' 20 220 230 { Start-Operation 'startup' }
$null=Add-Button $startup '移除启动项' 270 220 180 {
 if([Windows.Forms.MessageBox]::Show('移除登录启动项？当前环境变量和 .env 将保留。','确认移除','YesNo','Question') -eq 'Yes') {
  try { Remove-Startup; $startupOption.Checked=$false; Write-History '移除登录启动项，保留当前代理配置'; Refresh-Views; $status.Text='已移除登录启动项。' } catch {$status.Text='移除未完成：'+$_.Exception.Message; Write-History $status.Text}
 }
}
$null=Add-Button $startup '刷新状态' 470 220 160 { Refresh-Views }
$null=Add-Label $startup ('登录脚本：'+(Join-Path $env:LOCALAPPDATA 'ProxyHelper\Set-ProxyEnv.ps1')+"`r`n`r`n端口改变后，请重新检测并应用。已运行程序需要重启刷新环境。") 20 310 880 110
$tools=New-Object Windows.Forms.Panel;$tools.SetBounds(25,635,950,110);$form.Controls.Add($tools)
$null=Add-Button $tools '设置全局变量并登录恢复' 0 0 285 { $startupOption.Checked=$true;Start-Operation 'apply' }
$null=Add-Button $tools '启动 ChatGPT' 300 0 205 {try{Save-ChatGPTProxy;Launch-ChatGPTWithProxy;$status.Text='已请求启动 ChatGPT；如程序已运行，请退出后重开。'}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'启动失败')}}
$null=Add-Button $tools '创建绿色 ChatGPT 桌面入口' 520 0 420 {try{New-ChatGPTShortcut}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'创建失败')}}
$appAuto=New-Object Windows.Forms.CheckBox;$appAuto.Text='登录后自动打开代理配置助手';$appAuto.SetBounds(0,58,560,34);$tools.Controls.Add($appAuto)
$runKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$existing=Get-ItemProperty $runKey -ErrorAction SilentlyContinue;$appAuto.Checked=($null -ne $existing -and $existing.PSObject.Properties.Name -contains 'ProxyHelperApp')
$appAuto.Add_Click({if($script:uiBusy){return};Set-Loading $true '正在保存启动设置…';try{
 if(-not $HelperExe){throw '请从 EXE 启动工具'}
 if(-not(Test-Path $runKey)){New-Item $runKey|Out-Null}
 if($appAuto.Checked){New-ItemProperty $runKey -Name 'ProxyHelperApp' -Value ('"'+$HelperExe+'"') -PropertyType String -Force|Out-Null}else{Remove-ItemProperty $runKey -Name 'ProxyHelperApp' -ErrorAction SilentlyContinue}
 $status.Text='已保存助手登录自启动设置。'
}catch{$appAuto.Checked=-not $appAuto.Checked;[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'设置失败')}finally{Set-Loading $false}})
$status=Add-Label $form '准备就绪。检测代理 → 测试连接 → 应用配置。' 28 762 940 70; $status.BackColor=[Drawing.Color]::FromArgb(224,237,242); $status.Padding=New-Object Windows.Forms.Padding(12,10,12,5)
function Refresh-Views {
 $report.Text=Get-Report
 $currentUser=[Environment]::GetEnvironmentVariable('HTTP_PROXY','User');$currentMachine=[Environment]::GetEnvironmentVariable('HTTP_PROXY','Machine')
 $summary.Text="系统 / 检测地址：$(Find-Proxy)`r`n已应用用户：$(if($currentUser){$currentUser}else{'未设置'})    全局：$(if($currentMachine){$currentMachine}else{'未设置'})    启动项：$(if(Test-Startup){'已安装'}else{'未安装'})"
 $startupStatus.Text="登录启动项：$(if(Test-Startup){'已安装'}else{'未安装'})`r`n作用范围：当前用户登录。全局环境变量另由系统级配置持久保存。"
}
$form.KeyPreview=$true; $form.Add_KeyDown({if($_.KeyCode -eq 'Escape' -and $tabs.Enabled){$tabs.SelectedIndex=0; $_.Handled=$true}; if($_.Control -and $_.KeyCode -eq 'R' -and $tabs.Enabled){Refresh-Views; $_.Handled=$true}})

$loading=New-Object Windows.Forms.ProgressBar;$loading.SetBounds(28,835,940,6);$loading.MarqueeAnimationSpeed=24;$loading.Visible=$false;$form.Controls.Add($loading)
$script:networkTimer=New-Object Windows.Forms.Timer; $script:networkTimer.Interval=100
function Start-Operation([string]$mode) {
 $uri=$null; $proxy=$field.Text.Trim().TrimEnd('/')
 if(-not [Uri]::TryCreate($proxy,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'http' -or $proxy -notmatch ':\d+/?$' -or $uri.Port -lt 1 -or $uri.Port -gt 65535 -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -ne '/') {$status.Text='请输入有效的 http://主机:端口，不支持账号密码。'; return}
 $script:operationMode=$mode; $script:operationProxy=$proxy; $script:operationStart=Get-Date
 $script:networkPending=$true; Set-Loading $true '正在验证代理 HTTPS 连接，最长等待 8 秒…'
 $script:networkTask=[ProxyConnection]::Test($proxy); $script:networkTimer.Start()
}
$script:networkTimer.Add_Tick({
 if(-not $script:networkTask.IsCompleted){return}; $script:networkTimer.Stop()
 try {
  $failure=$script:networkTask.Result
  if($failure){throw "连接失败，未修改配置：$failure"}
  switch($script:operationMode){
   'test' {$status.Text="连接成功（$([int]((Get-Date)-$script:operationStart).TotalMilliseconds) ms）。仅测试，未写入配置。"; Write-History $status.Text}
   'startup' {Set-Startup $script:operationProxy;$startupOption.Checked=$true;$status.Text='已更新登录启动项。';Write-History $status.Text}
   'apply' {Apply-Proxy $script:operationProxy $true}
  }
 } catch {$status.Text='操作未完成，若已开始写入则可能有部分配置更新：'+$_.Exception.Message; Write-History $status.Text}
 finally {$script:networkPending=$false;Set-Loading $false; Refresh-Views; [void][Windows.Forms.MessageBox]::Show($form,$status.Text,'操作结果','OK',$(if($status.Text -like '操作未完成*'){'Error'}else{'Information'}))}
})
Refresh-Views
[void]$form.ShowDialog()
