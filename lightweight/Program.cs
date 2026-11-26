using System;
using System.IO;
using System.Text;
using System.Reflection;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
class Launcher {
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int MessageBox(IntPtr h,string text,string title,uint flags);
 [STAThread] static int Main(string[] args) {
  string root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"ProxyHelper");
  try {
   string dir=Path.Combine(root,"Lightweight",Assembly.GetExecutingAssembly().ManifestModule.ModuleVersionId.ToString("N"));Directory.CreateDirectory(dir);
   string self=Assembly.GetExecutingAssembly().Location, stable=Path.Combine(dir,"ProxyHelper.exe");
   if(!File.Exists(stable))File.Copy(self,stable);
   foreach(string name in new[]{"ProxyHelper.ps1","ProxyHelper.ico","ChatGPT-Green.ico"}) {
    string file=Path.Combine(dir,name);if(File.Exists(file))continue;
    using(Stream stream=Assembly.GetExecutingAssembly().GetManifestResourceStream(name)) {
     if(name.EndsWith(".ps1")){using(var reader=new StreamReader(stream,Encoding.UTF8,true))File.WriteAllText(file,reader.ReadToEnd(),new UTF8Encoding(true));}
     else {using(var output=File.Create(file))stream.CopyTo(output);}
    }
   }
   string command="& { $p='"+Path.Combine(dir,"ProxyHelper.ps1").Replace("'","''")+"'; & ([ScriptBlock]::Create([IO.File]::ReadAllText($p,[Text.Encoding]::UTF8))) -RuntimeDirectory '"+dir.Replace("'","''")+"' -HelperExe '"+stable.Replace("'","''")+"'"+(Array.IndexOf(args,"--chatgpt")>=0?" -LaunchChatGPT":"")+" }";
   var start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell","v1.0","powershell.exe"));
   start.Arguments="-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand "+Convert.ToBase64String(Encoding.Unicode.GetBytes(command));
   start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardError=true;start.RedirectStandardOutput=true;
   using(var process=Process.Start(start)) {
    Task<string> error=process.StandardError.ReadToEndAsync(),output=process.StandardOutput.ReadToEndAsync();process.WaitForExit();Task.WaitAll(error,output);
    string details=error.Result+Environment.NewLine+output.Result;File.WriteAllText(Path.Combine(root,"last-startup.log"),details);
    if(process.ExitCode!=0)MessageBox(IntPtr.Zero,details,"代理配置助手启动失败",16);
    return process.ExitCode;
   }
  }catch(Exception e){MessageBox(IntPtr.Zero,e.Message,"代理配置助手",16);return 1;}
 }
}
