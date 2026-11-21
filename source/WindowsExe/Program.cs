using System;
using System.IO;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
class Program {
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int MessageBox(IntPtr h,string text,string title,uint type);
 [STAThread] static int Main(string[] args) {
  string root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"ProxyHelper");
  try {
   Directory.CreateDirectory(root);
   var version=Assembly.GetExecutingAssembly().ManifestModule.ModuleVersionId.ToString("N");
   var dir=Path.Combine(root,"Runtime",version);Directory.CreateDirectory(dir);
   var stable=Path.Combine(dir,"ProxyHelper.exe");
   if(!string.Equals(Environment.ProcessPath,stable,StringComparison.OrdinalIgnoreCase) && !File.Exists(stable))File.Copy(Environment.ProcessPath,stable,false);
   foreach(var name in new[]{"ProxyHelper.ps1","ProxyHelper.ico","ChatGPT-Green.ico"}) {
    var path=Path.Combine(dir,name);if(File.Exists(path))continue;
    using var src=Assembly.GetExecutingAssembly().GetManifestResourceStream(name);
    if(name.EndsWith(".ps1")) {using var reader=new StreamReader(src,System.Text.Encoding.UTF8,true);File.WriteAllText(path,reader.ReadToEnd(),new System.Text.UTF8Encoding(true));}
    else {using var dst=File.Create(path);src.CopyTo(dst);}
   }
   var start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell","v1.0","powershell.exe")){UseShellExecute=false,CreateNoWindow=true,RedirectStandardError=true,RedirectStandardOutput=true};
   foreach(var arg in new[]{"-NoLogo","-NoProfile","-ExecutionPolicy","Bypass","-STA","-WindowStyle","Hidden","-Command", "& { $ErrorActionPreference = 'Stop'; $p = $args[0]; $h = $args[1]; $text = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8); & ([ScriptBlock]::Create($text)) -HelperExe $h -RuntimeDirectory ([IO.Path]::GetDirectoryName($p)) " + (Array.IndexOf(args,"--chatgpt")>=0 ? "-LaunchChatGPT " : "") + "} '" + Path.Combine(dir,"ProxyHelper.ps1").Replace("'","''") + "' '" + stable.Replace("'","''") + "'"})start.ArgumentList.Add(arg);
   
   using var process=Process.Start(start);var errors=process.StandardError.ReadToEndAsync();var output=process.StandardOutput.ReadToEndAsync();process.WaitForExit();Task.WaitAll(errors,output);
   var details=errors.Result+Environment.NewLine+output.Result;
   File.WriteAllText(Path.Combine(root,"last-startup.log"),DateTime.Now+Environment.NewLine+"Exit="+process.ExitCode+Environment.NewLine+details);
   if(process.ExitCode!=0)MessageBox(IntPtr.Zero,"启动失败：\n"+details+"\n日志："+Path.Combine(root,"last-startup.log"),"代理配置助手",16);
   return process.ExitCode;
  }catch(Exception e){try{Directory.CreateDirectory(root);File.WriteAllText(Path.Combine(root,"last-startup.log"),e.ToString());}catch{}MessageBox(IntPtr.Zero,e.Message+"\n日志目录："+root,"代理配置助手启动失败",16);return 1;}
 }
}
