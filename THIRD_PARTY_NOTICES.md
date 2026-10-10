# 第三方组件 / Third-party components

本项目自有代码：AGPL-3.0-or-later。以下组件不因本项目的许可证而改变其原有授权。
Original project code: AGPL-3.0-or-later. Third-party components retain their original terms.

| Component | Use | Source / license notes |
| --- | --- | --- |
| LinkSwift 1.1.3 | Modified folder userscript | https://github.com/hmjz100/LinkSwift — AGPL-3.0-or-later; complete modified source and license in `userscript/`. Modification date and scope are preserved in the source header. |
| aria2 | HTTP download engine | https://github.com/aria2/aria2 — GPL-2.0-or-later; external executable bundled only during local builds. |
| libtorrent 2.1.1 | BT engine | https://github.com/arvidn/libtorrent — BSD-style license; see `backend/licenses/libtorrent-LICENSE.txt`. |
| Boost | libtorrent dependencies | https://www.boost.org/ — Boost Software License; see `backend/licenses/Boost-LICENSE.txt`. |
| yt-dlp / yt-dlp-ejs | Video extraction and JS challenge support | https://github.com/yt-dlp/yt-dlp and https://github.com/yt-dlp/ejs — see installed package license files copied by the build; dependent packages have their own terms. |
| FFmpeg | Audio/video processing | https://ffmpeg.org/ — license depends on enabled components and build configuration; inspect the actual Homebrew build before redistribution. |
| Node.js | JavaScript runtime | https://nodejs.org/ — MIT and bundled third-party notices. The checked-in notice is for v24.12.0; replace with the matching notice if bundling a different version. |
| Python / PyInstaller | Backend packaging | https://www.python.org/ and https://pyinstaller.org/ — Python PSF license and PyInstaller's license / bootloader exception apply. |

`bundle_*.py` and `bundle_bt.sh` collect package notices and Homebrew build receipts. This does not by itself fulfill every binary-redistribution obligation. Supply matching notices and any required corresponding sources when publishing a binary release. No prebuilt engine binaries are committed to this source repository.

打包脚本复制许可证和构建信息，但这不代表二进制分发义务已经全部完成。发布安装包前请核对实际依赖版本，提供对应许可证及所需的对应源代码。源码仓库不提交预构建引擎。
