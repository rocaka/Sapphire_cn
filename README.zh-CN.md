# Sapphire 中文版

基于 [cshariq/Sapphire](https://github.com/cshariq/Sapphire) 的简体中文分支，保留上游版权、历史和 AGPL-3.0 许可证。上游基准：`792f9b4ea3d556d7566fbc38592fe54e88d89dc0`。

## 中文支持

提供简体中文与英文资源，覆盖首次启动、权限引导、设置、常用小组件与操作提示。中文系统自动使用简体中文；也可在 macOS「系统设置 → 通用 → 语言与地区 → 应用程序」中为 Sapphire 选择中文或 English，然后重启应用。文件名、歌曲名、便笺、终端输出等用户内容保持原文。上游新增文案、第三方返回的错误和开发调试界面可能仍显示英文。

设置侧边栏支持中英文搜索。设置助手仍受 Apple 智能、系统版本和地区可用性限制。

## 下载与构建

进入本仓库 [Actions](https://github.com/rocaka/Sapphire_cn/actions/workflows/build-cn.yml)，下载成功构建的 `Sapphire-CN-Release-universal` artifact，解压其中的 `Sapphire-CN.zip` 后将应用放入「应用程序」。只有绿色成功的构建才代表已通过编译与签名验证；日志 artifact 不代表有可安装程序。

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

上游公开仓库对订阅、部分智能功能、体育／金融、设备互联、存储等提供的是占位实现，摄像头／音频等扩展也存在公开占位目标。本分支修复公开源码的编译配置并进行汉化，不包含未公开的商业模块，也不提供付费功能解锁。修改语言或签名不会让占位功能变成完整实现。

公共构建不初始化占位 Firebase 项目，也不向原作者上传 Crashlytics 符号。更新检查指向本仓库 Releases；在本仓库发布新版本前不会有可用更新。自动替换应用要求有效签名和相同 Apple 开发者团队，临时签名版本请手动更新。

## 维护

译文位于 `Sapphire/zh-Hans.lproj/Localizable.strings`，权限说明位于同目录的 `InfoPlist.strings`。英文资源在 `en.lproj`。增加或修改译文后运行 `python3 scripts/check-localization.py`，检查语法、重复键、格式参数和中英文键一致性。

完整的功能说明和原项目信息见 [上游 README](README.md)。


### 网易云音乐（macOS）

在「音乐 > 通用」中将媒体来源和默认音乐应用设为「网易云音乐」。先安装并打开 macOS 网易云音乐客户端（`com.netease.163music`），从客户端播放歌曲。

- 歌名、歌手、专辑、封面、播放状态、时长与进度：跟随 macOS Now Playing，沿用原有实时进度和封面处理。
- 播放/暂停、上一首/下一首、喜欢歌曲、随机和循环：通过网易云自身原生菜单定向控制，需要在「系统设置 > 隐私与安全性 > 辅助功能」允许 Sapphire。设置中提供权限入口；失败会显示提示，不会把全局媒体键发送给别的播放器。
- 调整进度：仅在网易云是当前系统媒体客户端时发送系统跳转请求，等待客户端返回实际位置；客户端不支持或不响应时不会假装跳转成功。
- 同步歌词：优先读取网易云公开歌词与翻译。系统歌曲标识若不含网易云歌曲链接，则严格核对歌名、歌手、专辑和时长；匹配含糊或网络失败时使用原有歌词来源。不会读取网易云的 Cookie、账号或播放历史。
- 队列、歌单、搜索、推荐、账号与会员：在网易云客户端中管理，播放器列表按钮会打开网易云，不会要求登录 Spotify。**此版本没有把网易云账号资料库或队列内嵌到 Sapphire；不宣称与 Spotify/Apple Music 的专有 API 功能完全等同。**

已在网易云音乐 3.1.12 验证公开搜索对《Day & Night》/蔡健雅/I Do Believe 的准确版本匹配，以及本机系统媒体信息和原生播放/暂停菜单。其它客户端版本的菜单、收藏操作、循环模式和系统进度跳转仍需实机验收；接口变化时会明确报错。公开歌词服务并非稳定的第三方开发者契约，可能受地区、版权及网络影响。

签名仍为本地 ad-hoc 签名，未使用 Apple Developer ID 公证；安装方式见上文。
