# Clipboard Cloud for macOS

A native macOS client for Clipboard Cloud. It runs in the menu bar, captures
the clipboard and screenshots, encrypts them on the device, and syncs them with
the same account on the web and on other devices.

It is written in SwiftUI and AppKit. There are no web views and no third-party
dependencies.

## Features

- **Menu bar app with an optional window.** The app lives in the menu bar. The
  main window opens at launch and can be reopened from the menu. The Dock icon
  is shown only while the window is open.
- **Automatic clipboard capture.** The general pasteboard is polled every 3
  seconds. Text and images are uploaded, and duplicates are skipped using a
  SHA-256 hash.
- **Screenshot capture.** Screenshots taken with ⌘⇧3 / ⌘⇧4 are uploaded from
  the folder configured in `com.apple.screencapture` (the Desktop by default).
  Screenshots sent straight to the clipboard (⌃⌘⇧4) need no folder access.
- **End-to-end encryption.** Content is encrypted before it leaves the device,
  so the backend only stores ciphertext.
- **History.** Browse, search, filter (text, images, files), copy, open,
  download and delete entries.
- **Manual uploads.** Add text, images, PDF, DOCX and XLSX files. You can drag
  and drop or paste them, up to 10 files per batch.
- **Friends and sharing.** Invite friends by email and share encrypted entries
  with them. Each entry is re-encrypted for each recipient.
- **Menu bar actions.** From the menu bar you can:
  - show the window
  - copy the latest entry
  - pause or resume monitoring
  - check the capture status
  - request screenshot permission
- **Localization.** English, Spanish, Portuguese and Russian.

## Requirements

- macOS 15 or later
- Xcode 16 or later (Swift 6 toolchain)

## Building

Open `ClipboardCloud.xcodeproj` in Xcode and run the `ClipboardCloud` scheme.
Bundle identifier, version, signing, Info.plist keys and the app icon are
configured in the target settings, `Config/Info.plist` and
`Config/Assets.xcassets`.

To produce a release `.app` bundle from the command line:

```sh
./scripts/bundle.sh
open build/ClipboardCloud.app
```

The project is signed to run locally by default. For distribution, select a
development team under Signing & Capabilities, archive with a Developer ID
certificate and notarize the app. The hardened runtime is already enabled.

`Package.swift` is kept so the sources can also be built with `swift build`
and `swift run`. The resulting binary has no Info.plist, so use the Xcode
project for anything beyond quick checks.

## Installing a non-notarized build

Builds that are not notarized are blocked by Gatekeeper when they are
downloaded. After unzipping, remove the quarantine attribute before the first
launch:

```sh
xattr -dr com.apple.quarantine /Applications/ClipboardCloud.app
```

To package a build for distribution, run this from the folder that contains
the app:

```sh
ditto -c -k --sequesterRsrc --keepParent ClipboardCloud.app ClipboardCloud.zip
```

## Configuration

The backend endpoints can be overridden with environment variables:

| Variable               | Description                         |
| ---------------------- | ----------------------------------- |
| `CC_CONVEX_URL`        | Convex deployment URL               |
| `CC_WEB_APP_URL`       | Web app URL                         |
| `CC_EPHEMERAL_SESSION` | Debug builds only. Set it to `1` to skip the Keychain, so the session is not persisted. |

## Security model

The encryption format is compatible with the web client:

- **Data key.** Each account has a random AES-256 data encryption key (DEK). It
  is wrapped with a key derived from the user's password using PBKDF2-SHA256
  (310,000 iterations). Only the wrapped key is stored on the server.
- **Content.** Texts, images and files are encrypted with AES-256-GCM using a
  random 96-bit IV per item.
- **Sharing.**
  - Each user has an ECDH P-256 key pair. The private key is stored encrypted
    with the user's DEK.
  - Shared entries are encrypted with a per-recipient key derived with
    ECDH and HKDF-SHA256.
- **Local storage.** Session tokens and the unwrapped DEK are stored in the
  macOS Keychain.
- **Password changes.** Changing the password re-wraps the DEK without
  re-encrypting the history.

## Permissions

| Permission                        | Purpose                                     |
| --------------------------------- | ------------------------------------------- |
| Files and Folders: Desktop        | Read screenshots saved to the Desktop        |
| Files and Folders: Documents, Downloads | Read screenshots if the capture location points there |

If access is denied, the app explains how to grant it in System Settings,
under Privacy & Security, then Files and Folders.

## Project structure

```
Sources/ClipboardCloud/
  ClipboardCloudApp.swift   App entry point, menu bar and window scenes
  AppModel.swift            Shared state and user actions
  Session.swift             Authentication, token refresh, key unlocking
  SessionStore.swift        Keychain persistence
  ConvexHTTPClient.swift    Convex HTTP API client
  ClipCrypto.swift          AES-GCM, PBKDF2, ECDH and HKDF helpers
  ClipboardPoller.swift     Pasteboard monitoring and upload
  ScreenshotWatcher.swift   Screenshot folder monitoring
  Stores.swift              History, friends and feedback data
  Models.swift              API models
  Localization*.swift       Strings for all supported languages
  Theme.swift               Colors, fonts and reusable controls
  Views/                    SwiftUI screens
  Resources/                Bundled font (Oswald, SIL Open Font License)
Config/
  Info.plist                App Info.plist
  Assets.xcassets           App icon and other assets
ClipboardCloud.xcodeproj    Xcode project
scripts/
  bundle.sh                 Release build and .app packaging
```

## License

The bundled Oswald font is distributed under the SIL Open Font License. See
`Sources/ClipboardCloud/Resources/Oswald-OFL.txt`.
