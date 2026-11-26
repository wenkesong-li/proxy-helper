Windows 轻量版：使用 Windows 内置 .NET Framework 编译，无需 Chromium、Electron 或额外 .NET 运行时。
完整功能沿用 Windows/ProxyHelper.ps1，EXE 内嵌脚本和图标，首次运行解包至当前用户目录。
目标 Windows 11 x64。启动异常记录在 %LOCALAPPDATA%/ProxyHelper/last-startup.log。
编译命令见 .github/workflows/windows-lightweight.yml，使用系统自带 csc.exe。
