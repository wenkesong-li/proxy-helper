Proxy Helper / 代理配置助手

macOS 和 Windows 代理环境配置工具。
功能：检测系统代理、应用/清除代理环境变量、Codex .env、登录恢复、配置对照与备份管理。
Windows 还支持独立 EXE、助手登录自启动、ChatGPT 代理快捷方式。
全局代理会影响其他新启动应用；已运行进程需要重启刷新环境。

下载：GitHub Releases，分别选择 macOS-universal.zip 或 Windows-x64.exe。
Mac：解压后把应用拖入 Applications。Apple Silicon macOS 12+，Intel macOS 14+。
Windows：双击独立 EXE，无需另装 .NET，要求 Windows 10/11 x64 与 Windows PowerShell 5.1。
成品没有开发者签名/公证。Windows GUI/UAC 与商店版启动未在 Windows 实机完整验证。
微软商店 ChatGPT 会优先尝试执行别名/安装包清单/开始菜单入口。
商店激活入口不能保证继承单次代理变量；该情况下需要全局配置，不能承诺绿色入口单次代理生效。

源码：source/main.swift、Windows/ProxyHelper.ps1、source/WindowsExe。
Mac 编译：swiftc -target arm64-apple-macosx12.0 source/main.swift -o ProxyHelper-arm64
Intel：swiftc -target x86_64-apple-macosx14.0 source/main.swift -o ProxyHelper-x86_64
使用 lipo -create 合并，应用资源使用 source/ProxyHelper.iconset 生成 icns。
Windows 打包：dotnet publish source/WindowsExe/ProxyHelper.csproj -c Release -o WindowsExe
需要 .NET 10 SDK；最终 EXE 自带运行时。PowerShell 脚本必须保留 UTF-8 BOM。

运行数据：Mac ~/Library/Application Support/ChatGPTProxy；Windows %LOCALAPPDATA%/ProxyHelper。
本仓库不包含用户运行数据、代理日志或实际配置。
