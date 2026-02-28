# Dicta (macOS) — Premium Menu Bar Dictation

Dicta is a menu bar dictation app for macOS 13+ that behaves like Apple Dictation: press a global hotkey, record, transcribe, and insert into the focused app.

## Build & Run
1. Open `Dicta.xcodeproj` in Xcode 15+.
2. Select the `Dicta` target.
3. Set your signing team if required.
4. Build and run.

Dicta runs as a menu bar app (no Dock icon by default).

## Permissions
Dicta needs:
- Microphone (recording)
- Speech Recognition (Apple Speech transcription)
- Accessibility (optional, only if you choose Accessibility typing)

Use the Diagnostics menu to check status and open System Settings.

## Default Hotkey
- Default: Option + Space (⌥Space)
- Hotkey is configurable in Settings.

### Karabiner suggestion (Fn+Delete → F18)
If you want an Fn+Delete style hotkey, map it to F18 in Karabiner and bind Dicta to F18:
1. Open Karabiner-Elements.
2. Add a Simple Modification: `fn + delete` → `f18`.
3. In Dicta Settings, record F18 as the hotkey.

## Insertion Modes
- **Pasteboard (Cmd+V)**: Default, works in most apps.
- **Accessibility Typing**: Optional advanced mode; requires Accessibility permission.

You can toggle “Restore clipboard after paste” for safety vs speed.

## Troubleshooting
- **Paste not working**: Ensure Accessibility permission is granted (System Settings → Privacy & Security → Accessibility). Some apps require it to post keystrokes.
- **No transcription**: Check Speech Recognition permission and selected language. If on-device is unavailable, Dicta will fall back to server-based recognition.
- **Permissions stuck**: Use Diagnostics → Permissions Status → Open System Settings.
- **Hotkey not firing**: Re-record the shortcut in Settings. Avoid shortcuts used by other apps.

## Debug Bundle
Use **Diagnostics → Export Debug Bundle** to save:
- Rolling logs
- Last 3 audio files
- Settings snapshot (redacted)

## Manual Test Checklist
- Hotkey toggles record/stop in Notes, Discord, Safari address bar, VS Code editor.
- Works after sleep/wake.
- Works when switching audio input devices mid-session.
- Cancels cleanly during transcribing.
- Does not steal focus from current app.
- Does not spam clipboard unexpectedly (when restore is enabled).

## File Structure
- `DictaApp.swift` — SwiftUI app entry.
- `AppDelegate.swift` — Status item, windows, hotkey wiring.
- `MenuBar/` — Status item + menu view model.
- `Hotkey/` — Carbon hotkey registration and key translation.
- `Audio/` — AVAudioEngine recording pipeline.
- `Transcription/` — Transcription protocol + Apple Speech engine.
- `Insertion/` — Pasteboard and Accessibility insertion.
- `Settings/` — Settings model + UI.
- `Diagnostics/` — Logging and debug export.
- `Permissions/` — Permissions checks + onboarding.
- `Utilities/` — State machine, HUD overlay.
