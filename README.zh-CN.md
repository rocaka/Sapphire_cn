# Sapphire 中文版

基于 [cshariq/Sapphire](https://github.com/cshariq/Sapphire) 的简体中文分支，保留上游版权、历史和 AGPL-3.0 许可证。上游基准：`792f9b4ea3d556d7566fbc38592fe54e88d89dc0`。

## 中文支持

提供简体中文与英文资源，覆盖首次启动、权限引导、设置、常用小组件与操作提示。中文系统自动使用简体中文；也可在 macOS「系统设置 → 通用 → 语言与地区 → 应用程序」中为 Sapphire 选择中文或 English，然后重启应用。文件名、歌曲名、便笺、终端输出等用户内容保持原文。上游新增文案、第三方返回的错误和开发调试界面可能仍显示英文。

设置侧边栏支持中英文搜索。设置助手仍受 Apple 智能、系统版本和地区可用性限制。

## 音乐界面自定义

打开「音乐 → 播放器 → 播放器外观」，可调整宽度、封面大小与圆角、标题/歌手/歌词字号、控件比例和强调色，并分别显示或隐藏封面、歌手、进度和内嵌歌词。提供默认、紧凑、大字预设、恢复默认和不启动播放器的静态预览。所有来源共用外观设置，详细播放器与锁屏会按各自显示器限制宽度。

开启「独立自定义网易云按钮」后，可单独显示、隐藏和排序红心、列表、随机、循环、设备按钮；前两个已启用按钮位于主控制栏。默认关闭独立模式，保留现有推荐布局。外观设置不会改变网易云收藏所需的系统授权。

打开「音乐 → 歌词 → 刘海下方桌面歌词」可启用独立歌词，调整字号、颜色、宽度、与刘海的间距、背景不透明度、第二行译文和暂停时隐藏。默认关闭；开启后播放器收起也能显示，鼠标点击穿透，刘海展开、锁屏、休眠或按已有应用/全屏规则隐藏时不显示。沿用同一歌词源和按歌词时间点更新的计时器，不另设轮询；没有当前歌词时不显示占位条。

社区版另提供原生文本片段、Finder剪切粘贴和系统监控页。输入类功能默认关闭、需要辅助功能权限，状态会显示在相应设置页；不支持的控件和输入法组合输入会跳过。Finder图片粘贴PNG、F2重命名及其它未实现项目仍保留为不可用，详见 [功能进度](FEATURES.zh-CN.md)。

## 下载与构建

本轮新增音乐界面自定义、刘海下方桌面歌词及本地工具，并修复下载进度刷新引起的刘海闪烁，请从 [最新功能预览版](https://github.com/rocaka/Sapphire_cn/releases/tag/cn-2026.10.29-progress-fix) 下载 `Sapphire-CN.zip`。退出旧版，解压后将 `Sapphire.app` 放入「应用程序」并替换旧版，再从该位置打开。发布附件使用公开链接，无需登录 GitHub；预览版说明列出仍待实机验收的操作。其他版本见 [全部发布](https://github.com/rocaka/Sapphire_cn/releases)。

开发中的构建可在 [Actions](https://github.com/rocaka/Sapphire_cn/actions/workflows/build-cn.yml) 下载 `Sapphire-CN-Release-universal` artifact（通常需要登录 GitHub）。只有绿色成功的构建才代表已通过编译与签名验证；日志 artifact 不代表有可安装程序。

本地需要完整 Xcode、macOS SDK 和 GitHub 网络连接：

```sh
git clone https://github.com/rocaka/Sapphire_cn.git
cd Sapphire_cn
python3 scripts/check-localization.py
scripts/build-cn.sh
```

输出为 `build-cn/Sapphire-CN.zip` 和 SHA-256 文件。Release 默认按项目配置构建通用架构（Apple Silicon 与 Intel）；捆绑的第三方设备工具仍受上游二进制架构限制。请以构建日志中 `lipo -archs` 的实际结果为准。`CONFIGURATION=Debug BUILD_ARCHS=arm64 scripts/build-cn.sh` 可快速构建 Apple Silicon 调试版。Actions 的手动运行也可选择配置和架构；调试版用于验证，不代替通用 Release。

## 签名与权限

默认使用 ad-hoc（临时）签名，不需要原作者的开发者账户。构建后从内到外重签嵌套二进制、框架、扩展和主程序，再运行 `codesign --verify --deep --strict`。中文版使用独立的 `com.rocaka.sapphirecn` 应用标识及辅助服务标识，避免与上游共用权限和后台服务。

**临时签名不等于 Apple Developer ID 签名或 Apple 公证。** 首次打开可能被 Gatekeeper 阻止；先尝试打开，再通过「系统设置 → 隐私与安全性 → 仍要打开」批准。不要全局关闭 Gatekeeper。更新或重新签名后，macOS 可能要求重新授予辅助功能、屏幕录制等权限。

若系统的辅助功能开关已开启，但 Sapphire 内部仍显示未授权，可能是该条目仍绑定更新前的临时签名。请先退出旧副本，在系统辅助功能列表移除旧 Sapphire，再添加「应用程序」中的新版并开启，最后重新启动新版。网易云设置中的「显示当前 Sapphire 所在位置」可帮助确认运行的是哪一份应用；「检查网易云连接」会显示当前进程实际授权状态、源码版本及原生菜单错误，不读取系统权限数据库或自动修改授权。

上游辅助服务会拒绝临时签名客户端执行 root 操作。本分支保留此校验，因此默认构建无法保证电池充电控制、风扇和其他特权功能可用。**不要通过删除辅助服务校验来解决。** 需要正式签名时，在本机钥匙串安装自己的 Developer ID Application 证书，然后执行：

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' scripts/build-cn.sh
```

所有组件必须使用同一身份签名。该命令不会导入、上传或生成 Apple 证书。正式分发还需要使用你自己的 Apple 开发者账号公证：

```sh
# 预先用 xcrun notarytool store-credentials 保存本机公证凭据
xcrun notarytool submit build-cn/Sapphire-CN.zip --keychain-profile SapphireCN --wait
xcrun stapler staple build-cn/DerivedData/Build/Products/Release/Sapphire.app
xcrun stapler validate build-cn/DerivedData/Build/Products/Release/Sapphire.app
# staple 修改了应用，需重新打包并更新校验和
/usr/bin/ditto -c -k --sequesterRsrc --keepParent build-cn/DerivedData/Build/Products/Release/Sapphire.app build-cn/Sapphire-CN.zip
(cd build-cn && shasum -a 256 Sapphire-CN.zip > Sapphire-CN.zip.sha256)
```

正式公证未完成前，不应将产物标为「已公证」。证书、密码、私钥和 provisioning profile 不应提交到仓库。

## 公开源码的功能范围

上游公开仓库对部分智能功能、体育／金融、设备互联、存储等提供的是占位实现，摄像头／音频等扩展也存在公开占位目标。本分支开放有完整实现的本地功能，并补齐部分界面与本地处理功能；具体状态和测试范围见 [社区版功能实现进度](FEATURES.zh-CN.md)。不包含未公开的商业模块，也不伪造原作者订阅或账号。尚未实现的功能仍保持不可用，不能只通过修改 VIP 标记获得。

公共构建不初始化占位 Firebase 项目，也不向原作者上传 Crashlytics 符号。更新检查指向本仓库 Releases；在本仓库发布新版本前不会有可用更新。自动替换应用要求有效签名和相同 Apple 开发者团队，临时签名版本请手动更新。

## 维护

译文位于 `Sapphire/zh-Hans.lproj/Localizable.strings`，权限说明位于同目录的 `InfoPlist.strings`。英文资源在 `en.lproj`。增加或修改译文后运行 `python3 scripts/check-localization.py`，检查语法、重复键、格式参数和中英文键一致性。

完整的功能说明和原项目信息见 [上游 README](README.md)。


### 网易云音乐（macOS）

在「音乐 > 通用」中将媒体来源和默认音乐应用设为「网易云音乐」。先安装并打开 macOS 网易云音乐客户端（`com.netease.163music`），从客户端播放歌曲。

- 歌名、歌手、专辑、封面、播放状态、时长与进度：跟随 macOS Now Playing，沿用原有实时进度和封面处理。
- 播放/暂停、上一首/下一首：网易云是当前系统媒体客户端时使用 macOS 媒体通道，不要求辅助功能权限；其它客户端处于活动状态时只尝试网易云自身菜单，避免控制其它播放器。界面跟随客户端返回的实际播放状态。
- 喜欢歌曲、随机和循环：通过网易云自身原生菜单控制，需要在「系统设置 > 隐私与安全性 > 辅助功能」允许当前运行的 Sapphire。红心调用「喜欢歌曲／取消喜欢」，状态读取后才改变图标；设置提供只读连接检查及权限入口。
- 调整进度：仅在网易云是当前系统媒体客户端时发送系统跳转请求，等待客户端返回实际位置；客户端不支持或不响应时不会假装跳转成功。
- 同步歌词：优先读取网易云公开歌词与翻译。系统歌曲标识若不含网易云歌曲链接，则严格核对歌名、歌手、专辑和时长；匹配含糊或网络失败时使用原有歌词来源。不会读取网易云的 Cookie、账号或播放历史。
- 队列、歌单、搜索、推荐、账号与会员：在网易云客户端中管理，播放器列表按钮会打开网易云，不会要求登录 Spotify。**此版本没有把网易云账号资料库或队列内嵌到 Sapphire；不宣称与 Spotify/Apple Music 的专有 API 功能完全等同。**

已在网易云音乐 3.1.12 验证公开搜索对《Day & Night》/蔡健雅/I Do Believe 的准确版本匹配，以及本机系统媒体信息和原生播放/暂停菜单。其它客户端版本的菜单、收藏操作、循环模式和系统进度跳转仍需实机验收；接口变化时会明确报错。公开歌词服务并非稳定的第三方开发者契约，可能受地区、版权及网络影响。

签名仍为本地 ad-hoc 签名，未使用 Apple Developer ID 公证；安装方式见上文。

网易云模式默认显示收藏与列表（主控制栏两侧）、随机与循环（下方操作栏）。升级时不受旧版默认关闭收藏/播放模式开关或空按钮排序的影响；可在网易云设置卡片中关闭「显示网易云播放操作按钮」。列表按钮打开网易云客户端中的队列与歌单入口，尚未内嵌完整列表。
