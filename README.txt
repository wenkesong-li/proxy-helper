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

================ 使用场景与排障指南 ================
文档更新：2026-11-21

一、为什么做这个工具
浏览器能访问网页，但 ChatGPT/Codex 桌面端、工具子进程或终端连不上，常见原因是各进程读取的代理配置不同；代理软件换端口后，旧环境变量和登录脚本仍保留原端口，也可能造成连接异常。
本工具集中检测、写入、对照、备份和清除这些配置，减少重复手动修改。它不提供代理服务，不提升节点带宽，也不替代 VPN、防火墙或远程访问配置。

二、重点场景：反复重连，包括连续五次后失败
表现：请求中途断开、重复 reconnect/reconnecting、重试若干次后失败。
“重连五次”是观察到的表现，不是本工具确认的固定产品限制，也不能单凭次数判定为代理问题。
可能原因：旧端口、进程未继承代理、节点不稳定、长连接被代理/防火墙中断、认证过期、服务故障。
建议顺序：
1. 检查 OpenAI 服务状态：https://status.openai.com/
2. 确认代理软件已运行，工具检测出的主机和端口正确。
3. 测试连接，再应用配置；保存工作后完全退出并重新打开目标应用。
4. 对照实际进程/终端中的环境，不要只看配置文件的一致状态。
5. 若仍重连，更换节点或网络，对照是否为特定网络引起；检查组织网络的长连接策略。
官方网络指南说明了 WebSocket 等网络要求。普通 HTTPS 测试成功不代表流式连接能够持续稳定。
工具能处理配置不一致；不能保证修复服务端中断、认证和网络策略问题。

三、重点场景：内置浏览器打不开
先区分：浏览器工具没有创建窗口、窗口创建后导航失败、普通浏览器也打不开同一网站。
可能原因包括：工具运行时异常、权限或版本问题、子进程代理继承不同、目标网站限制、DNS/证书/网络问题。
本机排查中曾观察到 ChatGPT 主进程和 node_repl 子进程的代理环境并不相同；这说明主程序配置成功不能证明每个工具进程均已应用，不构成所有版本的行为保证。
操作：先用普通浏览器验证同一地址；在助手中测试并应用正确端口；保存工作后重启桌面应用，再创建内置浏览器。保留失败时间、具体错误、目标域名和应用版本。
仅在端口错误或环境未继承时，本工具的同步配置可能有效。不要把反复杀死 node_repl 当作通用修复，也不要因此结束其他任务。

四、重点场景：手机无法远程连接电脑
需要区分两个体系：
A. ChatGPT/Codex 手机远程：检查电脑端远程功能已启用、手机与电脑的账号/工作区一致、设备在线且未休眠、配对有效，以及工作区管理员是否允许远程访问。手机和电脑两边的网络都需要正常。
B. ToDesk 等第三方远控：检查该应用自身在线状态、权限、账号、节点及系统网络。
代理相关可能性：电脑宿主无法连接服务，或全局变量被其他应用继承，引起原本正常的远控连接异常。本机曾确认 ToDesk 主进程继承代理变量，但未通过受控对照试验证明代理就是其唯一故障原因。
手机上的 127.0.0.1 指手机本机，不是电脑；不要把电脑本地代理地址直接复制给手机。通常无需把本地代理端口暴露到公网。
建议：先确保电脑本地 ChatGPT/Codex 能正常工作，再在手机按官方流程配对；比较 Wi-Fi/蜂窝网络；检查休眠和工作区权限。第三方远控异常时可先备份并清除本工具的全局变量，再退出重开远控程序做对照，清除不会改变系统代理或 VPN。
若正在通过远控维护电脑，重启远控程序会断开连接，应先准备其他访问方式。

五、工具究竟改了哪里
Mac：当前用户 GUI 登录会话的 launchctl 环境、~/.codex/.env；可选登录恢复脚本 local.chatgpt.proxy-env。
Windows：当前用户/系统级环境变量、当前用户 .codex/.env；可选登录恢复脚本。系统级操作需管理员授权。
变量：HTTP_PROXY、HTTPS_PROXY、ALL_PROXY、NO_PROXY、NODE_USE_ENV_PROXY；Mac 同时处理小写代理变量。
NODE_USE_ENV_PROXY 是否被具体 Node 运行时支持/使用取决于版本和调用实现，设置为 1 不代表所有 Node 请求必然走代理。
NO_PROXY 是目标主机绕过列表，不能按应用名称排除 ToDesk。
全局设置会影响其他继承这些变量的程序。当前发布版不按应用选择代理。

六、如何使用
1. 启动代理软件，开启系统代理，确认本地 HTTP 端口。
2. 打开助手，重新检测，也可以填写 http://127.0.0.1:端口。
3. 测试连接，再应用当前地址。
4. 按需要启用登录恢复；Windows 可用“设置全局变量并登录恢复”。
5. 保存工作，完全退出需要刷新环境的应用，再重新打开。
6. 当前配置页面对照实际写入值；历史与备份页面可查看记录、勾选批量删除备份。
7. 更换代理端口后重新检测并应用。
“一致”只说明被比较的配置值相同，不证明网络可达、子进程已刷新、WebSocket 正常或下载速度正常。
当前发布包的连接验证使用 https://example.com，它只验证该测试目标的代理 HTTPS 请求，不是 OpenAI 全链路测试或速度测试。

七、清除与恢复
一键清除会处理本工具管理的代理环境变量、.env 代理项和登录恢复项，保留 .env 中其他配置，并保存备份。系统代理、VPN/TUN、Git 和 SSH 独立配置不因此清除。
新启动程序读取新环境，已经运行的程序仍需重启。部分终端配置、其他启动脚本可能重新注入代理；本工具不能自动清理所有第三方配置。
需要恢复时先记录原值或保留备份，重新应用所需端口。备份管理提供清理，不提供统一的一键回滚所有系统状态。删除备份无法撤销。

八、终端、Git 与下载慢
macOS launchctl 设置不等于当前终端已导出变量，.codex/.env 也不是通用 shell 启动文件。本工具当前不自动修改 .zshrc/.zprofile，不配置 SSH ProxyCommand。
在实际下载的终端执行：env | grep -i proxy
如果没有，可在当前 shell 临时设置：
export HTTP_PROXY=http://127.0.0.1:7891
export HTTPS_PROXY=$HTTP_PROXY
export ALL_PROXY=$HTTP_PROXY
端口按自己的配置替换。
HTTPS Git 示例：git -c http.proxy=http://127.0.0.1:7891 clone https://github.com/OWNER/REPO.git
SSH 地址 git@github.com:OWNER/REPO.git 不受 http.proxy 控制，不能用“已经设置 HTTP 代理”推断 SSH 已走代理。
下载还可能经过 codeload.github.com、release-assets.githubusercontent.com 等域名。代理软件的路由、节点带宽和重定向均会影响速度。
不要用只有几百字节的小文件测试估算大文件下载带宽。

九、Windows 特有说明
独立 EXE 无需另装 .NET，内部使用系统 Windows PowerShell 5.1。首次运行解包到当前用户固定运行目录。
全局按钮会写入用户与系统级值，并配置用户登录时恢复；“助手自启动”开关仅决定是否登录后打开助手界面，两者不同。
绿色 ChatGPT 快捷方式尝试在启动子进程时注入保存的代理值；先完全退出已运行的 ChatGPT。修改地址后重新保存快捷方式配置。
微软商店版可能禁止直接执行 WindowsApps 中的 EXE。工具尝试执行别名、包清单和开始菜单入口；商店激活不能保证继承单次环境变量，因此绿色图标并不意味着代理已生效。
当前版本存在 Windows 商店启动兼容性限制，尚未 Windows 实机完整验证。不能承诺仅靠绿色入口即可免全局配置。
启动错误日志：%LOCALAPPDATA%/ProxyHelper/last-startup.log
UTF-8 BOM 和显式 UTF-8 读取用于避免 Windows PowerShell 5.1 将中文脚本误读为本地编码。

十、反馈问题时提供什么
操作系统、应用/助手版本、故障时间、使用系统代理还是 VPN/TUN、端口、错误截图、是否重启过目标程序、配置对照摘要，以及 Windows 启动日志中的错误段。
先检查并遮盖 token、密码、Cookie、个人目录和敏感代理账号；不要上传整个环境变量列表或完整 .env。
一次只改变一个条件，分别记录“修改前表现、修改内容、修改后结果”。这能区分配置问题与节点/服务问题。

官方资料（核对日期 2026-11-21；产品功能可能随版本变化）
网络要求：https://help.openai.com/en/articles/9247338-network-recommendations-for-chatgpt-errors-on-web-and-apps
错误排查：https://help.openai.com/en/articles/7996703-troubleshooting-chatgpt-error-messages
远程连接：https://learn.chatgpt.com/docs/remote-connections
服务状态：https://status.openai.com/
以上用于网络与产品排障参考，不代表 OpenAI 对本第三方工具提供支持或保证。
