import Foundation

/// One cleanable target. `paths` are absolute paths (with ~ already expanded).
/// `command` is an optional shell command to run instead of (or after) deleting paths.
/// `requiresAdmin` items get batched into a single sudo prompt.
struct CleanTarget: Identifiable, Hashable {
    let id = UUID()
    let category: CleanCategory
    let label: String
    let detail: String
    let paths: [String]
    let command: String?       // optional shell command (e.g. brew cleanup)
    let requiresAdmin: Bool
    let dangerous: Bool        // shows warning glyph + extra confirmation
    var size: Int64? = nil
    var selected: Bool = false
}

enum CleanCategory: String, CaseIterable, Identifiable, Hashable {
    case userEssentials   = "User essentials"
    case appCaches        = "App caches"
    case browsers         = "Browsers"
    case devTools         = "Developer tools"
    case devLanguages     = "Language toolchains"
    case xcode            = "Xcode & Simulator"
    case mobileDev        = "Mobile development"
    case gui              = "GUI applications"
    case media            = "Media & gaming"
    case system           = "System (admin)"
    case homebrew         = "Homebrew"
    var id: String { rawValue }
}

enum CleanCatalog {
    static func allTargets() -> [CleanTarget] {
        let h = NSHomeDirectory()
        var t: [CleanTarget] = []

        // ---------- User essentials ----------
        // ~/.Trash is TCC-protected. Try Finder via AppleScript (needs Automation permission);
        // if anything remains, fall back to admin rm (root bypasses TCC).
        t.append(CleanTarget(category: .userEssentials,
            label: "Empty Trash",
            detail: "Tries Finder first (no password). If items remain, falls back to admin rm.",
            paths: [],
            command: """
            BEFORE=$(/usr/bin/osascript -e 'tell application "Finder" to count items of trash' 2>/dev/null || echo "?")
            /usr/bin/osascript -e 'tell application "Finder" to delete every item of trash' 2>/dev/null || true
            sleep 1
            AFTER=$(/usr/bin/osascript -e 'tell application "Finder" to count items of trash' 2>/dev/null || echo "?")
            echo "Trash: $BEFORE → $AFTER items"
            if [ "$AFTER" != "0" ] && [ "$AFTER" != "?" ]; then
              echo "Finder left $AFTER item(s). Re-run with admin to force-remove."
            fi
            """,
            requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .userEssentials,
            label: "Force-empty Trash (admin)",
            detail: "Root rm — bypasses Finder + TCC. Use when Empty Trash leaves items behind.",
            paths: [],
            command: "/bin/rm -rf '\(h)/.Trash/'* '\(h)/.Trash/'.[!.]* 2>/dev/null; echo Trash force-emptied",
            requiresAdmin: true, dangerous: true))
        t.append(CleanTarget(category: .userEssentials,
            label: "User logs (>14d)",
            detail: "App-emitted logs in ~/Library/Logs older than 14 days.",
            paths: [],
            command: "/usr/bin/find '\(h)/Library/Logs' -type f \\( -name '*.log' -o -name '*.log.*' \\) -mtime +14 -print -delete 2>/dev/null; echo done",
            requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .userEssentials,
            label: "Saved app state (>30d)",
            detail: "~/Library/Saved Application State (TCC-protected → uses admin to enumerate).",
            paths: [],
            command: "/usr/bin/find '\(h)/Library/Saved Application State' -name '*.savedState' -maxdepth 2 -mtime +30 -prune -print -exec /bin/rm -rf {} + 2>/dev/null; echo done",
            requiresAdmin: true, dangerous: false))
        t.append(CleanTarget(category: .userEssentials,
            label: "Diagnostic / Crash reports",
            detail: "User-side ~/Library/Logs/DiagnosticReports.",
            paths: ["\(h)/Library/Logs/DiagnosticReports"],
            command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .userEssentials,
            label: "Mail downloads",
            detail: "Apple Mail attachment cache.",
            paths: ["\(h)/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"],
            command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .userEssentials,
            label: ".DS_Store sweep (home)",
            detail: "Recursively delete .DS_Store files under your home directory.",
            paths: [],
            command: "/usr/bin/find '\(h)' \\( -path '*/Library/Developer*' -o -path '*/.Trash*' -o -path '*/node_modules/*' -o -path '*/.git/*' \\) -prune -o -name .DS_Store -type f -print -delete 2>/dev/null | wc -l | awk '{print \"removed \"$1\" files\"}'",
            requiresAdmin: false, dangerous: false))

        // ---------- App caches ----------
        t.append(CleanTarget(category: .appCaches, label: "User app caches",
            detail: "Per-app caches under ~/Library/Caches/. Apps re-cache on next use.",
            paths: ["\(h)/Library/Caches"],
            command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .appCaches, label: "Sandboxed app caches",
            detail: "Caches inside ~/Library/Containers/*/Data/Library/Caches/.",
            paths: [],
            command: "/usr/bin/find '\(h)/Library/Containers' -path '*/Data/Library/Caches' -maxdepth 5 -type d -print 2>/dev/null | while read p; do /bin/rm -rf \"$p\"/* 2>/dev/null; done; echo done",
            requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .appCaches, label: "WebKit storage",
            detail: "~/Library/WebKit (TCC-protected → admin needed to enumerate).",
            paths: ["\(h)/Library/WebKit"], command: nil, requiresAdmin: true, dangerous: false))
        t.append(CleanTarget(category: .appCaches, label: "HTTP storages",
            detail: "~/Library/HTTPStorages (per-bundle HTTP caches).",
            paths: ["\(h)/Library/HTTPStorages"], command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .appCaches, label: "Cookies",
            detail: "~/Library/Cookies (TCC-protected → admin needed). Logs you out of some apps.",
            paths: ["\(h)/Library/Cookies"], command: nil, requiresAdmin: true, dangerous: true))

        // ---------- Browsers ----------
        let browserCaches: [(String, String)] = [
            ("Chrome",          "\(h)/Library/Caches/Google/Chrome"),
            ("Chrome GPU",      "\(h)/Library/Application Support/Google/Chrome/Default/GPUCache"),
            ("Chrome service workers", "\(h)/Library/Application Support/Google/Chrome/Default/Service Worker"),
            ("Edge",            "\(h)/Library/Caches/Microsoft Edge"),
            ("Brave",           "\(h)/Library/Caches/BraveSoftware/Brave-Browser"),
            ("Brave service workers", "\(h)/Library/Application Support/BraveSoftware/Brave-Browser/Default/Service Worker"),
            ("Firefox cache2",  "\(h)/Library/Caches/Firefox"),
            ("Safari cache",    "\(h)/Library/Caches/com.apple.Safari"),
            ("Arc cache",       "\(h)/Library/Caches/company.thebrowser.Browser"),
            ("Vivaldi",         "\(h)/Library/Caches/com.vivaldi.Vivaldi"),
            ("Opera",           "\(h)/Library/Caches/com.operasoftware.Opera"),
            ("Helium",          "\(h)/Library/Caches/net.imput.helium"),
            ("Comet",           "\(h)/Library/Caches/com.perplexity.comet"),
            ("Orion",           "\(h)/Library/Caches/com.kagi.kagimacOS"),
        ]
        for (name, path) in browserCaches {
            t.append(CleanTarget(category: .browsers, label: name,
                detail: "Browser cache. Pages re-download.",
                paths: [path], command: nil, requiresAdmin: false, dangerous: false))
        }

        // ---------- Developer tools ----------
        t.append(CleanTarget(category: .devTools, label: "npm cache",
            detail: "Run `npm cache clean --force` and prune log directories.",
            paths: ["\(h)/.npm/_logs", "\(h)/.npm/_cacache/tmp"],
            command: "command -v npm >/dev/null && /opt/homebrew/bin/npm cache clean --force 2>&1 || echo 'npm not installed'",
            requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .devTools, label: "pnpm store",
            detail: "Run `pnpm store prune`.",
            paths: [],
            command: "command -v pnpm >/dev/null && /opt/homebrew/bin/pnpm store prune 2>&1 || echo 'pnpm not installed'",
            requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .devTools, label: "Yarn cache",
            detail: "Classic Yarn cache + Yarn Berry cache.",
            paths: ["\(h)/.yarn/cache", "\(h)/Library/Caches/Yarn", "\(h)/.yarn/berry/cache"],
            command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .devTools, label: "Bun cache",
            detail: "Run `bun pm cache rm`.",
            paths: ["\(h)/.bun/install/cache"],
            command: "command -v bun >/dev/null && bun pm cache rm 2>&1 || echo 'bun not installed'",
            requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .devTools, label: "pip cache",
            detail: "Run `pip3 cache purge` and clear poetry/uv caches.",
            paths: ["\(h)/.cache/pip", "\(h)/.cache/poetry", "\(h)/.cache/uv"],
            command: "command -v pip3 >/dev/null && pip3 cache purge 2>&1 || true",
            requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .devTools, label: "Python tooling caches",
            detail: "ruff, mypy, pytest, jupyter runtime caches.",
            paths: ["\(h)/.cache/ruff", "\(h)/.cache/mypy", "\(h)/.pytest_cache", "\(h)/.jupyter/runtime"],
            command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .devTools, label: "AI/ML caches",
            detail: "huggingface, torch, tensorflow, wandb caches. Large but re-downloadable.",
            paths: ["\(h)/.cache/huggingface", "\(h)/.cache/torch", "\(h)/.cache/tensorflow", "\(h)/.cache/wandb"],
            command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .devTools, label: "Docker buildx cache",
            detail: "~/.docker/buildx/cache. Tip: also run `docker system prune -a --volumes`.",
            paths: ["\(h)/.docker/buildx/cache"], command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .devTools, label: "Frontend build caches",
            detail: "TS, electron, vite, webpack, parcel, eslint, prettier, turbo.",
            paths: [
                "\(h)/.cache/typescript", "\(h)/.cache/electron", "\(h)/.cache/node-gyp",
                "\(h)/.node-gyp", "\(h)/.turbo/cache", "\(h)/.vite/cache",
                "\(h)/.cache/vite", "\(h)/.cache/webpack", "\(h)/.parcel-cache",
                "\(h)/.cache/eslint", "\(h)/.cache/prettier"
            ], command: nil, requiresAdmin: false, dangerous: false))

        // ---------- Language toolchains ----------
        t.append(CleanTarget(category: .devLanguages, label: "Go module + build cache",
            detail: "`go clean -modcache -cache`.",
            paths: [],
            command: "command -v go >/dev/null && /opt/homebrew/bin/go clean -modcache -cache 2>&1 || echo 'go not installed'",
            requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .devLanguages, label: "Cargo registry/git cache",
            detail: "Re-downloaded as needed.",
            paths: ["\(h)/.cargo/registry/cache", "\(h)/.cargo/git", "\(h)/.rustup/downloads"],
            command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .devLanguages, label: "Maven local repo",
            detail: "~/.m2/repository (large; re-downloads on next mvn).",
            paths: ["\(h)/.m2/repository"], command: nil, requiresAdmin: false, dangerous: true))
        t.append(CleanTarget(category: .devLanguages, label: "Gradle caches",
            detail: "~/.gradle/caches and ~/.gradle/daemon. Builds will repopulate.",
            paths: ["\(h)/.gradle/caches", "\(h)/.gradle/daemon"], command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .devLanguages, label: "SBT / Ivy",
            detail: "~/.sbt and ~/.ivy2/cache.",
            paths: ["\(h)/.sbt", "\(h)/.ivy2/cache"], command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .devLanguages, label: "SwiftPM library cache",
            detail: "SwiftPM downloaded artifact cache.",
            paths: ["\(h)/.cache/swift-package-manager", "\(h)/Library/Caches/org.swift.swiftpm"],
            command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .devLanguages, label: "Conda/Anaconda packages",
            detail: "~/.conda/pkgs and ~/anaconda3/pkgs.",
            paths: ["\(h)/.conda/pkgs", "\(h)/anaconda3/pkgs"], command: nil, requiresAdmin: false, dangerous: false))

        // ---------- Xcode & Simulator ----------
        t.append(CleanTarget(category: .xcode, label: "Xcode DerivedData",
            detail: "Build intermediates from every Xcode/SwiftPM project.",
            paths: ["\(h)/Library/Developer/Xcode/DerivedData"], command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .xcode, label: "Xcode Archives",
            detail: "Shipped/released app archives. Delete only if you don't need to re-symbolicate.",
            paths: ["\(h)/Library/Developer/Xcode/Archives"], command: nil, requiresAdmin: false, dangerous: true))
        t.append(CleanTarget(category: .xcode, label: "Xcode iOS DeviceSupport",
            detail: "Re-downloaded on device connect. Often many GB.",
            paths: ["\(h)/Library/Developer/Xcode/iOS DeviceSupport"], command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .xcode, label: "Xcode watchOS DeviceSupport",
            detail: "Watch symbol caches.",
            paths: ["\(h)/Library/Developer/Xcode/watchOS DeviceSupport"], command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .xcode, label: "Xcode tvOS DeviceSupport",
            detail: "tvOS symbol caches.",
            paths: ["\(h)/Library/Developer/Xcode/tvOS DeviceSupport"], command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .xcode, label: "Xcode visionOS DeviceSupport",
            detail: "visionOS symbol caches.",
            paths: ["\(h)/Library/Developer/Xcode/visionOS DeviceSupport"], command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .xcode, label: "Xcode docs cache",
            detail: "DocumentationCache and DocumentationIndex.",
            paths: ["\(h)/Library/Developer/Xcode/DocumentationCache",
                    "\(h)/Library/Developer/Xcode/DocumentationIndex"], command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .xcode, label: "Xcode product cache",
            detail: "~/Library/Developer/Xcode/Products.",
            paths: ["\(h)/Library/Developer/Xcode/Products"], command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .xcode, label: "Xcode device logs",
            detail: "iOS / watchOS device console logs.",
            paths: ["\(h)/Library/Developer/Xcode/iOS Device Logs",
                    "\(h)/Library/Developer/Xcode/watchOS Device Logs"], command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .xcode, label: "CoreSimulator caches/logs",
            detail: "Shared simulator state caches and per-device logs.",
            paths: ["\(h)/Library/Developer/CoreSimulator/Caches",
                    "\(h)/Library/Logs/CoreSimulator"], command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .xcode, label: "Unavailable simulators",
            detail: "Run `xcrun simctl delete unavailable`.",
            paths: [],
            command: "/usr/bin/xcrun simctl delete unavailable 2>&1; echo done",
            requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .xcode, label: "CocoaPods cache",
            detail: "~/Library/Caches/CocoaPods.",
            paths: ["\(h)/Library/Caches/CocoaPods"], command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .xcode, label: "Carthage cache",
            detail: "~/Library/Caches/org.carthage.CarthageKit.",
            paths: ["\(h)/Library/Caches/org.carthage.CarthageKit"], command: nil, requiresAdmin: false, dangerous: false))

        // ---------- Mobile dev ----------
        t.append(CleanTarget(category: .mobileDev, label: "Android build cache",
            detail: "~/.android/build-cache + cache.",
            paths: ["\(h)/.android/build-cache", "\(h)/.android/cache"], command: nil, requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .mobileDev, label: "Expo caches",
            detail: "Various ~/.expo/* caches.",
            paths: ["\(h)/.expo/expo-go", "\(h)/.expo/android-apk-cache",
                    "\(h)/.expo/ios-simulator-app-cache", "\(h)/.expo/native-modules-cache",
                    "\(h)/.expo/schema-cache", "\(h)/.expo/template-cache",
                    "\(h)/.expo/versions-cache"], command: nil, requiresAdmin: false, dangerous: false))

        // ---------- GUI applications ----------
        let appCacheItems: [(String, String)] = [
            ("VS Code logs/cache", "\(h)/Library/Application Support/Code/logs"),
            ("VS Code cache", "\(h)/Library/Application Support/Code/Cache"),
            ("VS Code cached extensions", "\(h)/Library/Application Support/Code/CachedExtensions"),
            ("VS Code cached data", "\(h)/Library/Application Support/Code/CachedData"),
            ("Sublime Text caches", "\(h)/Library/Caches/com.sublimetext.4"),
            ("Zed cache", "\(h)/Library/Caches/Zed"),
            ("Zed logs", "\(h)/Library/Logs/Zed"),
            ("Discord cache", "\(h)/Library/Application Support/discord/Cache"),
            ("Slack cache", "\(h)/Library/Application Support/Slack/Cache"),
            ("Zoom cache", "\(h)/Library/Caches/us.zoom.xos"),
            ("Telegram cache", "\(h)/Library/Caches/ru.keepcoder.Telegram"),
            ("MS Teams cache", "\(h)/Library/Caches/com.microsoft.teams2"),
            ("WhatsApp cache", "\(h)/Library/Caches/WhatsApp"),
            ("Skype cache", "\(h)/Library/Caches/com.skype.skype"),
            ("Sketch cache", "\(h)/Library/Caches/com.bohemiancoding.sketch3"),
            ("Adobe shared cache", "\(h)/Library/Caches/Adobe"),
            ("Figma cache", "\(h)/Library/Caches/com.figma.Desktop"),
            ("Spotify cache", "\(h)/Library/Caches/com.spotify.client"),
            ("Apple Music cache", "\(h)/Library/Caches/com.apple.Music"),
            ("Notion cache", "\(h)/Library/Caches/notion.id"),
            ("Obsidian cache", "\(h)/Library/Caches/md.obsidian"),
            ("Logseq cache", "\(h)/Library/Caches/com.logseq.app"),
            ("Alfred cache", "\(h)/Library/Caches/com.runningwithcrayons.Alfred"),
            ("Warp cache", "\(h)/Library/Caches/dev.warp.Warp-Stable"),
            ("Ghostty cache", "\(h)/Library/Caches/com.mitchellh.ghostty"),
            ("ChatGPT cache", "\(h)/Library/Caches/com.openai.chat"),
            ("Claude Desktop cache", "\(h)/Library/Caches/com.anthropic.claudefordesktop"),
            ("Claude logs", "\(h)/Library/Logs/Claude"),
            ("The Unarchiver cache", "\(h)/Library/Caches/cx.c3.theunarchiver"),
            ("Steam shader cache", "\(h)/Library/Application Support/Steam/steamapps/shadercache"),
            ("Steam HTML cache", "\(h)/Library/Application Support/Steam/htmlcache"),
            ("Epic Games cache", "\(h)/Library/Caches/com.epicgames.EpicGamesLauncher"),
            ("Battle.net cache", "\(h)/Library/Application Support/Battle.net/Cache"),
            ("Minecraft logs", "\(h)/Library/Application Support/minecraft/logs"),
            ("Quick Look cache reset", ""),
            ("Quick Look thumbnail cache", "\(h)/Library/Caches/com.apple.QuickLook.thumbnailcache"),
        ]
        for (name, path) in appCacheItems {
            if path.isEmpty {
                t.append(CleanTarget(category: .gui, label: name,
                    detail: "Reset QuickLook plugin cache.",
                    paths: [], command: "/usr/bin/qlmanage -r cache 2>&1 | tail -3",
                    requiresAdmin: false, dangerous: false))
            } else {
                t.append(CleanTarget(category: .gui, label: name,
                    detail: "Per-app cache directory.",
                    paths: [path], command: nil, requiresAdmin: false, dangerous: false))
            }
        }

        // ---------- Homebrew ----------
        t.append(CleanTarget(category: .homebrew, label: "brew cleanup",
            detail: "Run `brew cleanup -s --prune=all` + `brew autoremove`.",
            paths: [],
            command: "/opt/homebrew/bin/brew autoremove 2>&1; /opt/homebrew/bin/brew cleanup -s --prune=all 2>&1",
            requiresAdmin: false, dangerous: false))
        t.append(CleanTarget(category: .homebrew, label: "Homebrew cache",
            detail: "~/Library/Caches/Homebrew (downloaded bottles, formula tarballs).",
            paths: ["\(h)/Library/Caches/Homebrew"], command: nil, requiresAdmin: false, dangerous: false))

        // ---------- System (admin) ----------
        t.append(CleanTarget(category: .system, label: "System logs (>14d)",
            detail: "/private/var/log *.log/.gz/.asl older than 14 days.",
            paths: [],
            command: "/usr/bin/find /private/var/log -type f \\( -name '*.log' -o -name '*.gz' -o -name '*.asl' \\) -mtime +14 -print -delete 2>/dev/null; echo done",
            requiresAdmin: true, dangerous: false))
        t.append(CleanTarget(category: .system, label: "System diagnostic logs",
            detail: "/private/var/db/diagnostics older than 14 days.",
            paths: [],
            command: "/usr/bin/find /private/var/db/diagnostics -type f -mtime +14 -print -delete 2>/dev/null; echo done",
            requiresAdmin: true, dangerous: false))
        t.append(CleanTarget(category: .system, label: "System power logs (>14d)",
            detail: "/private/var/db/powerlog.",
            paths: [],
            command: "/usr/bin/find /private/var/db/powerlog -type f -mtime +14 -print -delete 2>/dev/null; echo done",
            requiresAdmin: true, dangerous: false))
        t.append(CleanTarget(category: .system, label: "System crash reports",
            detail: "/Library/Logs/DiagnosticReports.",
            paths: ["/Library/Logs/DiagnosticReports"], command: nil, requiresAdmin: true, dangerous: false))
        t.append(CleanTarget(category: .system, label: "System updates download",
            detail: "/Library/Updates.",
            paths: ["/Library/Updates"], command: nil, requiresAdmin: true, dangerous: false))
        t.append(CleanTarget(category: .system, label: "Time Machine local snapshots",
            detail: "Delete all listed local APFS snapshots.",
            paths: [],
            command: """
            /usr/bin/tmutil listlocalsnapshotdates / 2>/dev/null | /usr/bin/awk 'NR>1 {print $1}' | while read d; do
              [ -n "$d" ] && /usr/bin/tmutil deletelocalsnapshots "$d" 2>&1
            done
            """,
            requiresAdmin: true, dangerous: false))
        t.append(CleanTarget(category: .system, label: "Memory pressure relief (purge)",
            detail: "Run /usr/sbin/purge to free inactive RAM.",
            paths: [], command: "/usr/sbin/purge && echo Memory purged", requiresAdmin: true, dangerous: false))
        t.append(CleanTarget(category: .system, label: "Font registry rebuild",
            detail: "atsutil databases -remove. Skip if browsers running.",
            paths: [],
            command: "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/ATS.framework/Support/atsutil databases -remove 2>&1; echo done",
            requiresAdmin: true, dangerous: false))

        return t
    }
}
