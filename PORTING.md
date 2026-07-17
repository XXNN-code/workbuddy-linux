# WorkBuddy (macOS DMG to Linux) 移植技术说明与指南

本篇文档记录了将 WorkBuddy macOS (darwin-x64) 版本 DMG 安装包成功移植到 Linux 平台（以 Linux Mint 为核心测试环境）的原理、遇到的核心问题及完整解决方案。

---

## 一、 移植基本原理
WorkBuddy 核心是基于 **Electron** 开发的桌面端应用程序。其绝大部分业务逻辑是以 JavaScript / Node.js 编写并打包在 `app.asar` 归档中，这些平台无关的代码可以在 Linux 下直接运行。
核心的移植工作集中在以下两个方面：
1. **替换原生 C++ 模块（Native Addons）**：把 macOS 专用的 `.node` 动态链接库重新编译成 Linux 下的 ELF 规格。
2. **修补资源定位逻辑**：修正资源寻址代码，使其在解包/非标准打包环境下也能正常寻址核心配置文件。

---

## 二、 遇到的核心问题与解决方案

### 1. 原生模块 ABI 不匹配 (Mach-O vs ELF)
* **问题描述**：macOS 版本中携带的 `better-sqlite3` 和 `node-pty` 原生模块是用 macOS 的 Darwin 编译器编译的（Mach-O 格式）。在 Linux 运行会报错无法加载。
* **解决方案**：
  * 将 `app.asar` 完全解包出来。
  * 重新在 Linux 本地运行 `npm install better-sqlite3 node-pty @lydell/node-pty --omit=dev` 写入 Linux 原生源码。
  * 使用 `@electron/rebuild` 针对当前系统运行 of Electron 版本（例如 `v43.1.1`）执行重构编译：
    ```bash
    npx --package @electron/rebuild electron-rebuild -v 43.1.1
    ```
    重构后，系统会自动在 `node_modules` 对应目录下编译出适用于 Linux 平台的 `.node` 库文件。

### 2. asar 解包时平台特定文件缺失
* **问题描述**：应用打包时，macOS 端打包工具将特定平台（如 Windows、Linux 等）的 `ripgrep` 物理文件在 `app.asar.unpacked/` 中过滤去除了。当使用 `asar extract` 解密时，工具会因为找不到 `app.asar` 元数据中声明的 Linux 平台路径而报错退出 (`ENOENT`)。
* **解决方案**：
  * 编写提取脚本，在遇到 `ENOENT` 时捕获缺失路径，并在本地 `app.asar.unpacked/` 相应位置自动 touch 一个 0 字节的虚假文件，绕过 asar 解包限制。
  * **修复 Ripgrep 功能**：0 字节的文件无法执行，因此从 Linux 版本的 npm 包 `@vscode/ripgrep` 中提取出真实的 Linux x64 `rg` 二进制程序，覆盖替换到 `app/cli/vendor/ripgrep/x64-linux/rg`，并赋予可执行权限 `chmod +x`。

### 3. 配置寻址失效 (`Failed to locate cli/product.json`)
* **问题描述**：主进程启动时会调用 `resolveBundledAsset` 寻找 `cli/product.json` 配置文件。由于我们在 Linux 下使用了解包运行方式，`process.resourcesPath` 并非包内路径，且寻址候选方法中没有针对 `app/main` 的上级目录 `app/` 进行直接寻址的规则。
* **解决方案**：
  * 编辑 `app/main/bundled-assets.js`。
  * 在 `CANDIDATES_FNS` 数组中添加一个能够向上寻址一级目录的候选函数：
    ```javascript
    (root, segments) => (0, path.join)(root, "..", ...segments)
    ```
  * 修改后，资源寻址器能够从 `app/main/` 正确回退到 `app/` 根目录，成功加载 `cli/product.json`。

---

## 三、 手动操作标准步骤总结

1. **解压 DMG**：使用 `7z x WorkBuddy-darwin-x64-xxx.dmg` 解包出 `WorkBuddy.app`。
2. **解包 ASAR**：
   * 运行自动化循环解包脚本（自动 touch 缺失文件直至 `Success`）。
3. **更新并编译依赖**：
   * 进入 `WorkBuddy.app/Contents/Resources/app`。
   * 运行 `npm install better-sqlite3 node-pty @lydell/node-pty --omit=dev --legacy-peer-deps`（并授权 `approve-scripts`）。
   * 运行重构命令：`npx --package @electron/rebuild electron-rebuild -v 43.1.1`。
4. **修补 Ripgrep**：
   * 拷贝 Linux x64 `rg` 文件覆盖 `cli/vendor/ripgrep/x64-linux/rg`。
   * 赋予可执行权限。
5. **打补丁**：
   * 修改 `app/main/bundled-assets.js`，增加 `root/..` 寻址候选。
6. **创建快捷入口**：
   * 创建运行脚本 `workbuddy.sh`，直接通过全局/本地 `electron` 执行该目录。
   * 编写桌面快捷方式 `workbuddy.desktop` 注册进系统应用菜单。
