# Bailong Desktop Pet — English Edition

A tiny dragon companion for your Mac, with English menus, settings, dialogue, and Codex task notifications.

This is an English edition of [Joseph Blue's native Swift port](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift), based on upstream **0.7.4**. The original character and desktop pet are by [jingh12312-rgb (Feng Yin)](https://github.com/jingh12312-rgb/bailong-desktop-pet). This is an unofficial, fan-made project and is not affiliated with OpenAI.

Current English version: **0.8.0-dev.1**. See [English releases](https://github.com/ruyeli/bailong-desktop-pet-english/releases) for published builds. The upstream [Chinese documentation](README.zh-CN.md) remains available for reference; its download links point to the original Chinese edition.

## English edition

- English app menus, settings and settings search, chat windows, task alerts, error messages, and accessibility labels.
- English names for all 35 animations, plus translated default interaction and work dialogue.
- **Introduce Myself** in the pet's right-click menu plays the existing wave animation and says:

  > Hi! I'm Bailong (白龙), a fan-made chibi dragon girl inspired by ChatGPT! My hairpin and belt bear OpenAI logos. 🐉

- Your custom pet name, your name, custom dialogue, and conversation history are retained. Existing custom dialogue takes priority over the new defaults.
- Dialogue variables use `{userName}`, `{petName}`, and `{nickname}`. The Chinese variable names from previous versions remain supported and migrate only in template fields.
- Update checks point to this English fork.

User messages, saved history, and responses received from Codex are displayed in their original language. The English edition does not translate your conversations.

## Requirements and use

macOS 14 or later. Codex features require Codex to be installed and signed in on the same Mac. The companion is a separate native application that follows Codex activity.

Place **Bailong Desktop Pet.app** in Applications, then open it. Builds produced by the included scripts are locally signed, not notarized. If macOS blocks a downloaded build, follow [Apple's instructions for opening an app](https://support.apple.com/en-us/102445).

Quit the previous version before opening this edition. Both editions use the same application identity, settings, and local data at `~/Library/Application Support/BailongPetAppKit`. The app prevents two copies from running against the same data. Existing startup registrations are updated when you launch the new app; no new startup option is enabled automatically.

| Action | Default behavior |
| --- | --- |
| Single-click the pet | Random animation and task overview |
| Double-click the pet | Check Codex usage |
| Right-click | Open the pet menu |
| Double right-click | Open quick chat |
| Right-click → Introduce Myself | Wave and show the introduction |
| Command + Enter | Send a message |
| Command + comma | Open settings |
| Command + Q | Close the current interface; the pet keeps running |
| Pet menu → Quit Bailong Desktop Pet | Quit the application |

Settings let you change names and dialogue, animation frequency, movement, appearance, sounds, message timing, and startup behavior. Task approvals still require an explicit choice; stopping a task is separate from closing a window.

## Build from source

Install Apple Command Line Tools or Xcode. This edition supports building with Swift 6.0 / the macOS 15 SDK; newer appearance APIs are enabled only with a sufficiently recent compiler and macOS version. Builds using older tools use ordinary AppKit materials.

Animation files are not stored in Git. For the matching upstream 0.7.4 assets, download its [Apple Silicon application](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/releases/tag/%E7%99%BD%E9%BE%99%E6%A1%8C%E5%AE%A0Swiftv0.7.4), extract it, and copy resources as follows:

| From the original app's `Contents/Resources` | Into this repository |
| --- | --- |
| `outputs/白龙桌宠素材/` | `local-assets/native-hevc/catalog/` |
| `sounds/` | `local-assets/sounds/` |
| `glass-symbols/` | `local-assets/glass-symbols/` |
| `BailongPet.icns` | `local-assets/BailongPet.icns` |
| `openai-logo.png` | `local-assets/openai-logo.png` |

Keep the original asset filenames. Animation playback uses native HEVC with Alpha through AVFoundation; FFmpeg is not required.

```sh
./scripts/build.sh arm64            # Apple Silicon app
./scripts/build.sh x86_64           # Intel app; not verified on Intel hardware
./scripts/run-dev.sh --build-only   # Development binary only
./scripts/run-dev.sh                # Build and run for development
```

The packaged app is written to `dist/native-hevc/<VERSION>/<architecture>/Bailong Desktop Pet.app`. You can also use `build.command`, `launch.command`, and `run-dev.command`.

## Validation

The English build has been compiled, installed, and launched on Apple Silicon with macOS 15.0. Checked animated playback, English settings and search, preservation of custom names/dialogue, model loading in the chat window, and the existing launch-with-Codex registration. Targeted checks also cover legacy template migration, attachment placeholders, and the 35-animation catalog. Intel hardware and the full set of Codex task/approval flows have not been tested.

## Credits and source history

All upstream authorship and Git history are preserved. Character art, animations, sounds, icons, and software components retain their original attribution and terms. This fork does not add a license for upstream material. See [Sources and Architecture](docs/来源与架构.md) and the app's About page for the original credits.

Report English edition issues in [this repository](https://github.com/ruyeli/bailong-desktop-pet-english/issues), including the app version, macOS version, and reproduction steps. Avoid posting private conversations or credentials.
