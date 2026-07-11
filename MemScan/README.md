# MemScan

iMemScan 简化版 iOS 内存扫描器。

## 功能

- 选择进程
- 内存搜索 / 进一步搜索
- 修改数值
- 数据类型选择
- 搜索范围选择

## Windows 用户编译（GitHub Actions）

1. 把本文件夹 `MemScan` 里的**所有内容**上传到 GitHub 仓库
2. 确保包含 `.github/workflows/ios.yml`
3. 打开 **Actions** → **iOS Build** → **Run workflow**
4. 下载 **MemScan-unsigned.zip**
5. 解压后 `MemScan.app` 里应有 `MemScan`、`Info.plist`、`PkgInfo`

## 安装到越狱设备

```bash
ldid -SMemScan.entitlements MemScan.app/MemScan
```

然后用 Filza 或 TrollStore 安装。

## 项目位置

本地路径：`C:\Users\23658\Desktop\ios\MemScan`
