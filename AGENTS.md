# voice-todo

## Purpose

A free, local-first iOS voice memo to-do app. User records a voice memo,
the app transcribes it to text with Apple Speech framework, saves it as a
checkable to-do item, and the item automatically appears in the app's
built-in calendar. Reminders and system calendar sync come later. Built for
personal use on iOS 26.6, distributed via AltStore free signing.

## Structure

- `docs/`: project documents (MVP, PRD, decisions)
- `VoiceTodo/`: Xcode project (to be created)
  - `VoiceTodoApp/`: main app target
    - `Models/`: data models (VoiceRecord, TodoItem)
    - `Services/`: services (SpeechTranscriber, StorageService, AudioRecorder, NotificationService)
    - `Views/`: SwiftUI views (RecordView, TodoListView, CalendarView, TodoDetailView)
  - `VoiceTodo.xcodeproj`: Xcode project file

## Commands

- Open: `open VoiceTodo/VoiceTodo.xcodeproj`
- Build: Xcode 26, iOS 26.6 simulator / real device
- Verify: build succeeds; run on simulator; Speech framework requires a real device for full testing

## Conventions

- Keep code and file names in English.
- Follow a single-source-of-truth design: one record is both a to-do and a
  calendar item; list and calendar views render the same data, so deletion is
  naturally consistent on both sides. Do not introduce a separate sync layer.
- Services are protocol-based (`StorageServiceProtocol`, `SpeechProtocol`)
  so future CloudKit / system-calendar integration only swaps an
  implementation without touching business code.
- Local storage via SwiftData. Do not add cloud dependencies in MVP.
- Update this file when project structure or commands change.
