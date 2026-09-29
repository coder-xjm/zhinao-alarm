# 智闹 · 双条件智能闹钟（小米手机版）

一个按「**日期规则 + 目标时间**」双条件同时满足才响铃的安卓闹钟。
包名 `com.zhinao.alarm`，目标机型：小米 / 红米 / HyperOS。

---

## 这个 App 和系统闹钟有什么不同

系统闹钟只有一个重复维度（周一~周日）。智闹把「哪天响」拆成 6 种规则，
与「几点响」做 AND 判定：

| 条件一（哪天响） | 条件二（几点响） | 结果 |
|---|---|---|
| 工作日 | 07:00 | 每个工作日 7 点响，周末不响 |
| 每隔 2 天的 08:00 | 08:00 | 从起始日起，隔一天响一次 |
| 每隔 2 周的 周三 | 09:30 | 只在隔周周三响 |
| 每月 1 号 | 10:00 | 每月 1 号提醒交房租 |
| 节假日 | 09:00 | 只在周末响 |
| 每日 | 21:45 | 每天响（= 每隔 1 天） |

---

## 打包 APK：推荐走云端（本地零安装）

本项目已内置 GitHub Actions 流水线 `.github/workflows/build-apk.yml`。
把它推到 GitHub 后，**云端会自动编译出 APK**，本地完全不用装 Flutter / JDK / Android SDK。

完整图文步骤见工作区根目录的 **`打包APK-云构建指南.md`**。

一句话流程：

```
上传代码到 GitHub  →  Actions 自动跑 5~10 分钟  →  在运行页面底部下载 APK
```

> ⚠️ 流水线里 Flutter 版本**锁定在 3.24.5**，不要改成 `stable`。
> 设计上有两条保险：
> 1. 脚手架自带、且与 Flutter 版本自洽的 `android/settings.gradle` / `build.gradle` / `gradle.properties` **不做覆盖**，
>    只覆盖 `android/app/build.gradle`（为了 `minSdk = 24` 和 `androidx.core` 依赖）——
>    避免手写脚本里的 AGP/Kotlin 版本号和云端 Gradle 包装器对不上。
> 2. 复制 `lib/` 后会自动把 `withValues(alpha:` 替换为 `withOpacity(`，
>    兼容仓库里旧写法的代码；本地代码已改为通用写法，该替换是空操作。

---

## 项目结构

```
zhinao_alarm/
├── pubspec.yaml                    依赖清单
├── analysis_options.yaml           代码规范
├── README.md                       本文件
├── .github/
│   └── workflows/
│       └── build-apk.yml           ★ 云端打包流水线（推上去就自动出 APK）
│
├── lib/                            ===== Flutter 界面层 =====
│   ├── main.dart                   入口 + 主题
│   ├── models/
│   │   └── alarm.dart              闹钟数据模型（条件一 + 条件二字段）
│   ├── core/
│   │   ├── date_rule_engine.dart   ★ 双条件 AND 判定引擎（界面预览用）
│   │   ├── alarm_repository.dart   SQLite 持久化
│   │   └── alarm_store.dart        全局状态与增删改
│   ├── platform/
│   │   └── alarm_platform.dart     Flutter ↔ 原生 通道封装
│   ├── pages/
│   │   ├── home_page.dart          页面 1 闹钟列表
│   │   ├── edit_alarm_page.dart    页面 2 编辑闹钟
│   │   └── settings_page.dart      页面 5 可靠性检查
│   └── widgets/
│       ├── alarm_tile.dart         首页单个闹钟卡片
│       └── rule_picker_sheet.dart  条件一规则选择弹层
│
└── android/                        ===== Android 原生层（闹钟能不能响的关键）=====
    ├── build.gradle
    ├── settings.gradle
    ├── gradle.properties
    └── app/
        ├── build.gradle
        └── src/main/
            ├── AndroidManifest.xml         权限与组件声明
            ├── res/values/styles.xml       主题（含全屏响铃页深色主题）
            └── kotlin/com/zhinao/alarm/
                ├── MainActivity.kt         Flutter 通道入口 + 权限跳转
                ├── AlarmModel.kt           数据模型（对应 Dart 侧）
                ├── RuleEngine.kt           ★ 双条件 AND 判定引擎（实际排程用）
                ├── AlarmStore.kt           原生侧本地存储
                ├── AlarmScheduler.kt       ★ setAlarmClock 排程
                ├── AlarmReceiver.kt        到点广播
                ├── BootReceiver.kt         开机重排
                ├── RingService.kt          响铃前台服务
                └── RingActivity.kt         全屏响铃页
```

### 为什么规则引擎写了两份（重点）

`RuleEngine.kt` 和 `date_rule_engine.dart` 的逻辑必须完全一致：

- **Dart 那份**：算界面上的「下次响铃：明天 07:00」
- **Kotlin 那份**：算实际排程。因为响铃结束后、开机之后，Flutter 进程很可能没启动，
  原生必须自己算出下一次，闹钟才不会被"弄丢"

改判定规则时，**两个文件要一起改**。

---

## 一、准备开发环境

### 1. 安装 Flutter SDK

1. 打开 https://flutter.dev/docs/get-started/install/windows
2. 下载 `flutter_windows_x.x.x-stable.zip`
3. 解压到不含中文和空格的路径，例如 `C:\src\flutter`
4. 把 `C:\src\flutter\bin` 加入系统环境变量 `Path`
5. 打开新的命令行窗口验证：

```bash
flutter --version
```

> 本项目要求 **Flutter 3.24 或更高版本**（`surfaceContainerHighest` 等 Material 3 色彩角色需要 3.22+，
> 配套的 `flutter_lints 4.x` / `intl 0.19.x` 与 3.24 ~ 3.27 一带对齐）。
> 云端流水线锁定 **3.24.5**；本地开发建议 3.24.x ~ 3.27.x。

### 2. 安装 Android 开发环境

推荐直接安装 **Android Studio**（自带 SDK 管理器）：

1. 下载安装 Android Studio：https://developer.android.com/studio
2. 首次启动时按引导安装 SDK，注意勾选：
   - **Android SDK Platform 34**（或更高）
   - **Android SDK Build-Tools**
   - **Android SDK Command-line Tools (latest)** ← **必须勾选**，否则会报 `cmdline-tools not found`
   - **Android SDK Platform-Tools**
3. 安装 JDK 17（Android Studio 自带的 JBR 即可）

### 3. 检查环境

```bash
flutter doctor
```

必须确保 `Android toolchain` 前面是绿色的 ✓：

```
[✓] Flutter (Channel stable, 3.x.x)
[✓] Android toolchain - develop for Android devices (Android SDK version 34.x)
[✓] Android Studio (version 2023.x)
```

如果 `Android toolchain` 报缺少 licenses，执行：

```bash
flutter doctor --android-licenses
```

一路输入 `y` 同意。

---

## 二、把源码变成一个能运行的项目

本项目提供的是**完整源码**，Android 的 Gradle 包装器（`gradlew`、`gradle-wrapper.jar`）
属于二进制文件，需要由 Flutter 自动生成。所以按下面的顺序操作最稳妥：

### 步骤 1：生成标准空项目

在你想放项目的目录下执行：

```bash
flutter create --org com.zhinao --project-name alarm --platforms android zhinao_alarm
```

> **为什么 `--project-name` 写 `alarm` 而不是 `zhinao_alarm`？**
> Flutter 生成的安卓包名 = `--org` + `.` + `--project-name`。
> 写成 `alarm` 才能得到本项目使用的包名 **`com.zhinao.alarm`**，
> 并且原生代码会刚好落在 `android/app/src/main/kotlin/com/zhinao/alarm/` 目录下，
> 直接覆盖即可，不用改任何包名。Dart 侧的包名由后面覆盖的 `pubspec.yaml` 决定，不受影响。

### 步骤 2：用本项目的文件覆盖进去

把**本项目**的下列文件/目录复制到刚生成的 `zhinao_alarm` 里，全部选择"覆盖"：

| 本项目路径 | 说明 |
|---|---|
| `lib/` （整个目录） | Flutter 界面层，覆盖掉示例代码 |
| `pubspec.yaml` | 依赖清单，覆盖 |
| `analysis_options.yaml` | 代码规范，覆盖 |
| `android/app/src/main/AndroidManifest.xml` | **权限与组件声明，必须覆盖** |
| `android/app/src/main/res/values/styles.xml` | 主题（含全屏响铃页），必须覆盖 |
| `android/app/src/main/kotlin/com/zhinao/alarm/` （整个目录） | **原生闹钟核心代码，新增** |
| `android/app/build.gradle` | 需要 `minSdk = 24` 与 `androidx.core` 依赖 |

> 如果不想整个覆盖 `android/app/build.gradle`，也可以只手动改这两处：
> ```gradle
> defaultConfig {
>     minSdk = 24          // 原来是 flutter.minSdkVersion，改成 24
> }
> dependencies {
>     implementation "androidx.core:core-ktx:1.13.1"    // 新增这一行
> }
> ```

### 步骤 3：删除示例代码残留

如果 `lib/` 下还有 `flutter create` 生成的旧文件（如 `lib/widgets/counter.dart`），
一并删掉，只保留本项目 `lib/` 里的内容。

### 步骤 4：拉取依赖

```bash
cd zhinao_alarm
flutter pub get
```

---

## 三、连手机调试

1. 小米手机打开**开发者选项**：设置 → 我的设备 → 全部参数 → 连点「MIUI 版本」7 次
2. 打开 **USB 调试**：设置 → 更多设置 → 开发者选项 → USB 调试
3. 数据线连接电脑，手机上弹出「允许 USB 调试吗？」→ 允许
4. 验证设备已连接：

```bash
flutter devices
```

5. 跑起来：

```bash
flutter run
```

首次运行会编译几分钟，之后手机桌面上就会出现「智闹」。

---

## 四、打包 APK

### 方式 A：快速打包（先用调试签名，能装能测）

```bash
flutter build apk --release
```

产物路径：

```
build/app/outputs/flutter-apk/app-release.apk
```

这个 APK 用的是调试签名，**可以直接装到自己手机上用**，也能分享给朋友安装。
但不能上架应用商店。

### 方式 B：正式签名打包（长期使用推荐）

**1. 生成签名文件**（只做一次，务必保管好，弄丢了就无法覆盖升级）

```bash
keytool -genkey -v -keystore zhinao-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias zhinao
```

按提示设置密码和姓名等信息。生成的 `zhinao-release.jks` 放到 `android/` 目录下。

**2. 新建 `android/key.properties`**

```properties
storePassword=你设置的密码
keyPassword=你设置的密码
keyAlias=zhinao
storeFile=../zhinao-release.jks
```

**3. 修改 `android/app/build.gradle`**

在 `android {` 之前加入：

```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
```

把 `buildTypes` 整段改成：

```gradle
buildTypes {
    release {
        signingConfig signingConfigs.release
        minifyEnabled false
        shrinkResources false
    }
}

signingConfigs {
    release {
        keyAlias keystoreProperties['keyAlias']
        keyPassword keystoreProperties['keyPassword']
        storeFile file(keystoreProperties['storeFile'])
        storePassword keystoreProperties['storePassword']
    }
}
```

**4. 打包**

```bash
flutter build apk --release
```

如果需要体积更小，可以按 CPU 架构分包：

```bash
flutter build apk --split-per-abi
```

会生成 `app-armeabi-v7a-release.apk`、`app-arm64-v8a-release.apk` 等，
小米手机一般装 `arm64-v8a` 那个。

---

## 五、装到小米手机后，必须做的 4 项设置

**这四项不做，闹钟大概率不响。** 打开 App 首页如果顶部有红色告警条，点「去设置」逐项处理。

| # | 设置项 | 路径 | 为什么必须 |
|---|---|---|---|
| 1 | **允许自启动** | 设置 → 应用设置 → 应用管理 → 智闹 → 自启动 | 不开的话，手机重启后闹钟不会重新排程，直接失效 |
| 2 | **省电策略 → 无限制** | 同上页面 → 省电策略 → 选「无限制」 | 默认「智能省电」会冻结后台，闹钟响不了 |
| 3 | **精确闹钟权限** | App 内「设置 → 精确闹钟权限」一键跳转 | Android 12+ 必须手动授予，否则只能"大概准时" |
| 4 | **通知权限 + 锁屏显示** | 设置 → 应用设置 → 智闹 → 通知管理 | 响铃页需要盖在锁屏上弹出 |

### 验证闹钟真的会响

最靠谱的验证方式：设一个 **2 分钟后**的闹钟，然后把手机**息屏**、放在一边等它响。
如果这样能响，说明保活设置都对了。

---

## 六、常见报错排查

| 报错信息 | 原因 | 解决办法 |
|---|---|---|
| `cmdline-tools component is missing` | 没装 Android SDK 命令行工具 | Android Studio → SDK Manager → SDK Tools → 勾选 **Android SDK Command-line Tools** |
| `CocoaPods not installed` | 只影响 iOS，本项目不做 iOS | 忽略即可 |
| `Gradle build failed to produce an .apk file` | 构建缓存脏了 | `flutter clean` 后重新 `flutter pub get` → `flutter build apk` |
| `AAPT: error: resource android:attr/... not found` | Flutter / AGP 版本过低 | 升级到 Flutter 3.24+，与 `android/settings.gradle` 里的 AGP 版本配套 |
| `Unsupported class file major version` | JDK 版本不对 | 装 JDK 17，并在 Android Studio 里把 Gradle JDK 设为 17 |
| `Could not find method compileSdkVersion()` | AGP 与 Gradle 版本不匹配 | 直接用 `flutter create` 生成的 `build.gradle`，只改 `minSdk` 和 `dependencies` |
| `Execution failed for task ':app:processReleaseManifest'` | Manifest 里的属性不被当前 SDK 识别 | 确认 `compileSdk` ≥ 34，且已覆盖本项目的 `AndroidManifest.xml` |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | 手机上已装同名但签名不同的 App | 先卸载手机上的旧版本再安装 |
| 编译通过但**闹钟不响** | 系统权限没给全 | 回到「第五章」逐项检查自启动、省电策略、精确闹钟 |
| 闹钟延迟几分钟才响 | 用的降级通道（无精确闹钟权限） | 去设置页开启「精确闹钟权限」 |

---

## 七、代码里几个关键设计说明

### 1. 为什么用 `setAlarmClock()` 而不是 `setRepeating()`

`setRepeating()` 只能表达"固定周期"，而「每隔 2 周的周三」「每月 1 号」
无法用固定周期表达。所以改成：每次只排**下一次**，响铃触发时立刻算并排下一次。

`setAlarmClock()` 是安卓最高优先级的闹钟通道（系统自带闹钟用的就是它），
小米对它做了白名单豁免，最不容易被省电策略拦截。

### 2. 「每隔 N 周」的锚点

以**创建闹钟当周**为第 1 周。所以在编辑页选完间隔后，会显示一行提示
「以创建当周（9月28日 周一）为第 1 周计算」，避免用户产生歧义。

### 3. 「每月 31 号」遇到 2 月怎么办

默认**跳过本月**，用户也可以改成**顺延到当月最后一天**。
这个选项只在选择了 29/30/31 号时才出现。

### 4. 贪睡为什么不参与条件一判定

用户按了贪睡就是"再给我 5 分钟"，跟今天是不是"该响的日子"无关。
所以贪睡单独排一个一次性闹钟。

### 5. 自愈设计

`AlarmReceiver` 收到到点广播后，**第一件事是排下一次**，第二件事才是启动响铃服务。
这样即使响铃环节出问题，下一个周期的闹钟也已经安排好了。

### 6. 响铃时会不会动我的系统音量

每个闹钟的编辑页都有开关「**响铃时音量拉到最大**」，**默认开启**。

开启时的行为是**临时的**，用完就还：

```
响铃开始 → 记下你当前的闹钟音量 → 调到最大 → 开始响
响铃结束 → 恢复到响铃前的音量
```

响铃结束包括所有路径：点「关闭」、点「贪睡」、到时长自动停、服务被系统销毁。
还原动作统一放在 `RingService.stopRinging()` 里，它是所有停止路径的必经之处。

**三种情况下 App 完全不写系统设置：**

| 情况 | 行为 |
|---|---|
| 用户把开关关掉 | 一个字节都不碰系统音量，完全按你当前的闹钟音量响 |
| 音量本来就是最大 | 没什么可改，也就不需要还原 |
| 响铃期间你手动拖过音量条 | 检测到音量已不是我们拉的那档，**尊重你的操作，不覆盖** |

> 早期版本（v1.0.0）的做法是「响铃时无条件拉满，且**永不还原**」，
> 结果是一次响铃就会把你的系统闹钟音量永久留在最大值。
> 这个开关就是为了修掉这个问题而加的。

---

## 八、下一步（V2 计划）

- [ ] 中国法定节假日 + 调休补班日历（把「工作日/节假日」从自然日升级为法定口径）
- [ ] 自选铃声（从本地音乐里挑）
- [ ] 一个闹钟挂多个时间点
- [ ] 闹铃音量渐强
- [ ] 桌面小组件显示下次响铃时间
- [ ] 条件一多规则叠加（如「工作日 **加上** 每月 1 号」）
