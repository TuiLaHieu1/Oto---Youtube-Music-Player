# AGENTS.md

> **Repository Guidance for AI Coding Agents (Codex & Pair Programmers)**  
> **Project:** **Oto** (音)  
> This project is a native **iOS & iPadOS** client for YouTube Music, built with **Swift 6** and **SwiftUI**, delivering an Apple Music-grade player experience with multi-source synchronized lyrics.

---

## 1. Core Principles & Guardrails

- **Zero Credential Exposure:** Never print, log, hardcode, or commit real Google credentials (`SAPISID`, `SSID`, auth tokens, cookies, or user profile emails). Always use mock values (`"REDACTED"`, `"mock-auth-token"`) in test fixtures, mocks, and logs.
- **Strict Concurrency (Swift 6):** Every class marked `@Observable` MUST be isolated to `@MainActor`. All background network tasks must use structured concurrency (`Task`, `async/await`, `actor`) and pass `Sendable` types across actor boundaries.
- **API-over-WebView:** Never use a WebView to scrape metadata, search results, or browse feeds. Use `YTMusicClient` (Innertube JSON API) directly. `WKWebView` is strictly reserved for:
  1. Google authentication session capture.
  2. Protected audio playback (Widevine DRM).
- **Background Audio Preservation:** Never destroy, re-create, or reload the root DOM of the `SingletonPlayerWebView` during track changes. Re-creating the WebView drops the active audio session, causing iOS to terminate background playback.
- **Minimal Dependencies:** Prefer native Apple frameworks (`SwiftUI`, `AVFoundation`, `MediaPlayer`, `SwiftData`, `WebKit`). Do not introduce external dependencies without explicit approval from the developer.

---

## 2. Coding Rules & Project Conventions

| Avoid | Use | Reason |
| :--- | :--- | :--- |
| `print(...)` or `NSLog(...)` | `Logger(subsystem:category:)` / `os_log` | High-frequency logging harms battery life and risks leaking sensitive API tokens. |
| Force unwraps (`!`) | `guard let`, `if let`, or default fallbacks | Prevents runtime crashes from unexpected YouTube API JSON mutations. |
| `DispatchQueue.main.async` | `@MainActor` or `MainActor.run { ... }` | Idiomatic Swift 6 concurrency. |
| `.onAppear { Task { } }` | `.task { ... }` | Automatically handles task cancellation when the view leaves the hierarchy. |
| `NavigationView` | `NavigationStack` / `NavigationSplitView` | Modern iOS/iPadOS navigation standard. |
| Full WebView reloads on track change | JS Bridge `player.loadVideoById(id)` | Drastically reduces memory consumption and prevents audio glitches. |

---

## 3. Architecture Blueprint

```
AppTarget/
├── App/                → App entry point, AppDelegate (AudioSession setup), SceneDelegate
├── Presentation/
│   ├── Navigation/     → TabView (iOS), NavigationSplitView (iPadOS)
│   ├── Player/         → MiniPlayer, FullscreenPlayer, MeshGradientBackground, QueueView
│   ├── Lyrics/         → SyncedLyricsView, LyricLineRow, LyricsScroller
│   ├── Home/           → HomeFeedView, QuickPickShelf, ListenAgainRow
│   ├── Explore/        → ExploreView, ChartsSection, MoodsGrid
│   └── Library/        → LibraryView, LikedSongsView, PlaylistsView
├── ViewModels/         → @MainActor @Observable ViewModels (Player, Lyrics, Home, Search)
├── Services/
│   ├── Audio/          → AudioSessionManager, NowPlayingManager (Lock Screen/Dynamic Island)
│   ├── WebKit/         → SingletonPlayerWebView, WebKitManager, CookieStorage (Keychain)
│   ├── API/            → YTMusicClient, RequestBuilder, EndpointHandlers
│   │   └── Parsers/    → HomeParser, ExploreParser, PlaylistParser, SearchParser
│   └── Lyrics/         → MultiSourceLyricsService (LRCLIB, Musixmatch, YTM Fallback)
└── Models/             → Song, Album, Artist, Playlist, LyricsLine, PlaybackState
```

---

## 4. Multi-Source Lyrics Engine Rules

When resolving lyrics for a song, adhere strictly to this priority pipeline:

```
[Now Playing Song] 
      │
      ▼
┌───────────────┐   Found Sync (.lrc)
│  LRCLIB API   │ ──────────────────────► Return Synced Lyrics
└───────┬───────┘
        │ (404 / No Sync)
        ▼
┌───────────────┐   Found Sync
│  Musixmatch   │ ──────────────────────► Return Synced Lyrics
└───────┬───────┘
        │ (Not found)
        ▼
┌───────────────┐   Has Plain Text
│ YouTube Music │ ──────────────────────► Return Plain Text Lyrics
└───────┬───────┘
        │ (Empty)
        ▼
[Display "No Lyrics Available"]
```

- Clean up song titles before querying lyrics: Strip out strings like `"(Official Music Video)"`, `"[Lyric Video]"`, `"(Remastered)"`, or `"(Audio)"`.
- Smooth lyric scrolling: Use interpolation (`CADisplayLink` or time dampening) so the highlight doesn't jump abruptly.

---

## 5. Proposed Agent Skills (Công cụ gợi ý cho AI Agent)

To maximize autonomy and velocity, the AI coding agent should be equipped with the following specialized skills:

### Skill 1: `api-exploration`
- **Purpose:** Test and inspect real YouTube Music Innertube and LRCLIB responses before writing or modifying Swift parsers.
- **Workflow:** Execute lightweight CLI test requests using `curl` or a standalone Swift CLI tool to verify JSON response schemas. Prevents parsing errors due to undocumented schema changes.

### Skill 2: `apple-music-ui`
- **Purpose:** Guidelines and reusable templates for replicating Apple Music's signature design patterns.
- **Content:**
  - Shader and Mesh Gradient configurations (`SwiftUI.MeshGradient` on iOS 18+ or Metal Shader fallback for iOS 17).
  - Floating bottom bar and smooth interactive dismissible sheet physics.
  - Haptic feedback patterns using `UIImpactFeedbackGenerator`.

### Skill 3: `audio-session-debug`
- **Purpose:** Diagnose and debug iOS audio interruptions, routing, and lock-screen metadata.
- **Content:**
  - Checklists for `AVAudioSessionInterruptionNotification` (handling phone calls, Siri, alarms).
  - Verifying `MPNowPlayingInfoCenter` dictionary keys and artwork size limits.
  - Ensuring background mode audio watchdog policies are respected.

### Skill 4: `autoreview`
- **Purpose:** Automated self-review before committing any code.
- **Checks:**
  1. Any hardcoded auth tokens or credentials?
  2. Are all `@Observable` classes marked `@MainActor`?
  3. Are there any unsafe force unwraps (`!`)?
  4. Did any code touch `SingletonPlayerWebView` without verifying background playback continuity?

---

## 6. Verification & Quality Assurance

Before marking any task as complete, run:
```bash
# 1. Build validation
xcodebuild -scheme Oto -destination 'platform=iOS Simulator,name=iPhone 16' build

# 2. Run unit tests
xcodebuild test -scheme Oto -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OtoTests

# 3. Code formatting & linting
swiftlint --strict
```
