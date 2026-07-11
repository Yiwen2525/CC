# MemScan

iMemScan 的简化版 iOS 内存扫描器，支持进程选择、内存搜索、进一步搜索、数值修改、数据类型与搜索范围配置。

## 功能

| 功能 | 说明 |
|------|------|
| 选择进程 | 列出系统运行中的进程，选择目标应用 |
| 搜索 | 按精确数值在目标进程内存中首次扫描 |
| 进一步搜索 | 在已有结果上精搜：精确值 / 增大 / 减小 / 不变 / 改变 |
| 修改 | 点击结果地址，写入新数值 |
| 数据类型 | Int8/16/32/64、UInt8/16/32/64、Float、Double |
| 搜索范围 | 全部、堆、栈、匿名映射、共享内存、可执行段 |

## 环境要求

> **重要**：本应用需要访问其他进程内存，必须在具备 `task_for_pid` 权限的环境下运行。

- 已越狱的 iOS 设备（推荐 iOS 13–17）
- 或通过 TrollStore 等方式安装并注入相应 entitlement
- 使用 Xcode 15+ 在 Mac 上编译
- 非越狱设备上 UI 可运行，但无法实际读写其他进程内存

## 使用流程

1. 打开 MemScan，在进程列表中选择目标应用
2. 选择**数据类型**和**搜索范围**
3. 输入当前游戏中的数值，点击**搜索**
4. 回到目标应用改变该数值（如金币 +1）
5. 返回 MemScan，选择精搜模式（通常选「精确值」并输入新数值，或选「数值增大」）
6. 重复步骤 4–5，直到结果只剩少量地址
7. 点击地址，输入目标值并**写入**

## 项目结构

```
MemScan/
├── MemScan.xcodeproj
└── MemScan/
    ├── Bridge/          # Mach 内核内存读写 (ObjC++)
    ├── Models/          # 数据类型、搜索范围等模型
    ├── Services/        # 进程枚举与扫描会话
    ├── Views/           # SwiftUI 界面
    └── MemScanApp.swift
```

## 编译与安装

### 方式一：Windows 用户 — GitHub Actions 云端编译（推荐，免费）

iOS 应用无法在 Windows 本地直接编译（Xcode 仅支持 macOS），但可以用 GitHub 提供的免费 macOS 虚拟机远程编译：

1. 注册 [GitHub](https://github.com) 账号
2. 新建一个仓库，将 `MemScan` 文件夹上传（或在项目目录执行下方命令）
3. 打开仓库 → **Actions** → 选择 **iOS Build**（不是默认的 "iOS starter workflow"）→ **Run workflow**
4. 等待约 3–5 分钟，编译完成后在 **Artifacts** 下载 `MemScan-unsigned.zip`
5. 解压得到 `MemScan.app`，按下方「安装到设备」步骤操作

```bash
# 在 Windows PowerShell 中（需先安装 Git）
cd C:\Users\23658\Desktop\ios\MemScan
git init
git add .
git commit -m "Initial MemScan project"
git remote add origin https://github.com/你的用户名/MemScan.git
git push -u origin main
```

> GitHub 免费账户每月有约 2000 分钟 macOS 编译时长，对本项目足够使用。

### 方式二：租用云端 Mac

| 服务 | 说明 | 价格 |
|------|------|------|
| [MacinCloud](https://www.macincloud.com) | 按小时租用远程 Mac 桌面 | ~$1/小时起 |
| [AWS EC2 Mac](https://aws.amazon.com/ec2/instance-types/mac/) | 亚马逊云端 Mac 实例 | ~$1/小时起 |
| [Codemagic](https://codemagic.io) | 移动端 CI，有免费额度 | 免费层可用 |

### 方式三：有 Mac 的朋友帮忙

将项目文件夹发给有 Mac 的朋友，用 Xcode 打开 `MemScan.xcodeproj`，连接 iPhone 编译安装即可。

### 方式四：本地 Mac 编译

1. 用 Xcode 打开 `MemScan.xcodeproj`
2. 在 Signing & Capabilities 中配置你的 Team（越狱设备可用 ad-hoc 签名）
3. 确认 `MemScan.entitlements` 已关联到 Target
4. 连接 iOS 设备，选择真机 Target，Build & Run

### 安装到越狱设备

从 GitHub Actions 下载的未签名 `.app` 需要注入权限后安装：

```bash
# 在越狱设备的 SSH 终端，或用电脑上的 ldid 工具
ldid -SMemScan.entitlements MemScan.app/MemScan

# 然后复制到设备并安装，例如：
# - 用 Filza 将 MemScan.app 放到 /Applications
# - 或用 TrollStore 安装
# - 或用 ideviceinstaller 从电脑推送
```

### 不可行的方式（请勿尝试）

- **黑苹果 / macOS 虚拟机**：Apple 许可协议禁止在非 Mac 硬件上运行 macOS，且配置复杂、稳定性差
- **Windows 版 Xcode**：不存在
- **直接用 Visual Studio 编译 SwiftUI iOS 项目**：不支持

## 技术说明

- 进程列表：`sysctl(KERN_PROC_ALL)`
- 附加进程：`task_for_pid`
- 内存枚举：`mach_vm_region_recurse`
- 内存读取：`mach_vm_read_overwrite`
- 内存写入：`mach_vm_write`

## 免责声明

本工具仅供学习与研究 iOS 内存机制使用。修改第三方应用内存可能违反服务条款、导致应用崩溃或账号封禁，请自行承担风险。
