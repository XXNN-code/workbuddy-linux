# WorkBuddy Linux Porting Tools

This repository contains tools and scripts to port **Tencent WorkBuddy (macOS DMG)** to **Linux** (tested on Linux Mint / Ubuntu / Arch).

Since WorkBuddy is closed-source proprietary software, this repository **does not contain any code or assets** from WorkBuddy. It only provides a script to extract and patch your legally acquired official macOS build so it can run natively on Linux.

---

## Prerequisites

Before running the script, make sure you have the following packages installed on your Linux system:

### For Debian / Ubuntu / Linux Mint:
```bash
sudo apt update
sudo apt install p7zip-full nodejs npm build-essential
```

### Electron Runtime
You also need Electron installed. If you don't have it globally, the script will run it via `npx electron`.

---

## How to Repackage and Run

1. **Download the Official macOS DMG**:
   Obtain the official `WorkBuddy-darwin-x64-xxx.dmg` from Tencent (e.g. from `https://www.codebuddy.ai/`).

2. **Clone this repository**:
   ```bash
   git clone https://github.com/XXNN-code/workbuddy-linux.git
   cd workbuddy-linux
   ```

3. **Run the repackage script**:
   Provide the path to the downloaded `.dmg` file as the first argument:
   ```bash
   ./repackage.sh /path/to/WorkBuddy-darwin-x64-5.2.6.33159827-8ee6bc11.dmg
   ```
   *The script will extract the DMG, resolve missing unpacking files, compile the native Node modules (`better-sqlite3`, `node-pty`), apply path patches for configuration files, and generate local wrappers.*

4. **Launch WorkBuddy**:
   - Via Terminal:
     ```bash
     ./workbuddy.sh
     ```
   - Via System Application Menu:
     Simply search for **WorkBuddy** in your desktop environment's start/applications menu and click to launch!

---

## Technical Details

For an in-depth explanation of how this port works, check out [PORTING.md](PORTING.md).
