# 安装指南（Windows 全程操作）

本应用代码由 GitHub 的免费云 Mac 服务器自动编译，**你不需要苹果电脑**，只需要：

- Windows 电脑
- iPhone（iOS 26.6）
- 一根数据线
- 一个免费 Apple ID

全程 4 大步，约 20 分钟。

---

## 第一步：把代码放上 GitHub（约 5 分钟，全自动）

先注册一个**免费 GitHub 账号**：打开 https://github.com → 注册（已有就直接登录，登录状态留在浏览器里即可）。

然后运行项目里的一键上传脚本：

1. 打开文件夹 `D:\CODEX\20260812-voice-todo`
2. 双击文件 `upload_to_github.ps1`（若提示选择打开方式，选 PowerShell；若被系统阻止，右键 → 使用 PowerShell 运行）
3. 脚本会自动：
   - 检测/安装 GitHub 官方命令行工具（会先问你是否安装，选 Y）
   - 弹出浏览器让你登录 GitHub（按提示点授权即可）
   - 自动创建**私有仓库**并上传全部代码
   - 自动打开编译任务页面
4. 如果双击没反应，就打开 PowerShell 手动运行：
   ```
   powershell -ExecutionPolicy Bypass -File D:\CODEX\20260812-voice-todo\upload_to_github.ps1
   ```

> 不需要任何 git 知识，脚本会带你走完每一步。

---

## 第二步：自动编译（约 5 分钟，全程免费）

代码上传后，GitHub 会自动在云 Mac 上编译，不需要你操作任何东西。

1. 打开你的仓库页面。
2. 点顶部 `Actions`（操作）标签。
3. 会看到名为 `Build iOS App` 的任务正在运行（黄色），等它变绿（成功）。
4. 点击这个任务，往下拉，在 `Artifacts`（产物）区域点 `VoiceTodo-ipa` 下载。得到 `VoiceTodo-ipa.zip`。

---

## 第三步：用 SideStore（LiveContainer + SideStore）装进 iPhone，一次搞定自动续签

用 **iloader + LiveContainer+SideStore** 方式安装。相比旧的 Sideloadly 每周重装，这套方案**只在手机后台自动续签，不需要每周插电脑**。

> 为什么不用 Sideloadly/AltStore：Sideloadly 每周要手动重装；iOS 26 上 AltStore 的 Windows 方案已失效（AltServer 不支持 iOS 17+）。SideStore 靠手机内置 VPN 在后台自动续签，是免费方案里唯一"装完就不用管"的。

### 准备（5 分钟）

1. **装 iTunes**（目的是获得苹果 USB 驱动，只装这一个就够，**不需要 iCloud**）：
   - 到 https://www.apple.com/itunes/ 下载 Windows 版并安装。
2. **下载 iloader**（负责一次性注入"配对文件"并装 SideStore）：
   - GitHub Releases：https://github.com/nab138/iloader/releases → 选 `iloader_windows.zip`。
3. **手机装 LocalDevVPN**（SideStore 自动续签依赖的本地 VPN）：
   - App Store 搜「LocalDevVPN」安装。
4. **手机打开开发者模式**：`设置 → 隐私与安全性 → 开发者模式` → 打开 → 手机会重启。
5. **手机连电脑**：数据线插上，手机解锁时选「信任这台电脑」，需已设锁屏密码。

### 装 LiveContainer + SideStore（10 分钟）

1. 电脑打开 iloader，登录你的 **Apple ID**（不区分大小写）。
2. 选中你的 iPhone，在 Installers 里选 **LiveContainer + SideStore**（或 SideStore Stable）。
3. 等待安装完成并 **Place Pairing File**（配对文件被注入到手机，之后才可离线续签）。

### 手机上首次配置（关键，顺序不能反）

1. 打开手机上的 **LiveContainer**，会自启内置 **SideStore**。
2. **先在内置 SideStore 里登录**：Settings → **Sign in with Apple ID**，填与 iloader 相同的账号密码。
   - 中途会弹 **6 位验证码**，务必要等到并填上——**登录前先连好 LocalDevVPN**，否则 2FA 可能不弹直接报"凭据/格式错误"。
   - 登录成功后 Settings 会显示你的账号。
3. 回 **LiveContainer → Settings → "Import Certificate From SideStore"**。现在能正常导入（之前报"证书未找到"是因为没先登录）。
4. 打开 **LocalDevVPN → Connect** → 允许添加 VPN 配置并输锁屏密码。
5. 回 LiveContainer → **Apps** 标签 → 点 **sidestore 图标 → Refresh**，直到显示剩余天数（如 `7 DAYS`）。

### 安装 VoiceTodo.ipa

把 `VoiceTodo-ipa.zip` 解出的 `VoiceTodo.ipa` 弄到手机：
- **推荐 iCloud 网页版**：https://www.icloud.com → iCloud 云盘 → 上传该 ipa → 手机「文件」App → iCloud 云盘 → 点该 ipa →「用 LiveContainer 打开」。
- 或隔空投送 / 微信「文件传输助手」/ 网盘中转到手机。
- **不推荐**直接往 iPhone"内部存储"拖文件（iOS 的 internal storage 对 Windows 通常只读、拖不进去）。

然后在 LiveContainer → **Apps → `+` → 选中该 ipa → 安装**，图标出现即可启动。

### 首次信任（如弹出）

手机：`设置 → 通用 → VPN 与设备管理` → 找到你的 Apple ID → **信任**。

### 续签：不用再管（自动）

免费签名仍按 7 天过期，但 SideStore 会在**后台自动续签**，到期前自动刷新，**无需插电脑**。只要手机偶尔联网即可。

---

## 第四步：首次使用

打开"语音待办"App：

1. 允许**麦克风**、**语音识别**、**通知**三项权限（都点允许）。
2. 待办页右下角点麦克风按钮 → 说一句话 → 停止。
3. 几秒后自动生成一条文字待办。
4. 切到"日历"页，能看到今天出现了这条待办。
5. 点待办右侧 `⋯` 进详情 → `添加提醒` → 设个时间 → 保存 → 到点手机弹通知。

---

## 常见问题

| 问题 | 解决 |
|---|---|
| Actions 显示红色失败 | 把失败日志截图发我，我来修。通常是环境问题，代码本身不影响 |
| SideStore 登录报"凭据/格式错误" | 先连好 LocalDevVPN，再登录；核对有没有弹 6 位验证码；有空格/大小写问题就重输 |
| 导入证书报"证书未找到" | 还没在内置 SideStore 里登录。顺序：先 Sign in 成功 → 再 Import Certificate From SideStore |
| 登录报"could not determine this device's UDID" | pairing 失效/已知 bug。用 iloader 重新放一次 pairing file，或换个没用过的新 Apple ID 登录 |
| 某个 App 显示 7 天倒计时 | 点它手动刷新；到期前会自动续签。全部 App 在 SideStore → Apps 里看剩余天数 |
| 想更新版本 | 改代码 → 上传 → Actions 自动编译 → 下载新 ipa → iCloud/隔空投送弄到手机 → LiveContainer 导入覆盖 |
| LocalDevVPN 要一直开吗 | 不用。只在刷新/安装时连一下即可，平时关掉省电 |

---

## 每次都这样吗？平时用不用管？

**不用。** 安装好后日常就是正常使用。唯一需要注意的是免费签名 7 天到期前，SideStore 会在后台自动续签，**不需要插电脑、不需要手动操作**。若某次没自动续上，打开 LiveContainer → SideStore → Apps 里点一下 `7 DAYS` 手动刷新即可（需先连 LocalDevVPN）。
