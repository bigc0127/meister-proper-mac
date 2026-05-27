# Meister Proper

A macOS utility for cleaning, analyzing, and optimizing your Mac. Finds leftover installer files, orphaned app data, stale LaunchAgents, and reclaims disk space.

**Requires macOS 14 (Sonoma) or later. Universal binary — runs on Apple Silicon and Intel.**

## Install

### Option 1: Download the DMG (recommended)

1. Go to the [latest release](../../releases/latest).
2. Download `Meister-Proper.dmg`.
3. Double-click the DMG. Drag **Meister Proper** to the **Applications** folder.
4. Eject the DMG.

### Option 2: Build from source

```bash
git clone https://github.com/bigc0127/meister-proper-mac.git
cd meister-proper-mac
./build-app.sh release
open "build/Meister Proper.app"
```

## First launch — what you will see

The app is **ad-hoc signed** (not Apple Developer ID signed or notarized). macOS Gatekeeper will warn you on first launch. This is expected.

### 1. Gatekeeper block

You will see one of these dialogs:

> *"Meister Proper" can't be opened because Apple cannot check it for malicious software.*

or on macOS 15 Sequoia and later:

> *"Meister Proper" is damaged and can't be opened. You should move it to the Trash.*

**Fix (GUI):** Open **System Settings → Privacy & Security**. Scroll to the bottom — you will see a message about Meister Proper being blocked. Click **Open Anyway**. Launch the app again, then click **Open** in the second confirmation dialog.

**Fix (Terminal one-shot):**

```bash
xattr -dr com.apple.quarantine "/Applications/Meister Proper.app"
```

After this, the app launches normally with no further Gatekeeper prompts.

### 2. Permission prompts on first use

The app will request these permissions as you use specific features. Each is requested only when needed:

| Prompt | Why | Recommended |
|---|---|---|
| Access **Desktop / Documents / Downloads** | Scan for leftover installer files | Allow |
| Control **Finder** | Empty Trash | OK |
| Control **System Events** | Manage LaunchAgents | OK |
| **Full Disk Access** (manual) | Clean system caches | Settings → Privacy & Security → Full Disk Access → add Meister Proper |
| **Admin password** | Remove protected items / system caches | Enter when prompted |

### 3. If the app refuses to open at all

Verify your macOS version:

```bash
sw_vers -productVersion
```

If below `14.0`, the app will not launch — `LSMinimumSystemVersion` is set to 14.0.

## Build from source — requirements

- macOS 14+
- Xcode 15+ or Swift 5.9 toolchain (`swift --version`)
- `iconutil`, `sips`, `codesign` (all included with macOS / Xcode Command Line Tools)

```bash
swift build -c release --arch arm64 --arch x86_64
./build-app.sh release
```

## License

[PolyForm Noncommercial 1.0.0](LICENSE) — do whatever you want with it, but no commercial use. Personal use, hobby projects, education, research, charities, and government use are all permitted. Selling it or using it as part of a commercial offering is not.
