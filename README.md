# 疾风下载 · Surge Download

**轻量、清爽的 macOS 原生下载管理器。** 在一个窗口里管理直链、磁力、种子和视频下载。

**简体中文** · [English](README_EN.md)

![macOS](https://img.shields.io/badge/macOS-15%2B-black) ![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-arm64-blue) ![Version](https://img.shields.io/badge/version-0.4.0-blue) ![License](https://img.shields.io/badge/license-AGPL--3.0--or--later-green)

> 目前为早期 Demo。软件本身不设置下载速度上限，但实际速度取决于源站、账号权限、网络和 BT 节点。不是网盘会员替代品，也不承诺突破服务端限速。

## 下载

### [⬇ 下载 Mac Apple Silicon 版 v0.4.0（ZIP，约 121 MiB）](https://github.com/zhengkai400/surge-download/releases/download/v0.4.0/SurgeDownload-v0.4.0-macOS-arm64.zip)

[查看发行说明、校验文件和对应源码](https://github.com/zhengkai400/surge-download/releases/tag/v0.4.0)

适用于 **Apple Silicon（M 系列）Mac · macOS 15+**。下载 ZIP，解压后将「疾风下载.app」拖到「应用程序」。不是 Intel / Windows 版；当前为未公证的早期预览版，首次打开按 macOS 系统提示确认。GitHub 自动生成的 `Source code` 不是可直接运行的应用。

## 界面预览

![疾风下载主界面：侧边栏分类、任务表格和底部任务详情](docs/images/main-window.png)

*截图来自应用的独立界面预览，文件名、速度和进度为示例数据，不代表测速结果；不包含私人下载记录或登录信息。当前应用界面为中文，文档提供中英双语。*

- **左侧分类**：全部任务、下载中、已暂停、已完成、下载出错、BT / 磁力。
- **顶部输入**：粘贴下载链接，点击「新建下载」确认目录与选项。
- **任务表格**：文件大小、进度、实时速度、状态，以及暂停、继续、移除操作。
- **底部详情**：点击任务查看剩余时间、已下载大小、当前连接数、保存位置；支持打开 Finder。
- **右上角更多菜单**：一键清除已完成记录，只清记录、不删除文件。

## 功能一览

| 功能 | 当前实现与范围 |
| --- | --- |
| HTTP / HTTPS | aria2 多连接分段下载，默认每任务最多 8 个连接；源站须支持相应请求，连接数不等于速度倍数 |
| BT / 磁力 | 导入 `.torrent` 或 magnet，libtorrent 处理元数据、DHT / Tracker 与节点连接；支持 BT v1 / 混合种子 |
| 任务管理 | 搜索、分类、暂停、继续、全部开始 / 暂停、完成记录清除；退出后保留断点和历史 |
| 视频网页 | 使用 yt-dlp 解析单个视频页面；自动识别 YouTube、B站、小红书、抖音等入口，其他支持站点可勾选「按视频网页解析」；识别入口不等于保证该站可下载 |
| 视频画质 | 最佳 / 4K / 1080p / 720p / 480p 优先级，无匹配时回退可用版本；音视频分离时通过 FFmpeg 合并，必要时输出 MKV |
| 音频提取 | 「仅音频 · MP3」使用 FFmpeg 转为 MP3 |
| 网盘推送 | 接收 LinkSwift 通过本机 Aria2 接口推送的 HTTP 任务；当前含 Cookie 的推送仅接受夸克 HTTPS 域名 |
| 文件夹推送（实验） | 附带 LinkSwift 文件夹适配源码，递归展开夸克目录并保留相对路径；在线接口兼容性尚需更多验证 |
| 保存与上传设置 | 自定义新任务保存目录；BT 上传上限可选 256 KB/s、1 MB/s、5 MB/s、不限速 |

### 已知限制（请先阅读）

- **抖音仍存在解析失败**：本机测试返回 HTTP 403。社区 `a_bogus` 补丁测试未解决目标链接，未并入正式代码。关闭网页登录窗后能播放，不代表 yt-dlp 的接口请求一定成功。
- **视频站点支持会变化**：小红书、YouTube 的部分链接已实测成功，不代表全站保证。403、签名失效、地区和账号限制仍可能发生。出错后可尝试重新解析；不保证重试成功。
- 不自动读取浏览器 Cookie；暂不支持播放列表批量下载、字幕选择和视频缩略图预览。
- 纯 BT v2 暂不支持。磁力资源缺少可用节点时可能长时间等待元数据；支持导入原始种子文件。
- 视频任务使用独立队列，最多同时 2 个任务；不与 aria2 普通任务并发设置联动。
- 多账号合并、多源账号测速只做过本地实验，**不是已发布功能**。
- 目前只有 Apple Silicon 构建，未提供 Intel / Windows / Linux 版本；未做 Apple 公证。

## 开始使用

### 1. 启动应用

从上方下载应用 ZIP，解压后打开「疾风下载.app」；也可从源码构建。升级时先退出旧版，不要同时运行两个实例，已有任务数据保留。

### 2. 普通直链、磁力和种子

1. 在顶部粘贴链接，点击「新建下载」（`⌘N`）。新增弹窗支持每行一个链接。
2. 检查保存目录，点击「开始下载」。
3. 种子文件可从侧边栏「导入种子」选择，也可使用文件菜单。
4. 点击表格中的任务查看详情；行末按钮或右键菜单提供暂停 / 继续、Finder 显示和移除。

### 3. 修改保存路径

左侧 **设置 → 保存目录 → 更改…**，或在新建下载弹窗中更改目录。只影响之后新建的任务，不自动搬移已有文件。BT 和视频任务会使用独立子目录。

### 4. 下载视频或提取音频

1. 粘贴具体视频页面地址；分享文案中的单个 HTTP 链接会被提取。
2. 已识别站点自动走视频解析；其他站点勾选「按视频网页解析」。
3. 选择优先画质；仅需声音则勾选「仅音频 · MP3」。
4. 开始下载，等待视频 / 音频轨下载与合并完成。合并阶段或切换轨道时进度显示可能变化。

### 5. LinkSwift 网盘推送

1. 在浏览器安装并启用 [LinkSwift](https://github.com/hmjz100/LinkSwift)，在浏览器完成网盘登录。
2. 疾风左侧「网盘推送」→ 开启允许推送。
3. 将页面显示的主机、端口、路径和专用密钥填入 LinkSwift 的 **Aria2 服务设置**。存储路径留空，由疾风控制目录。
4. 测试连接后选中文件，再通过 Aria2 推送。
5. 整个目录的实验适配见 [文件夹脚本说明](userscript/README.md)。请先用小目录测试。

### 6. 清除记录

右上角 **⋯ → 一键清除已完成记录**。保留已下载文件；单个任务的移除同样不删除磁盘文件。

## 网络、隐私与安全

- 控制接口仅监听本机回环地址。主引擎使用随机端口 / 密钥；外部推送接口默认关闭，并使用独立密钥、请求来源和方法限制。
- HTTP 请求未主动配置外部代理，但系统 VPN / TUN 仍可能影响出口。视频解析器可使用系统代理。
- BT 节点连接在系统 SOCKS5 已配置时使用该代理；**DHT 发现仍直连，会暴露本机网络 IP**，不是匿名下载器。
- BT 下载时会向其他节点上传，默认总上传上限 1 MB/s，完成后停止做种。
- 配置、历史、断点和可能含 Cookie / 签名 URL 的会话存在 `~/Library/Application Support/SurgeDownload`，目录 / 敏感文件采用受限权限。
- 不要上传该运行目录、Cookie、签名直链或 RPC 密钥。报告问题时只提交脱敏日志。
- 不扫描剪贴板、不安装开机服务、不自动打开下载的可执行文件。
- 请仅下载有权访问与保存的内容，并遵守网站服务条款。

## 从源码构建

需要 macOS 15+、Apple Silicon、Xcode Command Line Tools、Homebrew、Python 3.13、aria2、FFmpeg 和 Node.js。现有打包流程使用 Homebrew 的 `/opt/homebrew` 布局。

```bash
xcode-select --install   # 已安装可跳过
brew install python@3.13 aria2 ffmpeg node@24
git clone https://github.com/zhengkai400/surge-download.git
cd surge-download
/opt/homebrew/bin/python3.13 -m venv .venv
.venv/bin/python -m pip install -r backend/requirements-build.txt
export NODE_BINARY="$(brew --prefix node@24)/bin/node"
./build.sh
open build/疾风下载.app
```

`NODE_BINARY` 可指定本机 Node 可执行文件；默认尝试 PATH 和 `/usr/local/bin/node`。构建会将依赖复制到应用内并进行 ad-hoc 签名，不会申请 Apple 公证。首次使用系统若提示安全确认，请检查源码及来源后按系统界面处理，不需要关闭系统安全保护。

### 本地测试

```bash
.venv/bin/python tests/bridge_integration.py
.venv/bin/python tests/linkswift_integration.py
.venv/bin/python tests/video_integration.py
.venv/bin/python tests/video_redirects.py
.venv/bin/python tests/folder_paths.py
node --test tests/folder.test.cjs
```

本地测试覆盖 HTTP / BT 引擎、推送边界、视频下载与 MP3 输出、暂停续传和记录保留等。第三方站点仍需独立在线验证，测试通过不等于所有资源可用。

## 项目结构

```text
Sources/            SwiftUI 界面、任务管理与本机 RPC 客户端
backend/            BT / HTTP 桥接、LinkSwift 接收器与视频工作进程
userscript/         LinkSwift 文件夹实验适配与原许可证
tests/              本地集成测试与路径 / 输入解析测试
docs/images/        脱敏界面截图
build.sh            构建 macOS 应用
bundle_*.py / .sh    引擎、依赖和许可证打包
```

## 许可证与致谢

本项目自有代码采用 **AGPL-3.0-or-later**，详见 [LICENSE](LICENSE)。第三方代码保留各自许可证与作者信息，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

感谢 [aria2](https://github.com/aria2/aria2)、[libtorrent](https://github.com/arvidn/libtorrent)、[yt-dlp](https://github.com/yt-dlp/yt-dlp)、[FFmpeg](https://ffmpeg.org/) 和 [LinkSwift](https://github.com/hmjz100/LinkSwift)。再分发包含第三方引擎的二进制包前，需要独立履行所有相应许可证及对应源代码交付义务；发行版的对应源码、依赖源码与构建配方随 Releases 的 `Corresponding-Sources` 附件提供。
