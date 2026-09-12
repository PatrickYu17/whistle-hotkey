# Contributing

Thanks for considering a contribution. Keep it small and simple; that's the point of Whistle-Hotkey.

## Before a pull request

1. Run `make test` and make sure it passes.
2. Keep the zero-dependency rule: standard library, AppKit, and Carbon only. A new dependency needs a strong justification in the PR description.
3. Match the existing style: small files, no comments unless they explain a real gotcha, shortest code that works.

Open an issue before starting on anything large.

## Hotkey UI regression checks

When changing capture or menu behavior, run `make run` in a macOS desktop session with two harmless bindings (for example, commands that print a message):

- Open Change Hotkey and press the other binding's shortcut: it should report a duplicate without running a command. Recording the current shortcut should succeed.
- Cancel capture with Esc, then confirm both shortcuts still work. Repeat after saving a new shortcut.
- While capture is open, change the config through the CLI; shortcuts should stay suspended until capture closes. A combination added during capture must be rejected when saving.
- With a conflicting combination that reaches the recorder, verify the confirmation sheet: Return accepts, Esc cancels the sheet, and typing another shortcut does not record it. After cancelling the sheet, capture should resume.
- Disable and re-enable a binding from its submenu; verify its appearance, persistence, and whether its shortcut fires.
- Edit a multiline command, cancel another edit, and cancel/confirm removal; verify the resulting config and menu.
