# JustNote

A macOS menu-bar app for plain-text notes. It stays in the menu bar, opens as a compact Liquid Glass panel, and autosaves every edit.

## What it does

- Creates and deletes plain-text notes.
- Navigates all notes from the menu-bar panel.
- Autosaves edits to `.txt` files.
- Persists selected note, pinned notes, and recently opened notes.
- Keeps pinned notes at the top of the main note list.

Notes live in:

```sh
~/Library/Application Support/JustNote/Notes
```

App state lives beside them in:

```sh
~/Library/Application Support/JustNote/state.json
```

## Build

Requires Xcode and [XcodeGen](https://github.com/yonyz/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -project JustNote.xcodeproj -scheme JustNote -configuration Debug build
```

`project.yml` is the source of truth; `JustNote.xcodeproj` is generated and git-ignored. Debug builds are unsigned for day-to-day local development.

## Test

```sh
xcodebuild test -project JustNote.xcodeproj -scheme JustNote \
  -configuration Debug -derivedDataPath build -destination 'platform=macOS'
```

The tests inject a temporary storage directory and cover first-run creation, autosave, recent-note order, pin persistence, and delete selection behavior.
