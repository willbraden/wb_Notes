# wb_Notes

A floating notes window for WoW Forever. Write plain text with light markdown, and read it over the game next to your quest tracker.

## Features

- **Markdown:** `#` headings, `-` bullets, `1.` numbered lists, `- [ ]` tasks you can tick, `**bold**`, `*italic*`, `` `code` ``, `>` quotes and `---` dividers.
- **Collapsible headings:** click a heading's button to fold its section. Folds are remembered.
- **Stock look:** the title bar, headings, buttons and text match the game's objective tracker.
- **Default mode (padlock locked):** no background and click-through, so it sits over the game like the tracker. Task boxes, fold buttons and the mouse wheel still work. The scrollbar fades to half opacity when idle, and a jump-to-top button flashes when you're scrolled down.
- **Edit mode (padlock unlocked):** a solid window you can click into, move and resize.
- **Fold the whole window** down to its title bar with the title bar button.
- **Autosave and undo:** saves as you type. Ctrl+Z to undo, Ctrl+Y or Ctrl+Shift+Z to redo.
- **Minimap button:** click to show or hide the notes. Drag it around the minimap edge.

Notes are saved account-wide.

## Commands

- `/wbnotes`: show or hide the notes
- `/wbnotes reset`: move the window back to the center at its default size
- `/wbnotes minimap`: hide or show the minimap button

You can also set a keybind under Key Bindings > AddOns.

## Install

Copy the `wb_Notes` folder into `World of Warcraft/_forever_/Interface/AddOns/`.
