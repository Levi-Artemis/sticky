# Sticky Notes

A lightweight macOS sticky notes app built with Swift and SwiftUI.

Sticky Notes provides floating note windows, inline images, basic rich-text formatting, screenshot capture, and import/export support for both app-native documents and Markdown.

## Features

- Create multiple independent sticky notes.
- Pin notes above normal windows.
- Move and resize notes directly on the desktop.
- Hide the native macOS titlebar controls for a cleaner sticky-note surface.
- Change note colors.
- Edit text with bold, italic, underline, strikethrough, font-size controls, and a plain-text reset.
- Paste images at the current text cursor position.
- Capture a screen selection and insert it into the current note as an image.
- Resize inline images with hover controls:
  - original size
  - fit to note width
  - smaller/larger thumbnail controls
  - left, center, and right alignment
- Click an image to open a movable preview window.
- Zoom image previews with the toolbar buttons or Command + scroll.
- Access notes from the macOS menu bar item.
- Import and export Sticky Notes documents.
- Import and export Markdown, including local image assets.

## Requirements

- macOS 14 or newer.
- Swift 5.9 or newer.
- Xcode Command Line Tools.

Install the command line tools with:

```sh
xcode-select --install
```

## Build

Build the release executable and create a local app bundle:

```sh
./build.sh
```

This creates:

```text
Sticky Notes.app
```

in the repository root.

You can run the local build with:

```sh
open "Sticky Notes.app"
```

## Install

Install the current build to `/Applications`:

```sh
./install.sh
```

The default destination is:

```text
/Applications/Sticky Notes.app
```

You can also install to a custom destination, for example:

```sh
./install.sh "$HOME/Applications/Sticky Notes.app"
```

The install script builds the app, replaces the destination app bundle, and refreshes Launch Services registration when possible.

If Sticky Notes is already running, quit and reopen it after installing.

## Data Storage

Notes are saved locally in the current user's Application Support folder:

```text
~/Library/Application Support/StickyNotes/notes.json
```

The app stores note text, formatting runs, window position, size, color, pin state, and embedded image data.

## Import and Export

The app supports two export formats.

Sticky Notes document:

- Extension: `.stickynotes`
- JSON-based app document format.
- Can contain one note or all notes.
- Preserves note metadata, formatting, and embedded images.

Markdown:

- Extension: `.md`
- Exports the current note.
- Writes image files into a sibling assets folder.
- Preserves supported inline styles using Markdown plus simple HTML tags where needed.

The File menu and the menu bar item both expose import/export actions.

## Development

Common commands:

```sh
swift build
swift build -c release
./build.sh
./install.sh
```

The Swift package target is defined in `Package.swift`, and the app bundle metadata is defined in `Info.plist`.

## Repository Notes

Generated files are intentionally ignored, including:

- `.build/`
- `*.app/`
- `StickyNotes.zip`
- `.DS_Store`
- `.env`

Avoid committing local screenshots, exported archives, app bundles, or private environment files.
