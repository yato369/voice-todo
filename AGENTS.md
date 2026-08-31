# voice-todo

## Purpose

A free, local-first iOS voice memo to-do app. User can record a voice memo
(transcribed via Apple Speech framework) or type text directly, save it as a
checkable to-do item, and the item automatically appears in the app's
built-in calendar. Reminders and system calendar sync come later. Built for
personal use on iOS 26.6, distributed via Sideloadly free signing (iOS 26.6; AltStore incompatible on this OS version).

## Structure

- `docs/`: project documents (MVP, PRD, SETUP, decisions)
- `prototype/`: standalone `voice-todo-prototype.html` — a high-fidelity, interactive HTML mirror of the iOS UI, for quick browser-based validation on Windows before committing/building
- `VoiceTodo/`: iOS project source
  - `project.yml`: XcodeGen config (generates `VoiceTodo.xcodeproj`)
  - `VoiceTodoApp/`: main app target
    - `Models/`: data models (TodoItem — single source of truth)
    - `Services/`: services (AudioRecorder, SpeechTranscriber, StorageService, NotificationService)
    - `Views/`: SwiftUI views (MainTabView, RecordView, TodoListView, CalendarView, TodoDetailView, ReminderEditView, SettingsView)
- `.github/workflows/build.yml`: builds unsigned IPA on free macOS GitHub runner

## Commands

- Generate Xcode project (macOS only): `xcodegen generate` in `VoiceTodo/`
- Build unsigned IPA (macOS only): workflow in `.github/workflows/build.yml`
- Local code review / checks: none needed — Swift sources, no build available on Windows
- On this Windows machine: edit code only; never try to build iOS locally

## Development Flow (Windows)

- Code changes are committed on this Windows machine.
- Push to GitHub `main` → GitHub Actions compiles on a free macOS runner → download `VoiceTodo-ipa` artifact → install via Sideloadly per `docs/SETUP.md`.
- Every committed change must remain buildable by `xcodegen generate` + `xcodebuild archive` (validated by CI).

## Conventions

- Keep code and file names in English.
- Follow a single-source-of-truth design: one record is both a to-do and a
  calendar item; list and calendar views render the same data, so deletion is
  naturally consistent on both sides. Do not introduce a separate sync layer.
- Services are protocol-based (`StorageServiceProtocol`, `SpeechProtocol`)
  so future CloudKit / system-calendar integration only swaps an
  implementation without touching business code.
- Local storage via SwiftData. Do not add cloud dependencies in MVP.
- Keep `prototype/voice-todo-prototype.html` in sync with the SwiftUI views: after any UI/feature change, update the prototype so it can be validated in the browser first.
- Update this file when project structure or commands change.
- After any feature change or refactor, sync the update to the project memory file (`project_memory.md`) and this file (`AGENTS.md`) as applicable. Ask the user to confirm before committing the memory/doc sync.
