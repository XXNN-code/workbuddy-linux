#!/bin/bash
set -e

# WorkBuddy macOS to Linux Repackager Script
# Usage: ./repackage.sh <path_to_dmg_file> [electron_version]

DMG_FILE="$1"
ELECTRON_VERSION="${2:-43.1.1}"

if [ -z "$DMG_FILE" ]; then
  echo "Error: Please specify the path to WorkBuddy-darwin-x64-xxx.dmg file."
  echo "Usage: $0 <path_to_dmg_file> [electron_version]"
  exit 1
fi

if [ ! -f "$DMG_FILE" ]; then
  echo "Error: File $DMG_FILE not found."
  exit 1
fi

echo "=== Step 1: Checking system tools ==="
for cmd in 7z npm node; do
  if ! command -v $cmd &> /dev/null; then
    echo "Error: Required command '$cmd' is not installed."
    echo "On Debian/Ubuntu/Mint run: sudo apt install p7zip-full nodejs npm"
    exit 1
  fi
done

echo "=== Step 2: Extracting DMG file ==="
7z x "$DMG_FILE" -aoa

APP_RESOURCES="WorkBuddy.app/Contents/Resources"
if [ ! -d "$APP_RESOURCES" ]; then
  echo "Error: Failed to find WorkBuddy.app resources directory."
  exit 1
fi

echo "=== Step 3: Extracting ASAR archive (with automatic missing files dummy patching) ==="
# We extract app.asar into WorkBuddy.app/Contents/Resources/app
# We handle cases where macOS bundle lacks files that metadata marks as unpacked (e.g. win32/linux files)
while true; do
  out=$(npx asar extract "$APP_RESOURCES/app.asar" "$APP_RESOURCES/app" 2>&1)
  if [ $? -eq 0 ]; then
    echo "ASAR extracted successfully!"
    break
  fi
  # Find missing file path from error
  missing_file=$(echo "$out" | grep -o "open '[^']*'" | cut -d"'" -f2)
  if [ -n "$missing_file" ]; then
    echo "  Creating dummy file for unpacked path: $missing_file"
    mkdir -p "$(dirname "$missing_file")"
    touch "$missing_file"
  else
    echo "Error: ASAR extraction failed with unexpected error:"
    echo "$out"
    exit 1
  fi
done

echo "=== Step 4: Re-installing native modules ==="
cd "$APP_RESOURCES/app"

# Approve script execution for native compilation in newer npm versions
npm approve-scripts better-sqlite3 node-pty || true

echo "Running npm install for native modules..."
npm install better-sqlite3 node-pty @lydell/node-pty --omit=dev --legacy-peer-deps

echo "Rebuilding modules for Electron $ELECTRON_VERSION..."
npx --package @electron/rebuild electron-rebuild -v "$ELECTRON_VERSION"

cd - > /dev/null

echo "=== Step 5: Fixing Ripgrep binary for Linux ==="
TEMP_RG_DIR="temp_ripgrep_build"
mkdir -p "$TEMP_RG_DIR"
echo "Fetching @vscode/ripgrep for Linux..."
npm --prefix "$TEMP_RG_DIR" install @vscode/ripgrep --legacy-peer-deps

RG_BIN=$(find "$TEMP_RG_DIR" -name "rg" -type f | head -n 1)
if [ -n "$RG_BIN" ] && [ -f "$RG_BIN" ]; then
  echo "Copying Linux rg binary to cli vendor..."
  TARGET_RG_PATH="$APP_RESOURCES/app/cli/vendor/ripgrep/x64-linux/rg"
  mkdir -p "$(dirname "$TARGET_RG_PATH")"
  cp "$RG_BIN" "$TARGET_RG_PATH"
  chmod +x "$TARGET_RG_PATH"
else
  echo "Warning: Could not find Linux rg binary in @vscode/ripgrep. Search features might not work."
fi
rm -rf "$TEMP_RG_DIR"

echo "=== Step 6: Patching bundled assets resolver ==="
ASSET_RESOLVER="$APP_RESOURCES/app/main/bundled-assets.js"
if [ -f "$ASSET_RESOLVER" ]; then
  # Inject (root, segments) => (0, path.join)(root, "..", ...segments) as candidate candidate path
  # This lets the app search for resources in the parent folder (app/) when running unpacked
  node -e '
    const fs = require("fs");
    const file = process.argv[1];
    let code = fs.readFileSync(file, "utf8");
    const target = "(root, segments) => (0, path.join)(root, ...segments),";
    const replacement = "(root, segments) => (0, path.join)(root, ...segments),\n\t(root, segments) => (0, path.join)(root, \"..\", ...segments),";
    if (code.includes(target) && !code.includes(replacement)) {
      code = code.replace(target, replacement);
      fs.writeFileSync(file, code, "utf8");
      console.log("Patched bundled-assets.js successfully!");
    } else if (code.includes(replacement)) {
      console.log("bundled-assets.js already patched.");
    } else {
      console.error("Error: Could not locate patch target in bundled-assets.js");
    }
  ' "$ASSET_RESOLVER"
else
  echo "Error: $ASSET_RESOLVER not found. Cannot patch."
  exit 1
fi

echo "=== Step 7: Generating launcher scripts ==="
LAUNCHER_SCRIPT="workbuddy.sh"
cat > "$LAUNCHER_SCRIPT" <<EOF
#!/bin/bash
DIR="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "\$DIR"
npx electron "$APP_RESOURCES/app" "\$@"
EOF
chmod +x "$LAUNCHER_SCRIPT"

DESKTOP_ENTRY="workbuddy.desktop"
CWD=$(pwd)
cat > "$DESKTOP_ENTRY" <<EOF
[Desktop Entry]
Name=WorkBuddy
Exec=$CWD/workbuddy.sh %U
Terminal=false
Type=Application
Icon=$CWD/$APP_RESOURCES/app/resources/icon.png
StartupWMClass=WorkBuddy
Comment=Tencent WorkBuddy
Comment[zh_CN]=腾讯版
Categories=Office;Development;
EOF

# Install to user local applications menu if directory exists
if [ -d "$HOME/.local/share/applications" ]; then
  cp "$DESKTOP_ENTRY" "$HOME/.local/share/applications/workbuddy.desktop"
  chmod +x "$HOME/.local/share/applications/workbuddy.desktop"
  echo "Registered WorkBuddy in system applications menu."
fi

echo "============================================="
echo "Porting completed successfully!"
echo "To run WorkBuddy: ./workbuddy.sh"
echo "============================================="
