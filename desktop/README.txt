Electron 5.0 Windows 预览重构
基于 Electron（MIT）与 electron-builder（MIT）。源码和依赖版本记录在 package.json。
本版本：用户环境、Codex .env、连接测试、配置对照、登录恢复。
尚未迁移：系统级写入、历史备份管理界面、ChatGPT 绿色快捷方式。旧版功能没有删除，仍保留在 Windows 目录。
启动无需网络成功，后台操作 25 秒超时，网络测试 8 秒超时。默认不开 GPU 加速以减少驱动兼容问题。
构建：cd desktop && npm install && npm run build
运行：解压 ZIP 后启动 ProxyHelper.exe，不能只复制 EXE。
Windows CI 会检查成品是否能启动并出现主窗口；这不等于已在用户 Win11 环境完成全部验证。
