import Cocoa
import UniformTypeIdentifiers
let testMode = CommandLine.arguments.contains("--self-test")
let appHome = testMode ? FileManager.default.temporaryDirectory.appendingPathComponent("ProxyHelperTest-"+UUID().uuidString) : FileManager.default.homeDirectoryForCurrentUser
var mockEnvironment = [String:String]()
var mockLoaded = false

func run(_ path: String, _ args: [String]) -> (Int32, String) {
    if testMode && path == "/bin/launchctl" {
        switch args.first ?? "" {
        case "print": return (mockLoaded ? 0 : 1, "")
        case "bootstrap": mockLoaded=true;return (0,"")
        case "bootout": mockLoaded=false;return (0,"")
        case "unsetenv": mockEnvironment.removeValue(forKey:args[1]);return (0,"")
        case "setenv": mockEnvironment[args[1]]=args[2];return (0,"")
        case "getenv": return (0,mockEnvironment[args[1]] ?? "")
        default:return (1, "Unexpected mock command")
        }
    }
    if testMode && path == "/usr/sbin/scutil" { return (0,"HTTPEnable : 1\nHTTPProxy : 127.0.0.1\nHTTPPort : 18080\n") }
    let p = Process(); p.executableURL = URL(fileURLWithPath:path); p.arguments = args
    let out = Pipe(); p.standardOutput = out; p.standardError = out
    do { try p.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); return (p.terminationStatus, String(data:data,encoding:.utf8) ?? "") } catch { return (1,error.localizedDescription) }
}
func detected() -> String? {
    let (_, text) = run("/usr/sbin/scutil", ["--proxy"])
    var values = [String:String]()
    for line in text.components(separatedBy:"\n") {
        let pair = line.components(separatedBy:" : ")
        if pair.count == 2 { values[pair[0].trimmingCharacters(in:.whitespaces)] = pair[1].trimmingCharacters(in:.whitespaces) }
    }
    for prefix in ["HTTP", "HTTPS"] {
        if values[prefix+"Enable"] == "1", let host = values[prefix+"Proxy"], let port = values[prefix+"Port"], Int(port) != nil {
            return "http://\(host.contains(":") ? "[\(host)]" : host):\(port)"
        }
    }
    for key in ["HTTPS_PROXY", "HTTP_PROXY", "https_proxy", "http_proxy"] {
        let (_, value) = run("/bin/launchctl", ["getenv", key])
        let candidate = value.trimmingCharacters(in:.whitespacesAndNewlines)
        if validate(candidate) { return candidate }
        if let candidate = ProcessInfo.processInfo.environment[key], validate(candidate) { return candidate }
    }
    let env = appHome.appendingPathComponent(".codex/.env")
    if let content = try? String(contentsOf:env,encoding:.utf8) {
        for line in content.components(separatedBy:"\n") {
            let parts = line.components(separatedBy:"=")
            if parts.count == 2, ["HTTP_PROXY","HTTPS_PROXY","http_proxy","https_proxy"].contains(parts[0].trimmingCharacters(in:.whitespaces)), validate(parts[1].trimmingCharacters(in:.whitespaces)) { return parts[1].trimmingCharacters(in:.whitespaces) }
        }
    }
    return nil
}
func validate(_ raw: String) -> Bool {
    guard let u = URLComponents(string:raw), u.scheme == "http", let host = u.host, !host.isEmpty, let port = u.port, port > 0, port < 65536, u.user == nil, u.password == nil, u.query == nil, u.fragment == nil, u.path.isEmpty || u.path == "/" else { return false }; return true
}
func updateEnv(_ proxy: String) throws {
    let fm = FileManager.default, dir = appHome.appendingPathComponent(".codex")
    try fm.createDirectory(at:dir,withIntermediateDirectories:true)
    let file = dir.appendingPathComponent(".env")
    let old = fm.fileExists(atPath:file.path) ? try String(contentsOf:file,encoding:.utf8) : ""
    if fm.fileExists(atPath:file.path) { try fm.copyItem(at:file,to:dir.appendingPathComponent(".env.backup-\(UUID().uuidString)")) }
    let keys:Set<String> = ["HTTP_PROXY","HTTPS_PROXY","ALL_PROXY","http_proxy","https_proxy","all_proxy","NO_PROXY","no_proxy","NODE_USE_ENV_PROXY"]
    var lines = old.components(separatedBy:"\n").filter { line in
        var s = line.trimmingCharacters(in:.whitespaces)
        if s.hasPrefix("export ") { s = String(s.dropFirst(7)).trimmingCharacters(in:.whitespaces) }
        return !keys.contains(s.components(separatedBy:"=")[0].trimmingCharacters(in:.whitespaces))
    }
    while lines.last == "" { lines.removeLast() }
    for key in ["HTTP_PROXY","HTTPS_PROXY","ALL_PROXY","http_proxy","https_proxy","all_proxy"] { lines.append("\(key)=\(proxy)") }
    lines += ["NO_PROXY=localhost,127.0.0.1,::1","no_proxy=localhost,127.0.0.1,::1","NODE_USE_ENV_PROXY=1"]
    try (lines.joined(separator:"\n")+"\n").write(to:file,atomically:true,encoding:.utf8)
}
func installStartup(_ proxy: String) throws {
    let fm = FileManager.default, home = appHome
    let dir = home.appendingPathComponent("Library/Application Support/ChatGPTProxy")
    let agents = home.appendingPathComponent("Library/LaunchAgents")
    try fm.createDirectory(at:dir,withIntermediateDirectories:true)
    try fm.createDirectory(at:agents,withIntermediateDirectories:true)
    let script = dir.appendingPathComponent("set-proxy-env.sh")
    let plist = agents.appendingPathComponent("local.chatgpt.proxy-env.plist")
    for file in [script,plist] where fm.fileExists(atPath:file.path) {
        try fm.copyItem(at:file,to:URL(fileURLWithPath:file.path+".backup-"+UUID().uuidString))
    }
    // The value is restricted to a proxy URI; single quotes are escaped for the shell.
    let quoted = "'" + proxy.replacingOccurrences(of:"'",with:"'\"'\"'") + "'"
    let body = "#!/bin/sh\nset -eu\nfor key in HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy; do\n /bin/launchctl setenv \"$key\" " + quoted + "\ndone\nfor key in NO_PROXY no_proxy; do\n /bin/launchctl setenv \"$key\" 'localhost,127.0.0.1,::1'\ndone\n/bin/launchctl setenv NODE_USE_ENV_PROXY 1\n"
    try body.write(to:script,atomically:true,encoding:.utf8)
    try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:script.path)
    let config: [String:Any] = ["Label":"local.chatgpt.proxy-env","LimitLoadToSessionType":"Aqua","ProgramArguments":["/bin/sh",script.path],"RunAtLoad":true,"StandardErrorPath":dir.appendingPathComponent("launch-agent-error.log").path,"StandardOutPath":dir.appendingPathComponent("launch-agent.log").path]
    try PropertyListSerialization.data(fromPropertyList:config,format:.xml,options:0).write(to:plist,options:.atomic)
    let domain = "gui/\(getuid())"
    let loaded = run("/bin/launchctl",["print",domain+"/local.chatgpt.proxy-env"]).0 == 0
    if !loaded {
        let result = run("/bin/launchctl",["bootstrap",domain,plist.path])
        if result.0 != 0 { throw NSError(domain:"ProxyHelper",code:1,userInfo:[NSLocalizedDescriptionKey:"登录启动项加载失败："+result.1]) }
    }
}

let historyDir = appHome.appendingPathComponent("Library/Application Support/ChatGPTProxy")
func recordHistory(_ text:String) {
    do {
        try FileManager.default.createDirectory(at:historyDir,withIntermediateDirectories:true)
        let file = historyDir.appendingPathComponent("history.log")
        let old = (try? String(contentsOf:file,encoding:.utf8)) ?? ""
        try (old + DateFormatter.localizedString(from:Date(),dateStyle:.medium,timeStyle:.medium) + "  " + text.replacingOccurrences(of:"\n",with:" | ") + "\n").write(to:file,atomically:true,encoding:.utf8)
    } catch { NSLog("History write failed: %@",error.localizedDescription) }
}
func backupFiles() -> [URL] {
    let home=appHome
    let roots:[(URL,[String])] = [(home.appendingPathComponent(".codex"),[".env.backup-"]),(historyDir,["set-proxy-env.sh.backup-","environment.backup-"]),(home.appendingPathComponent("Library/LaunchAgents"),["local.chatgpt.proxy-env.plist.backup-"])]
    return roots.flatMap { dir,prefixes in
        ((try? FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey,.creationDateKey])) ?? []).filter { file in
            let values=try? file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            return values?.isRegularFile == true && values?.isSymbolicLink != true && prefixes.contains { file.lastPathComponent.hasPrefix($0) }
        }
    }.sorted { $0.path < $1.path }
}
let proxyKeys = ["HTTP_PROXY","HTTPS_PROXY","ALL_PROXY","http_proxy","https_proxy","all_proxy","NO_PROXY","no_proxy","NODE_USE_ENV_PROXY"]
let startupPlist = appHome.appendingPathComponent("Library/LaunchAgents/local.chatgpt.proxy-env.plist")
let startupScript = historyDir.appendingPathComponent("set-proxy-env.sh")
let envFile = appHome.appendingPathComponent(".codex/.env")
func envValues(_ text:String)->[String:String] {
    var result=[String:String]()
    for raw in text.components(separatedBy:.newlines) {
        var line=raw.trimmingCharacters(in:.whitespaces)
        if line.hasPrefix("export ") { line=String(line.dropFirst(7)).trimmingCharacters(in:.whitespaces) }
        guard let equal=line.firstIndex(of:"=") else { continue }
        let key=String(line[..<equal]).trimmingCharacters(in:.whitespaces)
        if proxyKeys.contains(key) { result[key]=String(line[line.index(after:equal)...]).trimmingCharacters(in:.whitespaces).trimmingCharacters(in:CharacterSet(charactersIn:"\"'")) }
    }
    return result
}
func startupLoaded()->Bool { run("/bin/launchctl",["print","gui/\(getuid())/local.chatgpt.proxy-env"]).0 == 0 }
func removeStartup() throws {
    let domain="gui/\(getuid())/local.chatgpt.proxy-env"
    if startupLoaded() {
        let result=run("/bin/launchctl",["bootout",domain])
        if result.0 != 0 { throw NSError(domain:"ProxyHelper",code:1,userInfo:[NSLocalizedDescriptionKey:result.1]) }
    }
    for file in [startupPlist,startupScript] where FileManager.default.fileExists(atPath:file.path) {
        try FileManager.default.copyItem(at:file,to:URL(fileURLWithPath:file.path+".backup-"+UUID().uuidString))
        try FileManager.default.removeItem(at:file)
    }
}
struct Snapshot {
    let system:String
    let environment:[String:String]
    let env:[String:String]
    let startup:String
    let startupExists:Bool
    let loaded:Bool
    init() {
        system=run("/usr/sbin/scutil",["--proxy"]).1
        var values=[String:String]()
        for key in proxyKeys { let value=run("/bin/launchctl",["getenv",key]).1.trimmingCharacters(in:.whitespacesAndNewlines); if !value.isEmpty { values[key]=value } }
        environment=values
        env=envValues((try? String(contentsOf:envFile,encoding:.utf8)) ?? "")
        startup=(try? String(contentsOf:startupScript,encoding:.utf8)) ?? ""
        startupExists=FileManager.default.fileExists(atPath:startupPlist.path)
        loaded=startupLoaded()
    }
    var systemProxy:String? {
        var v=[String:String]()
        for line in system.components(separatedBy:.newlines) { let pair=line.components(separatedBy:" : ");if pair.count == 2 { v[pair[0].trimmingCharacters(in:.whitespaces)]=pair[1].trimmingCharacters(in:.whitespaces) } }
        for prefix in ["HTTP","HTTPS"] {
            if v[prefix+"Enable"] == "1",let host=v[prefix+"Proxy"],let port=v[prefix+"Port"] { return "http://\(host.contains(":") ? "[\(host)]" : host):\(port)" }
        }
        return nil
    }
    var startupProxy:String? {
        guard let regex=try? NSRegularExpression(pattern:"http://[^'\\\"\\s]+"),let match=regex.firstMatch(in:startup,range:NSRange(startup.startIndex...,in:startup)),let range=Range(match.range,in:startup) else { return nil };return String(startup[range])
    }
    var consistent:Bool {
        guard let proxy=systemProxy ?? environment["HTTP_PROXY"] ?? env["HTTP_PROXY"] else { return false }
        let keys=Array(proxyKeys.prefix(6))
        return keys.allSatisfy { environment[$0] == proxy && env[$0] == proxy } && (!startupExists || (loaded && startupProxy == proxy)) && ["NO_PROXY","no_proxy"].allSatisfy { environment[$0] == "localhost,127.0.0.1,::1" && env[$0] == "localhost,127.0.0.1,::1" } && environment["NODE_USE_ENV_PROXY"] == "1" && env["NODE_USE_ENV_PROXY"] == "1"
    }
    var report:String {
        var lines=["代理配置助手 · 当前配置", "采集时间："+DateFormatter.localizedString(from:Date(),dateStyle:.medium,timeStyle:.medium),"系统 HTTP 代理："+(systemProxy ?? "未启用"),"登录启动项：\(startupExists ? "已安装" : "未安装") / \(loaded ? "已加载" : "未加载")","启动脚本代理："+(startupProxy ?? "未设置"),"共享配置对照："+(consistent ? "一致" : "存在缺失或差异，请点击一键应用同步"),"", "变量                          当前用户启动环境  /  Codex .env"]
        for key in proxyKeys { lines.append("\(key)\n  \(environment[key] ?? "未设置")  /  \(env[key] ?? "未设置")") }
        lines += ["","文件位置",envFile.path,startupPlist.path,startupScript.path,"","说明：读取当前用户 launchctl 环境，不代表已运行的 ChatGPT/Codex 进程已经刷新。"]
        return lines.joined(separator:"\n")
    }
}

struct ManagedApp:Codable { var path:String;var selected:Bool }
let appListFile=historyDir.appendingPathComponent("applications.json")
func loadApps()->[ManagedApp] {
    if let data=try? Data(contentsOf:appListFile),let items=try? JSONDecoder().decode([ManagedApp].self,from:data) { return items }
    return ["/Applications/ChatGPT.app","/Applications/Codex.app","/Applications/ToDesk.app"].filter { FileManager.default.fileExists(atPath:$0) }.map { ManagedApp(path:$0,selected:!$0.contains("ToDesk")) }
}
func shellQuote(_ s:String)->String { "'"+s.replacingOccurrences(of:"'",with:"'\"'\"'")+"'" }
func applyApplications(_ apps:[ManagedApp],_ proxy:String) throws {
    // Validate all targets before changing shared settings.
    let fm=FileManager.default
    for app in apps {
        guard let bundle=Bundle(path:app.path),bundle.executableURL != nil else { throw NSError(domain:"ProxyHelper",code:2,userInfo:[NSLocalizedDescriptionKey:"应用不可用："+app.path]) }
    }
    try fm.createDirectory(at:historyDir,withIntermediateDirectories:true)
    let launchers=historyDir.appendingPathComponent("应用启动入口")
    try fm.createDirectory(at:launchers,withIntermediateDirectories:true)
    for old in (try? fm.contentsOfDirectory(at:launchers,includingPropertiesForKeys:nil)) ?? [] {
        if Bundle(url:old)?.bundleIdentifier?.hasPrefix("local.proxyhelper.launcher.") == true { try fm.removeItem(at:old) }
    }
    for (i,app) in apps.enumerated() {
        let target=Bundle(path:app.path)!,name=URL(fileURLWithPath:app.path).deletingPathExtension().lastPathComponent
        let dir=launchers.appendingPathComponent("\(name)-\(i).app")
        let mac=dir.appendingPathComponent("Contents/MacOS");try fm.createDirectory(at:mac,withIntermediateDirectories:true)
        let resources=dir.appendingPathComponent("Contents/Resources");try fm.createDirectory(at:resources,withIntermediateDirectories:true)
        var script="#!/bin/sh\n# Managed by ProxyHelper\n"
        for key in proxyKeys { script += "unset \(key)\n" }
        if app.selected {
            for key in proxyKeys { let value=key == "NODE_USE_ENV_PROXY" ? "1" : (key.lowercased() == "no_proxy" ? "localhost,127.0.0.1,::1" : proxy);script += "export \(key)=\(shellQuote(value))\n" }
        }
        script += "exec \(shellQuote(target.executableURL!.path)) \"$@\"\n"
        let executable=mac.appendingPathComponent("launch");try script.write(to:executable,atomically:true,encoding:.utf8);try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:executable.path)
        var info:[String:Any] = ["CFBundleExecutable":"launch","CFBundleIdentifier":"local.proxyhelper.launcher.\(i)","CFBundleName":name+(app.selected ? " · 代理" : " · 默认"),"CFBundlePackageType":"APPL","CFBundleVersion":"1"]
        if let icon=target.object(forInfoDictionaryKey:"CFBundleIconFile") as? String,let source=target.url(forResource:(icon as NSString).deletingPathExtension,withExtension:"icns") {
            let dst=resources.appendingPathComponent("App.icns");if fm.fileExists(atPath:dst.path) { try fm.removeItem(at:dst) };try fm.copyItem(at:source,to:dst);info["CFBundleIconFile"]="App.icns"
        }
        try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:dir.appendingPathComponent("Contents/Info.plist"),options:.atomic)
    }
    var previous=[String:String]()
    for key in proxyKeys { let value=run("/bin/launchctl",["getenv",key]).1.trimmingCharacters(in:.whitespacesAndNewlines);if !value.isEmpty { previous[key]=value } }
    if !previous.isEmpty { try JSONEncoder().encode(previous).write(to:historyDir.appendingPathComponent("environment.backup-"+UUID().uuidString+".json"),options:.atomic) }
    // Remove legacy session-wide injection; selected apps receive variables only in their launchers.
    try removeStartup()
    for key in proxyKeys { let r=run("/bin/launchctl",["unsetenv",key]);if r.0 != 0 { throw NSError(domain:"ProxyHelper",code:2,userInfo:[NSLocalizedDescriptionKey:"清理全局变量失败："+key]) } }
    if apps.contains(where:{$0.selected && URL(fileURLWithPath:$0.path).lastPathComponent.lowercased().contains("codex")}) { try updateEnv(proxy) }
    else if fm.fileExists(atPath:envFile.path) {
        let old=try String(contentsOf:envFile,encoding:.utf8)
        try fm.copyItem(at:envFile,to:URL(fileURLWithPath:envFile.path+".backup-"+UUID().uuidString))
        let lines=old.components(separatedBy:"\n").filter { envValues($0).isEmpty }
        try lines.joined(separator:"\n").write(to:envFile,atomically:true,encoding:.utf8)
    }
    try JSONEncoder().encode(apps).write(to:appListFile,options:.atomic)
}
class Canvas:NSView {
    var fill:NSColor?;var rounded=false
    override var isFlipped:Bool { true }
    override func draw(_ rect:NSRect) {
        if let color=fill { color.setFill();let path=NSBezierPath(roundedRect:bounds,xRadius:rounded ? 14 : 0,yRadius:rounded ? 14 : 0);path.fill();if rounded { NSColor.separatorColor.withAlphaComponent(0.20).setStroke();path.lineWidth=1;path.stroke() } }
    }
}
class StyledButton:NSButton {
    var primary=false
    override func draw(_ dirtyRect:NSRect) {
        let chosen=primary || state == .on
        let accent=NSColor(calibratedRed:0.02,green:0.47,blue:0.52,alpha:1)
        let color=chosen ? accent : NSColor.controlBackgroundColor
        color.withAlphaComponent(isEnabled ? (isHighlighted ? 0.7 : 1) : 0.45).setFill()
        let path=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:9,yRadius:9);path.fill()
        if !chosen { NSColor.separatorColor.withAlphaComponent(0.35).setStroke();path.lineWidth=1;path.stroke() }
        let text=NSAttributedString(string:title,attributes:[.font:NSFont.systemFont(ofSize:13,weight:chosen ? .semibold : .regular),.foregroundColor:chosen ? NSColor.white : (isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor)])
        let size=text.size();text.draw(at:NSPoint(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2))
    }
}
func label(_ value:String,_ size:CGFloat=14,_ color:NSColor = .labelColor)->NSTextField {
    let v=NSTextField(wrappingLabelWithString:value);v.font = .systemFont(ofSize:size);v.textColor=color;return v
}
class Delegate:NSObject,NSApplicationDelegate {
    var window:NSWindow!; let root=Canvas();let body=Canvas();let field=NSTextField()
    let status=label("准备就绪",13,.secondaryLabelColor); let progress=NSProgressIndicator()
    var applications=loadApps();var appChecks=[NSButton]();var page=0;var busy=false;var controls=[NSControl]();var nav=[NSButton]();var checks=[NSButton]();var snapshot=Snapshot()
    let back=StyledButton(title:"‹ 返回概览",target:nil,action:nil)
    let startupOption=NSButton(checkboxWithTitle:"登录后自动恢复代理配置",target:nil,action:nil)
    var lastResult="检测代理 → 测试连接 → 应用配置。更换端口后重复一次即可。"
    func applicationDidFinishLaunching(_ notification:Notification) {
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1040,height:790),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title="代理配置助手";window.center();root.frame=NSRect(x:0,y:0,width:1040,height:790);window.contentView=root
        root.fill = NSColor.windowBackgroundColor
        let icon=NSImageView(frame:NSRect(x:26,y:20,width:48,height:48));icon.image=NSApp.applicationIconImage;root.addSubview(icon)
        put(label("代理配置助手",24),NSRect(x:86,y:20,width:460,height:32),root)
        put(label("让 ChatGPT 与 Codex 跟上你的代理设置",13,.secondaryLabelColor),NSRect(x:86,y:54,width:650,height:22),root)
        back.target=self;back.action=#selector(home);back.frame=NSRect(x:860,y:30,width:150,height:34);root.addSubview(back)
        for (index,title) in ["概览","当前配置","历史与备份","启动管理"].enumerated() {
            let b=StyledButton(title:title,target:self,action:#selector(navigate(_:)));b.tag=index;b.bezelStyle = .rounded;b.frame=NSRect(x:28+index*246,y:96,width:236,height:36);nav.append(b);root.addSubview(b)
        }
        body.frame=NSRect(x:28,y:150,width:984,height:555);root.addSubview(body)
        progress.isDisplayedWhenStopped=false;progress.style = .spinning;progress.controlSize = .small;progress.frame=NSRect(x:30,y:734,width:18,height:18);root.addSubview(progress)
        status.frame=NSRect(x:58,y:724,width:945,height:52);root.addSubview(status)
        field.stringValue=detected() ?? "";startupOption.state=snapshot.startupExists ? .on : .off
        installMenu();showPage(0);window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        if let i=CommandLine.arguments.firstIndex(of:"--render"),CommandLine.arguments.count>i+1 {
            let dir=CommandLine.arguments[i+1]
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
                do {
                    try FileManager.default.createDirectory(atPath:dir,withIntermediateDirectories:true)
                    for p in 0...3 {
                        self.showPage(p);self.root.layoutSubtreeIfNeeded();self.root.display()
                        let rep=self.root.bitmapImageRepForCachingDisplay(in:self.root.bounds)!;self.root.cacheDisplay(in:self.root.bounds,to:rep)
                        try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:dir+"/page-\(p).png"))
                    }
                    print("Rendered four pages")
                } catch { print(error) }
                NSApp.terminate(nil)
            }
        }
    }
    func installMenu() {
        let menu=NSMenu()
        let application=NSMenu();application.addItem(withTitle:"关于代理配置助手",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"");application.addItem(.separator());application.addItem(withTitle:"退出代理配置助手",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let appItem=NSMenuItem();appItem.submenu=application;menu.addItem(appItem)
        let edit=NSMenu(title:"编辑")
        for (name,action,key) in [("剪切","cut:","x"),("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")] { edit.addItem(withTitle:name,action:NSSelectorFromString(action),keyEquivalent:key) }
        let editItem=NSMenuItem(title:"编辑",action:nil,keyEquivalent:"");editItem.submenu=edit;menu.addItem(editItem)
        let view=NSMenu(title:"页面")
        for (i,title) in ["概览","当前配置","历史与备份","启动管理"].enumerated() { let item=NSMenuItem(title:title,action:#selector(navigateMenu(_:)),keyEquivalent:String(i+1));item.tag=i;item.target=self;view.addItem(item) }
        let refresh=NSMenuItem(title:"刷新当前页",action:#selector(refresh),keyEquivalent:"r");refresh.target=self;view.addItem(refresh)
        let viewItem=NSMenuItem(title:"页面",action:nil,keyEquivalent:"");viewItem.submenu=view;menu.addItem(viewItem)
        NSApp.mainMenu=menu
        back.keyEquivalent="\u{1b}"
    }
    @objc func navigateMenu(_ sender:NSMenuItem) { if !busy { snapshot=Snapshot();showPage(sender.tag) } }
    func put(_ view:NSView,_ frame:NSRect,_ parent:NSView?=nil) { view.frame=frame;(parent ?? body).addSubview(view) }
    @discardableResult func action(_ title:String,_ selector:Selector,_ x:CGFloat,_ y:CGFloat,_ width:CGFloat=160,_ primary:Bool=false)->NSButton {
        let b=StyledButton(title:title,target:self,action:selector);b.primary=primary;b.bezelStyle = .rounded
        if primary { b.bezelColor = .systemTeal;b.contentTintColor = .white }
        put(b,NSRect(x:x,y:y,width:width,height:36));controls.append(b);return b
    }
    func card(_ title:String,_ value:String,_ detail:String,_ x:CGFloat,_ width:CGFloat=316) {
        let view=Canvas();view.fill = NSColor.controlBackgroundColor;view.rounded=true;put(view,NSRect(x:x,y:0,width:width,height:116))
        put(label(title,12,.secondaryLabelColor),NSRect(x:18,y:14,width:width-36,height:20),view)
        put(label(value,18),NSRect(x:18,y:40,width:width-36,height:28),view)
        put(label(detail,12,.secondaryLabelColor),NSRect(x:18,y:79,width:width-36,height:28),view)
    }
    func textBox(_ text:String,_ frame:NSRect) {
        let scroll=NSScrollView(frame:frame);scroll.hasVerticalScroller=true;scroll.borderType = .noBorder
        let textView=NSTextView(frame:NSRect(x:0,y:0,width:frame.width-20,height:frame.height));textView.isEditable=false;textView.isSelectable=true;textView.font = .monospacedSystemFont(ofSize:12,weight:.regular);textView.textContainerInset=NSSize(width:14,height:12);textView.string=text
        textView.autoresizingMask = [.width];textView.textContainer?.widthTracksTextView=true;scroll.documentView=textView;body.addSubview(scroll)
    }
    func showPage(_ index:Int) {
        page=index;body.subviews.forEach { $0.removeFromSuperview() };controls=[];checks=[];back.isHidden=index==0
        for (i,b) in nav.enumerated() { b.state=i==index ? .on : .off;b.needsDisplay=true }
        switch index {
        case 0:
            card("检测到的系统代理",snapshot.systemProxy ?? "未启用","开启代理软件中的“系统代理”可自动读取。",0)
            card("配置一致性",snapshot.consistent ? "已同步" : "待同步","环境变量、Codex .env 与登录配置对照。",334)
            card("全局代理注入",snapshot.environment.isEmpty ? "已清除" : "仍有旧配置","当前用户新启动的应用会继承这些变量。",668)
            put(label("代理地址",18),NSRect(x:6,y:146,width:300,height:26))
            put(label("读取系统代理，也可以手动填写；检测和测试连接都不会写入配置。",13,.secondaryLabelColor),NSRect(x:6,y:180,width:960,height:26))
            field.placeholderString="http://127.0.0.1:端口";field.font = .monospacedSystemFont(ofSize:17,weight:.regular);put(field,NSRect(x:6,y:219,width:960,height:38));controls.append(field)
            action("重新检测",#selector(detectOnly),6,280,145)
            action("测试连接",#selector(testOnly),166,280,145)
            action("应用当前地址",#selector(applyAddress),326,280,185,true)
            action("一键检测并应用",#selector(autoApply),526,280,210)
            put(startupOption,NSRect(x:6,y:340,width:520,height:28));controls.append(startupOption)
            put(label("统一写入当前用户环境与 Codex .env；全局环境会影响其他新启动应用，包括 ToDesk。",13,.secondaryLabelColor),NSRect(x:6,y:377,width:955,height:44))
            let note=label("应用完成后，请保存工作并完全退出、重新打开 ChatGPT / Codex。\n端口变化后重新检测并应用，随后重启需要刷新环境的应用。",13,.secondaryLabelColor);put(note,NSRect(x:6,y:455,width:960,height:66))
        case 1:
            put(label("当前应用配置",23),NSRect(x:6,y:0,width:700,height:34))
            put(label("按来源对照代理变量，缺失值会标为“未设置”。仅展示代理相关配置。",13,.secondaryLabelColor),NSRect(x:6,y:45,width:960,height:28))
            let table=Canvas();table.fill = .controlBackgroundColor;table.rounded=true;put(table,NSRect(x:6,y:88,width:966,height:390))
            for (text,x,w) in [("变量",14.0,225.0),("当前用户启动环境",245.0,278.0),("Codex .env",533.0,278.0),("状态",829.0,110.0)] { put(label(text,12,.secondaryLabelColor),NSRect(x:x,y:15,width:w,height:24),table) }
            for (i,key) in proxyKeys.enumerated() {
                let row=Canvas();if i % 2 == 0 { row.fill = NSColor.quaternaryLabelColor.withAlphaComponent(0.055) };put(row,NSRect(x:8,y:48+i*35,width:950,height:35),table)
                let a=snapshot.environment[key] ?? "未设置",b=snapshot.env[key] ?? "未设置"
                for (text,x,w) in [(key,6.0,225.0),(a,237.0,278.0),(b,525.0,278.0)] { let v=label(text,12);v.lineBreakMode = .byTruncatingMiddle;v.maximumNumberOfLines=1;v.toolTip=text;put(v,NSRect(x:x,y:8,width:w,height:22),row) }
                let same=snapshot.environment[key] != nil && a == b
                put(label(same ? "一致" : (snapshot.environment[key] == nil && snapshot.env[key] == nil ? "未注入" : "不同"),12,same ? .systemTeal : .systemOrange),NSRect(x:821,y:8,width:110,height:22),row)
            }
            action("刷新配置",#selector(refresh),6,500)
            action("复制诊断信息",#selector(copyReport),180,500)
            action("打开 .env 文件",#selector(openEnv),354,500)
            action("打开配置目录",#selector(openFolder),528,500)
            action("清除代理配置",#selector(clearProxy),702,500,220)
        case 2:
            put(label("历史与备份",23),NSRect(x:6,y:0,width:650,height:34))
            put(label("操作记录从新版开始积累；勾选备份可批量清理，当前配置与历史日志会保留。",13,.secondaryLabelColor),NSRect(x:6,y:44,width:950,height:30))
            let log=(try? String(contentsOf:historyDir.appendingPathComponent("history.log"),encoding:.utf8)) ?? "暂无修改记录。"
            textBox(log.components(separatedBy:.newlines).reversed().joined(separator:"\n"),NSRect(x:6,y:85,width:966,height:155))
            let files=backupFiles();put(label("备份文件（\(files.count) 个）",15),NSRect(x:6,y:256,width:750,height:26))
            let scroll=NSScrollView(frame:NSRect(x:6,y:292,width:966,height:182));scroll.hasVerticalScroller=true
            let list=Canvas();list.frame=NSRect(x:0,y:0,width:940,height:max(182,files.count*34+12))
            let formatter=DateFormatter();formatter.dateFormat="yyyy-MM-dd HH:mm:ss"
            for (i,file) in files.enumerated() {
                let attrs=try? FileManager.default.attributesOfItem(atPath:file.path)
                let date=attrs?[.creationDate] as? Date ?? Date()
                let name=file.lastPathComponent.components(separatedBy:".backup-")[0]
                let size=(attrs?[.size] as? NSNumber)?.int64Value ?? 0
                let b=NSButton(checkboxWithTitle:"\(formatter.string(from:date))    \(name)    \(size) 字节",target:nil,action:nil);b.toolTip=file.path;b.identifier=NSUserInterfaceItemIdentifier(file.path);b.frame=NSRect(x:8,y:i*34+6,width:920,height:28);list.addSubview(b);checks.append(b);controls.append(b)
            }
            if files.isEmpty { put(label("暂无备份文件。",14,.secondaryLabelColor),NSRect(x:12,y:20,width:650,height:30),list) }
            scroll.documentView=list;body.addSubview(scroll)
            action("全选",#selector(selectEveryBackup),6,500,115)
            action("取消全选",#selector(selectNone),133,500,130)
            action("删除勾选备份",#selector(removeSelected),275,500,180)
            action("刷新列表",#selector(refresh),467,500,145)
            action("打开日志目录",#selector(openLogFolder),624,500,170)
        case 3:
            card("启动项状态",snapshot.startupExists ? "已安装" : "未安装",snapshot.loaded ? "当前登录会话已加载。" : "当前登录会话未加载。",0,482)
            card("登录时恢复的代理",snapshot.startupProxy ?? "未设置","启动脚本只恢复上次应用的端口。",502,482)
            put(label("管理登录启动项",23),NSRect(x:6,y:150,width:900,height:35))
            put(label("添加 / 更新登录启动脚本，登录后自动恢复已配置的代理环境。\n移除启动项保留当前环境变量和 .env 配置。",14,.secondaryLabelColor),NSRect(x:6,y:198,width:960,height:70))
            action("添加 / 更新启动项",#selector(addStartup),6,286,220,true)
            let remove=action("移除启动项",#selector(deleteStartup),244,286,180);remove.isEnabled=snapshot.startupExists || snapshot.loaded
            action("刷新状态",#selector(refresh),442,286,150)
            put(label("文件位置",16),NSRect(x:6,y:360,width:700,height:28))
            textBox(startupPlist.path+"\n\n"+startupScript.path,NSRect(x:6,y:400,width:966,height:95))
            action("在 Finder 中显示",#selector(revealStartup),6,513,205)
        default:
            put(label("仅勾选的应用使用代理",23),NSRect(x:6,y:0,width:950,height:34))
            put(label("勾选为正向选择；点击反选可按排除方式选择。取消勾选后重新应用，该应用入口将移除代理变量。",13,.secondaryLabelColor),NSRect(x:6,y:48,width:960,height:50))
            let scroll=NSScrollView(frame:NSRect(x:6,y:115,width:966,height:250));scroll.hasVerticalScroller=true
            let list=Canvas();list.frame=NSRect(x:0,y:0,width:940,height:max(250,applications.count*42+10));appChecks=[]
            for (i,app) in applications.enumerated() {
                let b=NSButton(checkboxWithTitle:URL(fileURLWithPath:app.path).deletingPathExtension().lastPathComponent+"    "+app.path,target:self,action:#selector(toggleApp(_:)));b.tag=i;b.state=app.selected ? .on : .off;b.frame=NSRect(x:10,y:i*42+6,width:910,height:32);list.addSubview(b);appChecks.append(b);controls.append(b)
            }
            scroll.documentView=list;body.addSubview(scroll)
            action("添加应用",#selector(addApp),6,385,140)
            action("全选",#selector(allApps),158,385,110)
            action("反选 / 排除",#selector(invertApps),280,385,155)
            action("一键应用勾选",#selector(applyAddress),447,385,190,true)
            action("打开启动入口",#selector(openLaunchers),649,385,190)
            action("清除代理配置",#selector(clearProxy),6,425,190)
            put(label("生效方式：应用时会清理旧全局代理变量和旧登录脚本。请先退出目标应用，再从“启动入口”打开。\n普通 Finder / Dock 入口不会注入代理；系统代理、VPN/TUN 和应用自己的网络设置仍可能生效。",13,.secondaryLabelColor),NSRect(x:210,y:438,width:760,height:104))
        }
        status.stringValue=lastResult;setBusy(busy)
    }
    func setBusy(_ value:Bool) { busy=value;controls.forEach { $0.isEnabled = !value };nav.forEach { $0.isEnabled = !value };back.isEnabled = !value;if value { progress.startAnimation(nil) } else { progress.stopAnimation(nil) } }
    func message(_ text:String) { lastResult=text;status.stringValue=text }
    @objc func navigate(_ sender:NSButton) { snapshot=Snapshot();showPage(sender.tag) }
    @objc func home() { if !busy { showPage(0) } }
    @objc func refresh() { guard !busy else { return };snapshot=Snapshot();showPage(page);message("已刷新当前配置与状态。") }
    @objc func detectOnly() { snapshot=Snapshot();guard let proxy=detected() else { showPage(page);message("未找到有效 HTTP 代理。请开启系统代理，或手动填写地址。");return };field.stringValue=proxy;showPage(page);message("已检测到 \(proxy)，尚未写入配置。") }
    @objc func testOnly() { perform(field.stringValue,mode:"test") }
    @objc func applyAddress() { perform(field.stringValue,mode:"apply") }
    @objc func autoApply() { guard let proxy=detected() else { message("未检测到代理，请开启系统代理或手动填写。");return };field.stringValue=proxy;perform(proxy,mode:"apply") }
    @objc func addStartup() { perform(field.stringValue,mode:"startup") }
    func perform(_ raw:String,mode:String) {
        guard !busy else { return };let proxy=raw.trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        guard validate(proxy) else { message("请输入有效的 http://主机:端口（1–65535），不支持账号密码。");return }
        let enableStartup=startupOption.state == .on
        setBusy(true);message("正在通过代理验证 HTTPS 连接，最长等待 8 秒…")
        DispatchQueue.global().async {
            let begin=Date();let check=run("/usr/bin/curl",["--noproxy","","--proxy",proxy,"--connect-timeout","4","--max-time","8","--silent","--show-error","--fail","--output","/dev/null","https://example.com"])
            var result="";var successful=false
            if check.0 != 0 { result="连接失败，未修改配置："+String(check.1.prefix(260)) }
            else if mode == "test" { result="连接成功（\(Int(Date().timeIntervalSince(begin)*1000)) ms）。仅测试，未写入配置。";successful=true }
            else {
                do {
                    if mode == "startup" { try installStartup(proxy);result="已更新登录启动项。" }
                    else {
                        try updateEnv(proxy)
                        for key in proxyKeys {
                            let value=key == "NODE_USE_ENV_PROXY" ? "1" : (key.lowercased() == "no_proxy" ? "localhost,127.0.0.1,::1" : proxy)
                            let result=run("/bin/launchctl",["setenv",key,value])
                            if result.0 != 0 { throw NSError(domain:"ProxyHelper",code:1,userInfo:[NSLocalizedDescriptionKey:"写入失败："+key]) }
                        }
                        if enableStartup { try installStartup(proxy) } else { try removeStartup() }
                        result="已同步环境变量、Codex .env 与登录启动配置。请重新启动需要刷新环境的应用。"
                    }
                    successful=true
                } catch { result="操作未完成，部分配置可能已更新："+error.localizedDescription }
            }
            recordHistory("\(mode) · \(proxy) · "+result)
            let current=Snapshot();let done=result;let success=successful
            DispatchQueue.main.async {
                self.snapshot=current;if success && mode == "startup" { self.startupOption.state = .on }
                self.setBusy(false);self.showPage(self.page);self.message(done)
            }
        }
    }
    @objc func deleteStartup() {
        guard !busy else { return }
        let alert=NSAlert();alert.messageText="移除本工具的登录启动项？";alert.informativeText="当前环境变量与 .env 会保留。脚本和启动配置将先备份。";alert.addButton(withTitle:"移除");alert.addButton(withTitle:"取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try removeStartup();recordHistory("移除登录启动项，保留当前代理配置");startupOption.state = .off;snapshot=Snapshot();showPage(page);message("已移除登录启动项，当前代理配置保持不变。") } catch { message("移除未完成："+error.localizedDescription);recordHistory(lastResult) }
    }
    @objc func clearProxy() {
        guard !busy else { return }
        let alert=NSAlert();alert.messageText="清除本工具管理的代理配置？";alert.informativeText="将备份并清除当前用户启动环境、Codex .env 代理项及登录项。系统代理与 VPN 保留。已运行程序需重启刷新。";alert.addButton(withTitle:"清除代理");alert.addButton(withTitle:"取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        setBusy(true);message("正在清除代理配置…")
        let targets=applications.filter { Bundle(path:$0.path)?.executableURL != nil }.map { ManagedApp(path:$0.path,selected:false) }
        DispatchQueue.global().async {
            var result:String
            do { try applyApplications(targets,"");result="代理环境、.env 和登录启动项已清除。新启动程序立即使用新环境；已运行程序请重启。" } catch { result="清除未完成，部分配置可能已更新："+error.localizedDescription }
            recordHistory(result);let done=result;let current=Snapshot()
            DispatchQueue.main.async { self.applications=loadApps();self.snapshot=current;self.setBusy(false);self.showPage(self.page);self.message(done) }
        }
    }
    @objc func showApps() { showPage(4) }
    @objc func toggleApp(_ sender:NSButton) { applications[sender.tag].selected=sender.state == .on }
    @objc func allApps() { for i in applications.indices { applications[i].selected=true };showPage(4) }
    @objc func invertApps() { for i in applications.indices { applications[i].selected.toggle() };showPage(4) }
    @objc func addApp() {
        let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.allowedContentTypes=[.applicationBundle];panel.allowsMultipleSelection=true;panel.directoryURL=URL(fileURLWithPath:"/Applications")
        if panel.runModal() == .OK { for url in panel.urls where !applications.contains(where:{$0.path == url.path}) { applications.append(ManagedApp(path:url.path,selected:true)) };showPage(4) }
    }
    @objc func openLaunchers() { let dir=historyDir.appendingPathComponent("应用启动入口");if FileManager.default.fileExists(atPath:dir.path) { NSWorkspace.shared.open(dir) } else { message("请先勾选应用并一键应用，随后生成启动入口。") } }
    @objc func copyReport() { NSPasteboard.general.clearContents();NSPasteboard.general.setString(snapshot.report,forType:.string);message("已复制代理诊断信息，不包含 .env 中其他配置。") }
    @objc func openEnv() { if FileManager.default.fileExists(atPath:envFile.path) { NSWorkspace.shared.open(envFile) } else { message("尚未创建 .env，请先应用代理配置。") } }
    @objc func openFolder() { NSWorkspace.shared.selectFile(envFile.path,inFileViewerRootedAtPath:envFile.deletingLastPathComponent().path) }
    @objc func openLogFolder() { NSWorkspace.shared.open(historyDir) }
    @objc func revealStartup() { NSWorkspace.shared.selectFile(startupPlist.path,inFileViewerRootedAtPath:startupPlist.deletingLastPathComponent().path) }
    @objc func selectEveryBackup() { checks.forEach { $0.state = .on } }
    @objc func selectNone() { checks.forEach { $0.state = .off } }
    @objc func removeSelected() {
        let paths=checks.filter { $0.state == .on }.compactMap { $0.identifier?.rawValue }
        guard !paths.isEmpty else { message("请先勾选要删除的备份文件。");return }
        let alert=NSAlert();alert.messageText="永久删除 \(paths.count) 个备份？";alert.informativeText="当前配置与操作历史会保留，此操作无法撤销。";alert.addButton(withTitle:"删除备份");alert.addButton(withTitle:"取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let allowed=Set(backupFiles().map { $0.path });var failures=[String]();var count=0
        for path in paths {
            guard allowed.contains(path) else { failures.append(path);continue }
            do { try FileManager.default.removeItem(atPath:path);count+=1 } catch { failures.append(path+": "+error.localizedDescription) }
        }
        recordHistory("删除备份 \(count) 个；失败 \(failures.count) 个");showPage(page);message("已删除 \(count) 个备份，失败 \(failures.count) 个。")
        if !failures.isEmpty { let alert=NSAlert();alert.messageText="部分备份未删除";alert.informativeText=failures.joined(separator:"\n");alert.runModal() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
}
if testMode {
    defer { try? FileManager.default.removeItem(at:appHome) }
    let fm=FileManager.default
    try fm.createDirectory(at:envFile.deletingLastPathComponent(),withIntermediateDirectories:true)
    try "OTHER_SETTING=keep\nHTTP_PROXY=http://old:1234\nexport HTTPS_PROXY=http://old:1234\nhttp_proxy=http://old:1234\n".write(to:envFile,atomically:true,encoding:.utf8)
    assert(validate("http://127.0.0.1:18080"));assert(!validate("socks5://localhost:18080"));assert(!validate("http://user:pass@localhost:80"));assert(!validate("http://localhost:65536"))
    let proxy="http://127.0.0.1:18080"
    try updateEnv(proxy)
    let content=try String(contentsOf:envFile,encoding:.utf8)
    assert(content.contains("OTHER_SETTING=keep"));assert(envValues(content)["HTTP_PROXY"] == proxy)
    assert(content.components(separatedBy:"\n").filter { $0.hasPrefix("HTTP_PROXY=") }.count == 1)
    try installStartup(proxy);assert(mockLoaded);assert(fm.fileExists(atPath:startupPlist.path))
    assert(run("/bin/sh",["-n",startupScript.path]).0 == 0)
    try installStartup(proxy)
    let script=try String(contentsOf:startupScript,encoding:.utf8);assert(script.contains(proxy))
    let link=envFile.deletingLastPathComponent().appendingPathComponent(".env.backup-link")
    try fm.createSymbolicLink(at:link,withDestinationURL:envFile)
    assert(!backupFiles().contains(link));assert(backupFiles().count == 3)
    for key in proxyKeys { mockEnvironment[key]=key == "NODE_USE_ENV_PROXY" ? "1" : (key.lowercased() == "no_proxy" ? "localhost,127.0.0.1,::1" : proxy) }
    assert(Snapshot().consistent)
    mockEnvironment["HTTPS_PROXY"]="http://127.0.0.1:18081";assert(!Snapshot().consistent)
    try removeStartup();assert(!mockLoaded);assert(!fm.fileExists(atPath:startupPlist.path));assert(!fm.fileExists(atPath:startupScript.path));assert(fm.fileExists(atPath:envFile.path))
    assert(backupFiles().count == 5)
    recordHistory("self-test");let testLog=try String(contentsOf:historyDir.appendingPathComponent("history.log"),encoding:.utf8);assert(testLog.contains("self-test"))
    let a=NSApplication.shared;let d=Delegate();d.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
    d.field.stringValue=proxy
    for page in 0...3 { d.showPage(page);assert(d.back.isHidden == (page == 0));d.setBusy(true);assert(d.controls.allSatisfy { !$0.isEnabled });d.setBusy(false) }
    d.home();assert(d.page == 0);assert(d.field.stringValue == proxy)
    d.showPage(2);d.selectEveryBackup();assert(d.checks.allSatisfy { $0.state == .on });d.selectNone();assert(d.checks.allSatisfy { $0.state == .off })
    // Exercise real launcher processes against a harmless fixture app.
    let fixture=appHome.appendingPathComponent("Fixture.app")
    let mac=fixture.appendingPathComponent("Contents/MacOS");try fm.createDirectory(at:mac,withIntermediateDirectories:true)
    let output=appHome.appendingPathComponent("captured-env")
    let executable=mac.appendingPathComponent("Fixture")
    try ("#!/bin/sh\n/usr/bin/env > "+shellQuote(output.path)+"\n").write(to:executable,atomically:true,encoding:.utf8)
    try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:executable.path)
    try PropertyListSerialization.data(fromPropertyList:["CFBundleExecutable":"Fixture","CFBundleIdentifier":"test.fixture","CFBundlePackageType":"APPL"],format:.xml,options:0).write(to:fixture.appendingPathComponent("Contents/Info.plist"))
    try applyApplications([ManagedApp(path:fixture.path,selected:true)],proxy)
    assert(mockEnvironment.isEmpty)
    let launcher=historyDir.appendingPathComponent("应用启动入口/Fixture-0.app/Contents/MacOS/launch")
    assert(run("/bin/sh",[launcher.path]).0 == 0)
    let captured=try String(contentsOf:output,encoding:.utf8);assert(envValues(captured)["HTTP_PROXY"] == proxy)
    try applyApplications([ManagedApp(path:fixture.path,selected:false)],"")
    assert(run("/bin/sh",[launcher.path]).0 == 0)
    let cleared=try String(contentsOf:output,encoding:.utf8);assert(envValues(cleared).isEmpty)
    assert(loadApps().first?.selected == false)
    let finalEnv=try String(contentsOf:envFile,encoding:.utf8);assert(finalEnv.contains("OTHER_SETTING=keep"));assert(envValues(finalEnv).isEmpty)
    print("PASS: selected launcher injection, unchecked launcher cleanup, global cleanup and app selection persistence")
    print("PASS: isolated env preservation, validation, backup filtering, startup add/remove, consistency, navigation, busy state, batch selection")
    try fm.removeItem(at:appHome)
    _ = a
    exit(0)
}

let app=NSApplication.shared
if let path=Bundle.main.path(forResource:"ProxyHelper",ofType:"icns"),let icon=NSImage(contentsOfFile:path) { app.applicationIconImage=icon }
app.setActivationPolicy(.regular);let delegate=Delegate();app.delegate=delegate;app.run()
