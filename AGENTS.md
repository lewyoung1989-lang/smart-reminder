# 文档约定

- 本仓库新增或修改的 Markdown 文档必须使用中文书写。
- 技术标识、命令、文件路径、API 路径、代码、依赖包名和不可翻译的标准术语可保留原文。

# GitHub 提交、推送与生产部署约定

- 当前主要工作区通常在 `/Users/liuyang/Desktop/own/smart-reminder/.worktrees/flutter-ui-ocr-integration`，当前主分支为 `main`。
- 提交前必须先看 `git status --short --branch`，不要提交用户或其他模型留下的无关改动。已知文档类改动也要按任务范围单独处理，不能顺手混入代码修复提交。
- 推送 GitHub 时，普通沙箱内 `git push` 可能无法访问本地代理；若失败，使用沙箱外执行并通过本机代理：
  `HTTPS_PROXY=http://localhost:7897 HTTP_PROXY=http://localhost:7897 git push origin main`
- 推送后用 `git ls-remote origin main` 或等价方式确认远程 SHA 与本地 HEAD 一致。
- 生产服务器为 `ubuntu@aipupu.cloud`，SSH 私钥路径为 `/Users/liuyang/.ssh/id_ed25519_smart_reminder`。不要输出、提交或记录任何密钥、Token、密码、API Key、`.env` 内容。
- 生产代码目录为 `/opt/smart-reminder/app`，环境文件为 `/opt/smart-reminder/shared/.env.production`。
- 部署前如果服务器 `main` 与 `origin/main` 不一致，先读 `git status --short --branch`、`git branch -vv` 和相关提交 diff；保留必要修复。若需要对齐远程，先创建 `backup/production-<short-sha>-<timestamp>` 备份分支，再切到目标 SHA。
- 部署命令使用仓库脚本并传入精确完整 SHA：
  `./deploy/tencent/scripts/deploy.sh <FULL_SHA> /opt/smart-reminder/shared/.env.production`
- 部署脚本会构建、迁移、检查 FunASR、检查 Nginx 和健康状态；不要跳过脚本中的回滚保护。
- 部署完成后至少确认三件事：公网 `https://aipupu.cloud/api/v1/health` 返回 OK，服务器 `git rev-parse HEAD` 等于目标 SHA，`api` 和 `funasr` 容器 healthy。

# iPhone 真机打包与安装约定

- 真机安装生产包时必须显式传入生产 API 地址，不能使用默认值。`AppConfig` 的默认 `API_BASE_URL` 是 `http://127.0.0.1:8000`，在 iPhone 上会指向手机本机，导致“无法连接服务器”。
- 生产真机安装命令使用：
  `../../../.tools/flutter/bin/flutter run -d <DEVICE_ID> --release --dart-define=API_BASE_URL=https://aipupu.cloud`
- 本地局域网调试时才使用 Mac 局域网 IP，例如：
  `../../../.tools/flutter/bin/flutter run -d <DEVICE_ID> --release --dart-define=API_BASE_URL=http://<MAC_LAN_IP>:8000`
- 每次真机安装前先确认将要使用的 API 地址，并在安装完成后用手机打开 App 验证登录或 `今天` 页面能连到服务器。
- 如果只是安装后释放设备连接，可以停止本机 `flutter run` 附着进程；这不会卸载手机上的 App。
