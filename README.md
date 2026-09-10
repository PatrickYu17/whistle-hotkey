# whistle-hotkey

[![Build](https://github.com/PatrickYu17/whistle-hotkey/actions/workflows/build.yml/badge.svg)](https://github.com/PatrickYu17/whistle-hotkey/actions/workflows/build.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014+-lightgrey)
![Swift](https://img.shields.io/badge/swift-5.9-orange)

Press a global key combination anywhere on macOS to run any shell command.

- Small single Swift binary, zero dependencies
- Commands run through `zsh -ilc`, so your real shell environment applies
- Bindings are plain JSON in `~/.config/whistle-hotkey/`
- Everything runs locally: no network, no analytics, no Accessibility permission

## Requirements

macOS 14+ with Xcode Command Line Tools (`xcode-select --install`).

## Quick start

```sh
git clone https://github.com/PatrickYu17/whistle-hotkey.git
cd whistle-hotkey
make install      # builds and installs whistle-hotkey (+ aliases whk, whistlehk, whistle-hk)
whistle-hotkey    # starts the daemon detached; a bolt appears in the menu bar
```

Run `whistle-hotkey --foreground` to keep it attached to your terminal, or `whistle-hotkey install` to start it at login (LaunchAgent).

## Use

```sh
whistle-hotkey bind         # paste a command, then press the key combo
whistle-hotkey list         # show bindings
whistle-hotkey rm <id>      # remove a binding
whistle-hotkey enable <id>   # re-enable a disabled binding
whistle-hotkey disable <id>  # disable a binding without removing it
whistle-hotkey terminal     # show or set the terminal app
```

- `bind` reads multi-line commands (blank line or Ctrl-D to finish), then records the key combo in your terminal. Esc cancels, Cmd can't be recorded (the menu bar's Change Hotkey… recorder can). Combos need a modifier; bare F-keys are the exception. Recording assumes a US keyboard layout.
- If another app already owns the combo, `bind` warns and the menu marks the binding ⚠.
- After recording, choose whether the command runs in a visible terminal window (for TUIs like `htop`). Whether the window stays open afterwards depends on the terminal.
- `whistle-hotkey terminal ghostty|iterm2|terminal|command-file` picks the app (default `auto`). Any other terminal works via a template, e.g. `whistle-hotkey terminal custom 'kitty --hold zsh -ilc "$1"'`, where `$1` is your command.
- The menu bar shows every binding as a submenu: Run, Edit Command…, Change Hotkey…, Disable (or Enable), and Remove… (with confirmation). Editing the command or changing the hotkey happens in small dialogs right in the menu bar itself.
- Config changes, including external edits of `config.json`, are picked up within a couple of seconds.
- Disabled bindings are grayed out with a "(disabled)" marker and stop triggering.

## Permissions

Hotkeys need no grant. Terminal-mode bindings send Apple Events to your terminal, so macOS may ask you to allow that once (System Settings → Privacy & Security → Automation).

## Development

```sh
make test     # parser + config regression tests
make app      # build build.noindex/Whistle-Hotkey.app
make run      # build and launch
make clean    # remove build output
```

SwiftPM + Makefile only, no Xcode project. See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR.

## License

[MIT](LICENSE).
