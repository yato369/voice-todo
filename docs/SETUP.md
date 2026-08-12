# 安装指南（Windows 全程操作）

本应用代码由 GitHub 的免费云 Mac 服务器自动编译，**你不需要苹果电脑**，只需要：

- Windows 电脑
- iPhone（iOS 26.6）
- 一根数据线
- 一个免费 Apple ID

全程 4 大步，约 20 分钟。

---

## 第一步：把代码放上 GitHub（约 5 分钟）

1. 打开 https://github.com ，注册一个**免费账号**（已有就直接登录）。
2. 登录后点右上角 `+` → `New repository`（新建仓库）。
3. Repository name 填：`voice-todo`
4. 选 **Private**（私有，别人看不到）。
5. **不要**勾选任何初始化选项（不要 README，不要 .gitignore，不要 License）。
6. 点 `Create repository` 创建。
7. 创建完成后，页面上会显示一串命令。记下你的仓库网址（形如 `https://github.com/你的用户名/voice-todo.git`）。

> 注：如果你不懂 git 命令，最后一步的"上传代码"这一步告诉我，我来帮你准备一键上传脚本。

---

## 第二步：自动编译（约 5 分钟，全程免费）

代码上传后，GitHub 会自动在云 Mac 上编译，不需要你操作任何东西。

1. 打开你的仓库页面。
2. 点顶部 `Actions`（操作）标签。
3. 会看到名为 `Build iOS App` 的任务正在运行（黄色），等它变绿（成功）。
4. 点击这个任务，往下拉，在 `Artifacts`（产物）区域点 `VoiceTodo-ipa` 下载。得到 `VoiceTodo-ipa.zip`。

---

## 第三步：安装到 iPhone（约 10 分钟）

### 方式 A：Sideloadly（简单，推荐先用这个装第一次）

1. Windows 上安装 Apple 驱动：
   - 如果是 Windows 10/11，先装 [iTunes](https://www.apple.com/itunes/download/win64)（自动装 Apple 驱动）。
2. 下载 [Sideloadly](https://sideloadly.io/) 并安装（免费软件）。
3. 解开下载的 `VoiceTodo-ipa.zip`，得到 `VoiceTodo.ipa`。
4. 打开 Sideloadly：
   - 选你的 iPhone 设备（USB 连接）。
   - 拖入 `VoiceTodo.ipa`。
   - 输入你的 **Apple ID 账号和密码**（只用于签名，安全）。
   - 点 `Start`（开始）。
5. 首次签名安装需要 1~2 分钟，完成后 App 出现在手机桌面，名为"语音待办"。
6. 手机上：`设置 → 通用 → VPN与设备管理` → 点你的开发者证书 → `信任`。

> 注意：免费 Apple ID 签名的 App **7 天过期**。7 天后 App 无法打开，需要用 Sideloadly 重新安装一次。

### 方式 B：AltStore（可选，装好后每周自动续签）

如果你不想每 7 天手动重装：

1. 下载 [AltStore](https://altstore.io/) 的 Windows 版 AltServer 并安装。
2. 数据线连 iPhone，运行 AltServer，用 Apple ID 把 AltStore 本身装进手机（首次仍需手动信任）。
3. 手机打开 AltStore → `My Apps` → 右上角 `+` → 选 `VoiceTodo.ipa`。
4. 之后只要电脑开着 AltServer、手机在同一 WiFi，AltStore 会自动每周续签，长期可用。

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
| 安装时提示"无法安装" | 重新信任证书：设置 → 通用 → VPN与设备管理 → 信任 |
| 7 天后打不开 | 重新用 Sideloadly 装一次，或改用 AltStore 方式 B |
| 转写出来的文字不准 | 环境安静点、语速正常。准确率不足时我们后续可换云 ASR |
| 想更新版本 | 改代码 → 上传 → Actions 自动编译 → 下载新 ipa → 重装 |

---

## 每次都这样吗？平时用不用管？

**不用。** 安装好后日常就是正常使用。唯一的"维护动作"是免费签名的 7 天续签：
- 用 AltStore：电脑开着就自动续，无需操心。
- 用 Sideloadly：每周手动重装一次（3 分钟）。
