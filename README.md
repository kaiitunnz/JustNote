# JustNote

A macOS menu-bar app for plain-text notes. It stays in the menu bar, opens as a compact Liquid Glass panel, and autosaves every edit.

## What it does

- Creates and deletes plain-text notes.
- Navigates all notes from the menu-bar panel.
- Autosaves edits to `.txt` files.
- Persists selected note, pinned notes, and recently opened notes.
- Keeps pinned and unpinned notes in separate drag-movable sections.
- Supports a draggable sidebar/editor divider.
- Toggles soft wrapping so hard newlines are easier to distinguish from wrapped text.
- Reveals the storage folder in Finder from the footer path.
- Can uninstall itself by clearing Application Support, moving the app bundle to the Trash, and quitting.

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
